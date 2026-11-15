# AGENTS.md

Guidance for coding agents (and humans) working in this repository.

## What this is

The base image for nomira recipes: the smallest Arch Linux that bootc can
boot, with AppArmor active, plus the tools to build nomira images on the
machine itself (podman, buildkit, the nomira CLI). Published as
`ghcr.io/nomira-os/nomira-image:<snapshot date>`.

Sibling repositories: `nomira` (BuildKit frontend), `nomira-cli`,
`nomira-web` (reference recipe and website).

## Layout

- `Containerfile`: the whole build. Stages: `base` (Arch synced to the
  snapshot), `bootc-build`, `cli-build`, `system`.
- `versions.env`: everything that determines the content.
- `files/`: files copied into the image.
- `.github/workflows/`: `ci` (build and publish `sha-<commit>`),
  `release` (manual, beta or final), `snapshot` (weekly snapshot bump).
  All three call the shared workflows in `Nomira-OS/ci`.

## Build

```sh
. ./versions.env
podman build -f Containerfile \
  --build-arg SNAPSHOT="$SNAPSHOT" \
  --build-arg BOOTC_REF="$BOOTC_REF" \
  --build-arg NOMIRA_CLI_REF="$NOMIRA_CLI_REF" \
  -t localhost/nomira-image .
```

The build ends with `bootc container lint`. A full build compiles bootc
and takes around 20 minutes without cache.

## Rules

- **Minimalism is the point.** Do not add a package unless bootc cannot
  boot or install without it, or it belongs to the nomira toolchain.
  Network management, firmware, ssh, desktops and the bcvk boot test
  (it needs QEMU) belong in recipes.
- **Everything is pinned in `versions.env`.** `SNAPSHOT` is an Arch Linux
  Archive date and fixes all package versions; the mirrorlist stays in
  the image so recipes on top install from the same state. Do not add
  package sources that bypass the snapshot.
- **Never use `latest`,** neither for images consumed here nor as a
  published tag. Renovate updates `BOOTC_REF`, `NOMIRA_CLI_REF`, actions
  and digests; the `snapshot` workflow, not Renovate, moves `SNAPSHOT`.
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
- **Languages:** README is German. The Containerfile, comments, commit
  messages and this file are English.
- **Be explicit about what was not verified.** CI lints the image but
  does not boot it. If you could not boot-test a change, say so.

## Attribution

The bootc-on-Arch steps are adapted from bootcrew/mono (Apache-2.0); keep
`NOTICE` accurate when changing them.
