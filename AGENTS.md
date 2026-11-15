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
  snapshot), `bootc-build`, `bcvk-build`, `cli-build`, `system`.
- `versions.env`: everything that determines the content.
- `files/`: files copied into the image.
- `.github/workflows/build.yml`: build, publish, weekly snapshot bump.

## Build

```sh
. ./versions.env
podman build -f Containerfile \
  --build-arg SNAPSHOT="$SNAPSHOT" \
  --build-arg BOOTC_REF="$BOOTC_REF" \
  --build-arg BCVK_REF="$BCVK_REF" \
  --build-arg NOMIRA_CLI_REF="$NOMIRA_CLI_REF" \
  -t localhost/nomira-image .
```

The build ends with `bootc container lint`. A full build compiles bootc
and takes around 20 minutes without cache.

## Rules

- **Minimalism is the point.** Do not add a package unless bootc cannot
  boot or install without it, or it belongs to the nomira toolchain.
  The boot test (bcvk with QEMU, virtiofsd and openssh) counts as
  toolchain. Network management, firmware and desktops belong in recipes.
- **Everything is pinned in `versions.env`.** `SNAPSHOT` is an Arch Linux
  Archive date and fixes all package versions; the mirrorlist stays in
  the image so recipes on top install from the same state. Do not add
  package sources that bypass the snapshot.
- **Never use `latest`,** neither for images consumed here nor as a
  published tag. The image is tagged with the snapshot date only. GitHub
  Actions are pinned to a commit SHA with the version as a trailing
  comment. Renovate updates `BOOTC_REF`, `BCVK_REF`, `NOMIRA_CLI_REF`, actions and
  digests; the scheduled workflow, not Renovate, moves `SNAPSHOT`.
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
