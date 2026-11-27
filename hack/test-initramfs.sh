#!/bin/sh
# Tests files/initramfs against a fake system, with stand-ins for dracut
# and lsinitrd: when it runs dracut, when it takes the cache, and that it
# never stores anything without a cache. Needs GNU find, stat, sha256sum.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
root="$work/root"; cache="$work/cache"; bin="$work/bin"
mkdir -p "$bin" "$root/usr/lib/modules/7.0/kernel" "$root/usr/lib/firmware" \
  "$root/usr/lib/dracut/dracut.conf.d" "$root/usr/bin" "$root/etc"
echo vmlinuz > "$root/usr/lib/modules/7.0/vmlinuz"
echo mod > "$root/usr/lib/modules/7.0/kernel/a.ko"
echo fw > "$root/usr/lib/firmware/a.bin"
echo 'hostonly=no' > "$root/usr/lib/dracut/dracut.conf.d/30.conf"
echo systemd > "$root/usr/bin/systemd"
echo unused > "$root/usr/bin/unused"

# dracut stand-in: the "initramfs" lists the files it took and the epoch;
# one line per call in $work/calls.
cat > "$bin/dracut" <<'EOF'
#!/bin/sh
out="$6"; r="$NOMIRA_INITRAMFS_ROOT"
echo "$5" >> "$CALLS"
{ echo "epoch ${SOURCE_DATE_EPOCH:-}"
  for p in /usr/bin/systemd /usr/lib/modules/$5/kernel/a.ko /usr/lib/firmware/a.bin /etc/vconsole.conf; do
    [ -e "$r$p" ] && echo "$p $(cat "$r$p")"
  done
  echo "/etc/initrd-release generated"
} > "$out"
EOF
# lsinitrd stand-in: --unpack recreates the listed files in the cwd.
cat > "$bin/lsinitrd" <<'EOF'
#!/bin/sh
[ "$1" = --unpack ] || exit 2
grep '^/' "$2" | while read -r p rest; do mkdir -p ".$(dirname "$p")"; echo "$rest" > ".$p"; done
EOF
chmod +x "$bin/dracut" "$bin/lsinitrd"

export PATH="$bin:$PATH" NOMIRA_INITRAMFS_ROOT="$root" CALLS="$work/calls" SOURCE_DATE_EPOCH=100
: > "$CALLS"
img="$root/usr/lib/modules/7.0/initramfs.img"
run() { NOMIRA_INITRAMFS_CACHE="$cache" sh "$here/files/initramfs" > /dev/null; }
calls() { wc -l < "$CALLS" | tr -d ' '; }
expect() { # <name> <calls>
  [ "$(calls)" = "$2" ] || { echo "initramfs: $1: dracut ran $(calls) times, expected $2"; exit 1; }
}

# Without a cache: dracut every time, nothing stored.
NOMIRA_INITRAMFS_CACHE="$work/absent" sh "$here/files/initramfs" > /dev/null
NOMIRA_INITRAMFS_CACHE="$work/absent" sh "$here/files/initramfs" > /dev/null
expect "no cache" 2
[ ! -e "$work/absent" ] || { echo "initramfs: a cache was created"; exit 1; }

mkdir "$cache"
run; expect "first build" 3
first="$(cat "$img")"
rm "$img"
run; expect "unchanged" 3
[ "$(cat "$img")" = "$first" ] || { echo "initramfs: cached image differs"; exit 1; }
touch -d @5 "$img"
run; expect "unchanged, in place" 3
[ "$(stat -c %Y "$img")" = 5 ] || { echo "initramfs: an unchanged initramfs was written again"; exit 1; }

echo unused2 > "$root/usr/bin/unused"
run; expect "file not in the initramfs changed" 3

echo systemd2 > "$root/usr/bin/systemd"
run; expect "binary in the initramfs changed" 4
run; expect "again unchanged" 4

echo fw2 > "$root/usr/lib/firmware/b.bin"
run; expect "firmware added" 5

echo 'compress=zstd' >> "$root/usr/lib/dracut/dracut.conf.d/30.conf"
run; expect "configuration changed" 6

echo 'KEYMAP=de' > "$root/etc/vconsole.conf"
run; expect "vconsole.conf added" 7
echo 'KEYMAP=us' > "$root/etc/vconsole.conf"
touch -d @1 "$root/etc/vconsole.conf"
run; expect "vconsole.conf changed" 8

SOURCE_DATE_EPOCH=200 run; expect "other epoch" 9
run; expect "first epoch again, from the cache" 9

# Older entries are pruned.
for i in 1 2 3 4 5 6 7 8 9 10; do mkdir "$cache/old$i"; touch -d @$i "$cache/old$i"; done
run
[ "$(ls -1 "$cache" | wc -l)" -le 8 ] || { echo "initramfs: cache not pruned: $(ls "$cache" | wc -l) entries"; exit 1; }

# A kernel without vmlinuz loses its initramfs.
rm "$root/usr/lib/modules/7.0/vmlinuz"
run
[ ! -e "$img" ] || { echo "initramfs: kept the initramfs of a removed kernel"; exit 1; }

echo "initramfs: ok"
