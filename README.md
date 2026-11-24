# nomira-image

> **Alpha.** Content and layout of the image may still change.

The base image for nomira recipes: the smallest Arch Linux that bootc
can boot, plus the tools to build nomira images on the machine itself
and switch to them.

```yaml
settings:
  base: ghcr.io/nomira-os/nomira-image:TAG
```

No release has been published yet. Until then only development builds
`sha-<commit>` exist, see
[Packages](https://github.com/orgs/Nomira-OS/packages).

## Content

| Purpose | Packages |
|---|---|
| Base system | `base` |
| Booting with bootc | `linux`, `dracut`, bootc (built from source), `ostree` (a library bootc needs) |
| `bootc install` | `skopeo`, `bubblewrap`, `btrfs-progs`, `e2fsprogs`, `dosfstools` |
| Hardening | `apparmor`, active at boot |
| nomira tools | `podman`, `passt`, `buildkit`, `sudo`, the nomira CLI |

Deliberately not included: network management, firmware, SSH, a desktop
and the boot test with bcvk (it would need QEMU). The recipe chooses
those.

buildkitd runs as root and only on demand: `buildkit.socket` is enabled
and starts the daemon as soon as `sudo nomira switch` talks to it.

## Pinned state

Everything that determines the content is in `versions.env`:

| Variable | Meaning |
|---|---|
| `ARCH_IMAGE` | dated Arch Linux image, such as `archlinux:base-20261122.0.629543`, pinned by digest |
| `BOOTC_REF` | git tag of bootc |
| `NOMIRA_CLI_REF` | git ref of nomira-cli; empty leaves the CLI out |

The date in the tag of `ARCH_IMAGE` is the one date of the image.
`hack/build-args.sh` derives two build arguments from it:

| Derived | Meaning |
|---|---|
| `SNAPSHOT` | that day in the Arch Linux Archive; fixes all package versions |
| `SOURCE_DATE_EPOCH` | midnight UTC of that day; used for reproducible output |

Renovate moves `ARCH_IMAGE` to newer dated images, and with it the
snapshot.

## Reproducibility

Building the same `versions.env` twice should give the same files:

- Every pacman step runs through `files/pacman-build`, which sets the
  install dates in pacman's database to `SOURCE_DATE_EPOCH` and removes
  the log and the package cache. The image has no pacman keyring.
- dracut builds the initramfs with `reproducible=yes`, which uses
  `SOURCE_DATE_EPOCH`.
- CI splits the image into per-package layers with
  [chunkah](https://github.com/coreos/chunkah), which reads pacman's
  database and clamps all timestamps to `SOURCE_DATE_EPOCH`. An update
  to one package changes one layer; unchanged packages keep their layer
  digest across builds.

The `repro` workflow checks this: it builds the image twice without cache
and compares the layers.

## pacman in builds on top

The image ships no pacman keyring. A keyring contains a private signing
key, and one baked into an image is the same key on every machine that
uses it (the Arch images strip it for that reason, which also leaves
their keyring unable to accept new keys). A step that runs pacman sets
up a keyring in a tmpfs, which never ends up in the layer:

```yaml
collect: run --mount=type=tmpfs,target=/etc/pacman.d/gnupg --mount=type=cache,target=/usr/lib/sysimage/cache/pacman/pkg pacman-key --init && pacman-key --populate && pacman -S --needed --noconfirm ${items}
```

## Unified kernel image

nomira builds a unified kernel image (UKI) for every image it builds:
kernel, initramfs and a command line that carries the composefs digest of
the system, in one file. The image brings the tools for it (`bootc
container ukify`, ukify, sbsigntools), so the digest is computed by the
same bootc that checks it at boot. A UKI has no `root=` argument; systemd
finds the root partition by its GPT type, and unlocks it if it is
encrypted. The initramfs build checks that the generator and the
cryptsetup and TPM pieces for this are included.

## First boot

The image leaves locale, keymap, time zone and the root password open, so
systemd-firstboot asks for them on the console at the first boot (root
is `!unprovisioned`). systemd-homed is active, and
systemd-homed-firstboot then asks for the first user; members of `wheel`
may use sudo.

Releases are published as `<version>` and also as
`<version>-<snapshot date>`, for example `0.2.0` and `0.2.0-2026.11.13`.
There is deliberately no `latest` tag.

The mirrorlist in the image points to the same snapshot. A `pacman -S`
in a recipe therefore installs from the same package set as the base
image, without the recipe having to know a date: the tag of the base
image is the package set.

## Boot loader and storage

The image is installed with bootc's **composefs backend** and boots with
**systemd-boot**. `bootc install` picks both on its own: the empty file
`/usr/lib/composefs/setup-root-conf.toml` marks the image as
composefs-native, and without bootupd in the image bootc chooses
systemd-boot, which it installs itself with `bootctl`.

GRUB is not an option on Arch for now: bootc installs it through bootupd,
and bootupd generates its metadata with rpm
([bootupd#468](https://github.com/coreos/bootupd/issues/468)).

Known limits of the composefs backend in bootc 1.17, from its
documentation: no boot counting, so a system that fails to boot does not
fall back on its own (the previous entry is still in the boot menu);
`bootc install --root-ssh-authorized-keys` and install-time `karg-deletes`
are ignored; one EFI system partition, no XBOOTLDR; no
logically bound images. Each switch writes new boot entries; systemd-boot
itself is not updated after the installation yet.

## AppArmor

AppArmor is active in the image: the kernel arguments in
`/usr/lib/bootc/kargs.d/10-apparmor.toml` add it to the `lsm=` list, and
`apparmor.service` loads the profiles from `/etc/apparmor.d` at boot.
Profiles are enforced unless a profile says otherwise. A recipe puts its
own profiles into `/etc/apparmor.d`. `aa-status` shows the state.

bootc itself needs no support for this. Unlike SELinux, AppArmor works
with paths instead of labels on the files.

## CI and releases

- **Every commit on `main`** is built and published as the immutable
  development build `sha-<commit>`.
- **Releases** are cut by hand: start the "release" workflow in the
  Actions tab and choose `beta` or `final`. Version and changelog follow
  from the Conventional Commits, see
  [Nomira-OS/ci](https://github.com/Nomira-OS/ci).
- **New snapshot:** Renovate opens a pull request when a newer dated
  Arch Linux image appears. CI builds the image for the pull request;
  if it passes, Renovate merges it.

All images are signed with cosign and carry a provenance attestation.
The build ends with `bootc container lint`. CI does not boot the image
in a VM yet.

## Building locally

```sh
podman build -f Containerfile \
  $(sh hack/build-args.sh | sed 's/^/--build-arg /') \
  -t localhost/nomira-image .
```

## First boot

The image does not set locale, keymap, time zone or root password. On
the first boot `systemd-firstboot` therefore asks for them on the
console. It only asks for what is still open:

- A recipe that writes the values to `/etc` (`locale.conf`,
  `vconsole.conf`, `localtime`) gets no question for them.
- For unattended installations the values can be passed as systemd
  credentials.
- The kernel argument `systemd.firstboot=off` turns the questions off
  entirely, for tests in a VM for instance.

The prompts have not been tried in a VM yet.

## Notes for recipes

- **Initramfs:** after adding or changing the kernel, kernel modules or
  firmware that is needed early, call `/usr/libexec/nomira-initramfs`.
- **pacman cache:** it lives in `/usr/lib/sysimage/cache/pacman/pkg`,
  not below `/var`. A cache mount must point to this path.
- **`/var`, `/opt`, `/usr/local`, `/home`:** they are not part of the
  image. `/opt`, `/usr/local` and `/home` are links into `/var`, which
  is only filled on the running machine. Files for the image belong in
  `/usr` and `/etc`.

## Licence and origin

EUPL-1.2, see `LICENSES/`; per-file information is in `REUSE.toml`. The
steps that make Arch bootable with bootc come from
[bootcrew/mono](https://github.com/bootcrew/mono) (Apache-2.0). The
`Containerfile` is therefore under both licences, see `NOTICE`.
