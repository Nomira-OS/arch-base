#!/bin/sh
# Where does a packages collector spend its time? Installs the same
# packages on the base image several times, each in a fresh container,
# with one part more each time, and prints what every part costs:
#
#   download    pacman -Sw, into a shared cache (not timed again later)
#   verify      pacman -S --dbonly: signatures and reading the packages,
#               nothing unpacked, no scriptlets, no hooks
#   unpack      pacman -S with every hook masked, minus verify: unpacking
#               and install scriptlets
#   hooks       all hooks except the initramfs one
#   initramfs   the initramfs hook (dracut)
#   layer       what BuildKit's exporter does with the result: tar and
#               zstd level 3 (its default) over every new file
#
# Usage: sh hack/measure-packages.sh IMAGE PACKAGE...
#        sh hack/measure-packages.sh IMAGE --example uki
# ENGINE=podman to use podman instead of docker.
set -eu

image="${1:?usage: $0 IMAGE PACKAGE... | IMAGE --example NAME}"
shift
if [ "${1:-}" = "--example" ]; then
  recipe="$(dirname "$0")/../examples/${2:?example name}/recipe.yml"
  # The contributions to the collector "packages", as the examples write
  # them: packages: [a, b].
  set -- $(sed -n 's/^ *packages: *\[\(.*\)\]/\1/p' "$recipe" | tr ',' ' ')
fi
[ $# -gt 0 ] || { echo "no packages" >&2; exit 2; }

engine="${ENGINE:-docker}"
cache="nomira-measure-pkg-$$"
"$engine" volume create "$cache" > /dev/null
trap '"$engine" volume rm -f "$cache" > /dev/null' EXIT

# One measurement: a fresh container, the keyring set up outside the
# timing, then pacman in the given mode. Prints milliseconds.
inner='
set -eu
mode="$1"; shift
pacman-key --init > /dev/null 2>&1 && pacman-key --populate > /dev/null 2>&1
mask() { # mask every hook, except the one named $1
  mkdir -p /etc/pacman.d/hooks
  for h in /usr/share/libalpm/hooks/*.hook; do
    n="$(basename "$h")"
    [ "$n" = "${1:-}" ] || ln -sf /dev/null "/etc/pacman.d/hooks/$n"
  done
}
args="-S"
case "$mode" in
  download)  args="-Sw" ;;
  verify)    args="-S --dbonly" ;;
  nohooks)   mask ;;
  initramfs) mask 90-nomira-initramfs.hook ;;
  nodracut)  ln -sf /dev/null /etc/pacman.d/hooks/90-nomira-initramfs.hook ;;
esac
touch /tmp/stamp
start=$(date +%s%N)
pacman $args --noconfirm --needed "$@" > /tmp/log 2>&1 || { cat /tmp/log >&2; exit 1; }
end=$(date +%s%N)
echo "$mode $(( (end - start) / 1000000 ))"
if [ "$mode" = full ]; then
  find / -xdev -newer /tmp/stamp \( -type f -o -type l \) -print0 > /tmp/files
  start=$(date +%s%N)
  bytes=$(tar --null -cf - -T /tmp/files 2>/dev/null | zstd -3 -T0 -c | wc -c)
  end=$(date +%s%N)
  echo "layer $(( (end - start) / 1000000 ))"
  echo "files $(tr -cd "\0" < /tmp/files | wc -c)"
  echo "size $(( $(tar --null -cf - -T /tmp/files 2>/dev/null | wc -c) / 1048576 ))"
  echo "compressed $(( bytes / 1048576 ))"
fi
'

measure() {
  "$engine" run --rm -v "$cache:/var/cache/pacman/pkg" "$image" sh -c "$inner" sh "$@"
}

echo "image:    $image" >&2
echo "packages: $*" >&2
results="$(
  measure download "$@"
  measure verify "$@"
  measure nohooks "$@"
  measure nodracut "$@"
  measure initramfs "$@"
  measure full "$@"
)"
get() { printf '%s\n' "$results" | awk -v k="$1" '$1 == k { print $2 }'; }

d=$(get download); v=$(get verify); n=$(get nohooks); nd=$(get nodracut)
i=$(get initramfs); f=$(get full); l=$(get layer)
printf '\n%-30s %8s\n' "part" "ms"
printf '%-30s %8s\n' "download" "$d"
printf '%-30s %8s\n' "verify (signatures, reading)" "$v"
printf '%-30s %8s\n' "unpack and scriptlets" "$(( n - v ))"
printf '%-30s %8s\n' "hooks without initramfs" "$(( nd - n ))"
printf '%-30s %8s\n' "initramfs (dracut)" "$(( i - n ))"
printf '%-30s %8s\n' "install, all of it" "$f"
printf '%-30s %8s\n' "layer: tar and zstd -3" "$l"
printf '\n%s files, %s MiB, %s MiB compressed\n' "$(get files)" "$(get size)" "$(get compressed)"
