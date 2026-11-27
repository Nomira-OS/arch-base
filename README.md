# arch-base

> **Alpha.** Content and layout of the image may still change.

nomira's Arch Linux base image: the smallest Arch Linux that bootc can
boot, plus the tools to build nomira images on the machine itself. Other
bases may follow under their own names.

```yaml
settings:
  base: ghcr.io/nomira-os/arch-base:TAG
```

No release has been published yet. Until then only development builds
exist: `sha-<commit>` for every commit on `main`, and `latest` for the
newest of them, see [Packages](https://github.com/orgs/Nomira-OS/packages).

## Content

| Purpose | Packages |
|---|---|
| Base system | `base` |
| Booting with bootc | `linux`, `dracut`, bootc (built from source), `ostree` (a library bootc needs) |
| `bootc install` | `skopeo`, `bubblewrap`, `btrfs-progs`, `e2fsprogs`, `dosfstools` |
| Hardening | `apparmor`, active at boot |
| Applications | `flatpak`, with Flathub preconfigured; applications live in `/var` and survive image updates |
| nomira tools | `buildkit`, `sudo`, `systemd-ukify`, `sbsigntools`, the nomira CLI |

Deliberately not included: network management, firmware, SSH, a
desktop, a container runtime. The recipe chooses those.

buildkitd runs as root and only on demand: `buildkit.socket` is enabled
and starts the daemon as soon as `sudo nomira build` talks to it.

## Recipe parts and examples

The image carries no part of a recipe, so a recipe can do everything its
own way. [`recipes/`](recipes/) holds parts to import by URL instead:
mounts, the collectors `packages` and `services`, a unified kernel image,
`bootc container lint`. A few imports and a recipe is ready to build.

[`examples/`](examples/) holds recipes built on this image and these
parts, from a minimal one to a complete system with a unified kernel
image. CI lints both.

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

Releases are published as `<version>` and also as
`<version>-<snapshot date>`, for example `0.2.0` and `0.2.0-2026.11.13`.
`latest` follows `main` and is meant for trying things out: a recipe
that should build the same tomorrow names a release or a `sha-…` tag.

The mirrorlist in the image points to the same snapshot. A `pacman -S`
in a recipe therefore installs from the same package set as the base
image, without the recipe having to know a date: the tag of the base
image is the package set.

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
collect: run --mount=type=tmpfs,target=/etc/pacman.d/gnupg --mount=type=cache,target=/var/cache/pacman/pkg pacman-key --init && pacman-key --populate && pacman -S --needed --noconfirm ${items}
```

## Unified kernel image

Recipes on top can replace kernel and initramfs with a unified kernel
image (UKI) whose command line carries the composefs digest of the
system. The image brings the tools for it (`bootc container ukify`,
ukify, sbsigntools), so the digest is computed by the same bootc that
checks it at boot. A UKI has no `root=` argument; systemd finds the root
partition by its GPT type, and unlocks it if it is encrypted. The
initramfs build checks that the generator and the cryptsetup and TPM
pieces for this are included.

## First boot

The image leaves locale, keymap, time zone and the root password open, so
`systemd-firstboot` asks for them on the console at the first boot (root
is `!unprovisioned`, which systemd treats as not set). Then
`systemd-homed-firstboot` asks for the first user, who is put into
`wheel`; members of `wheel` may use sudo.

- A recipe that writes the values to `/etc` (`locale.conf`,
  `vconsole.conf`, `localtime`) gets no question for them.
- For unattended installations the values can be passed as systemd
  credentials.
- The kernel argument `systemd.firstboot=off` turns the questions off
  entirely, for tests in a VM for instance.

## Notes for recipes

- **Initramfs:** pacman hooks rebuild `/usr/lib/modules/<kver>/initramfs.img`
  whenever a package changes what goes into it (kernel, firmware, dracut
  modules), with the triggers of Arch's own dracut hooks. Files copied
  without a package (`/etc/vconsole.conf`, say) do not trigger them; run
  `dracut --force --tmpdir /tmp --kver <kver> /usr/lib/modules/<kver>/initramfs.img`
  after such a copy.
- **pacman database, cache and log:** the database is part of the image,
  in `/usr/lib/sysimage/lib/pacman`. Cache and log stay where Arch has
  them, `/var/cache/pacman/pkg` and `/var/log/pacman.log`; the nomira
  frontend gives every run a tmpfs over `/var/cache` and `/var/log`, so
  they never end up in the image. A cache mount at
  `/var/cache/pacman/pkg` keeps downloads across builds.
- **Install dates:** a pacman hook sets them to `SOURCE_DATE_EPOCH`, so
  the package database does not differ between builds.
- **`/var`, `/opt`, `/usr/local`, `/home`:** they are not part of the
  image. `/opt`, `/usr/local` and `/home` are links into `/var`, which
  is only filled on the running machine. Files for the image belong in
  `/usr` and `/etc`.

## Licence and origin

EUPL-1.2, see `LICENSES/`; per-file information is in `REUSE.toml`. The
steps that make Arch bootable with bootc come from
[bootcrew/mono](https://github.com/bootcrew/mono) (Apache-2.0). The
`Containerfile` is therefore under both licences, see `NOTICE`.
