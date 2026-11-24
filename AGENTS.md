# AGENTS.md

Guidance for coding agents (and humans) working in this repository.

## What this is

The base image for nomira recipes: the smallest Arch Linux that bootc can
boot, with AppArmor active, plus the tools to build nomira images on the
machine itself (podman, buildkit, the nomira CLI). Published as
`ghcr.io/nomira-os/arch-base`.

Sibling repositories: `nomira` (BuildKit frontend), `nomira-cli`,
`nomira-web` (reference recipe and website).

## Layout

- `Containerfile`: the whole build. Stages: `base` (Arch synced to the
  snapshot), `bootc-build`, `cli-build`, `system`.
- `versions.env`: everything that determines the content.
  `hack/build-args.sh` turns it into build arguments, deriving the
  snapshot date and `SOURCE_DATE_EPOCH` from the tag of `ARCH_IMAGE`.
- `files/pacman-build`: pacman for the build steps (keyring in a tmpfs,
  retries, reproducible install dates); mounted, not part of the image.
- `files/`: files copied into the image.
- `.github/workflows/`: `ci` (build and publish `sha-<commit>`),
  `release` (manual, beta or final), `repro` (manual: two builds without
  cache, layers compared). Both call the shared workflows in
  `Nomira-OS/ci` and split the image into layers with chunkah.

## Build

```sh
podman build -f Containerfile \
  $(sh hack/build-args.sh | sed 's/^/--build-arg /') \
  -t localhost/arch-base .
```

The build ends with `bootc container lint`. A full build compiles bootc
and takes around 20 minutes without cache.

## Rules

- **Minimalism is the point.** Do not add a package unless bootc cannot
  boot or install without it, or it belongs to the nomira toolchain.
  Network management, firmware, ssh, desktops and the bcvk boot test
  (it needs QEMU) belong in recipes.
- **Everything is pinned in `versions.env`, and there is one date.** The
  date in the tag of `ARCH_IMAGE` is the Arch Linux Archive snapshot and
  `SOURCE_DATE_EPOCH`; never define either a second time. The mirrorlist
  stays in the image so recipes on top install from the same state. Do
  not add package sources that bypass the snapshot.
- **Reproducibility.** Call pacman only through `files/pacman-build`,
  with a tmpfs at `/etc/pacman.d/gnupg`. Never ship a pacman keyring: it
  holds a private key. Order layers by how often they change; the CLI
  comes last.
- **Never use `latest`,** neither for images consumed here nor as a
  published tag. Renovate updates `ARCH_IMAGE` (tag and digest),
  `BOOTC_REF`, `NOMIRA_CLI_REF`, actions and digests.
- **Conventional Commits** for every commit. Version and changelog are
  derived from them; a change to what ends up in the image is at least a
  `fix:`. Releases are cut by hand with the `release` workflow and are
  published as `<version>` and `<version>-<snapshot date>`; never push a
  tag yourself.
- **Licence:** EUPL-1.2 via `REUSE.toml`; the Containerfile is
  `EUPL-1.2 AND Apache-2.0` because of the bootcrew/mono steps.
- **`/var` is not part of the image.** Pacman's database and cache live
  under `/usr/lib/sysimage`. Image content goes to `/usr` and `/etc`.
- **bootc is built without its `selinux` feature,** because Arch has no
  libselinux. AppArmor needs no bootc support.
- **Language:** everything is English: README, docs, code, comments and
  commit messages.
- **Be explicit about what was not verified.** CI lints the image but
  does not boot it. If you could not boot-test a change, say so.

## Attribution

The bootc-on-Arch steps are adapted from bootcrew/mono (Apache-2.0); keep
`NOTICE` accurate when changing them.
