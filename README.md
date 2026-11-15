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
| Booting with bootc | `linux`, `dracut`, `ostree`, bootc (built from source) |
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
| `SNAPSHOT` | date in the Arch Linux Archive (`YYYY/MM/DD`); fixes all package versions |
| `BOOTC_REF` | git tag of bootc |
| `NOMIRA_CLI_REF` | git ref of nomira-cli; empty leaves the CLI out |

Releases are published as `<version>` and also as
`<version>-<snapshot date>`, for example `0.2.0` and `0.2.0-2026.11.13`.
There is deliberately no `latest` tag.

The mirrorlist in the image points to the same snapshot. A `pacman -S`
in a recipe therefore installs from the same package set as the base
image, without the recipe having to know a date: the tag of the base
image is the package set.

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
- **New snapshot:** on Mondays the "snapshot" workflow checks whether
  the image builds with the previous day's snapshot and then writes the
  date to `versions.env` as a `fix:` commit. Nothing is published by
  that; the next release picks up the new state.

All images are signed with cosign and carry a provenance attestation.
The build ends with `bootc container lint`. CI does not boot the image
in a VM yet.

## Building locally

```sh
. ./versions.env
podman build -f Containerfile \
  --build-arg SNAPSHOT="$SNAPSHOT" \
  --build-arg BOOTC_REF="$BOOTC_REF" \
  --build-arg NOMIRA_CLI_REF="$NOMIRA_CLI_REF" \
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
