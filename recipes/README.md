# Recipe parts

Parts of recipes for systems on this image, to import by URL. The base
image itself carries none of them, so a recipe is free to do everything
its own way; these are a start.

| Part | What it adds |
|---|---|
| [`mounts.yml`](mounts.yml) | `settings.mounts`: logs and temporary files to a tmpfs, pacman's downloads and the initramfs cache to BuildKit caches |
| [`packages.yml`](packages.yml) | The collector `packages`, fanning out: resolved by pacman, downloaded by BuildKit, unpacked in up to 64 layers that only change with their own packages, finished by one pacman transaction for database, install scripts and hooks. Imports `mounts.yml` |
| [`services.yml`](services.yml) | The collector `services`: one `systemctl enable`. Imports `packages.yml` |
| [`initramfs.yml`](initramfs.yml) | The phase `initramfs`: the initramfs once more, for configuration copied after the packages (keymap, dracut options); near free when nothing changed. Import it after `services.yml` |
| [`lint.yml`](lint.yml) | The phase `lint`: `bootc container lint` on the finished system |
| [`uki.yml`](uki.yml) | The phases `kernel` and `uki`: a unified kernel image, as bootc builds a sealed image. Needs `services.yml`; import it last |

A recipe imports them by a URL pinned to a commit, so that it builds the
same tomorrow, and adds its own groups. The order of the imports is the
order of the phases: `uki.yml` last, since the unified kernel image has
to be built from the finished system.

```yaml
# syntax=ghcr.io/nomira-os/nomira:sha-…
imports:
  - https://raw.githubusercontent.com/Nomira-OS/arch-base/<commit>/recipes/services.yml
  - https://raw.githubusercontent.com/Nomira-OS/arch-base/<commit>/recipes/lint.yml
settings:
  base: ghcr.io/nomira-os/arch-base:sha-…
build:
  packages: {}            # features comes right after packages
  features:
    network:
      packages: [networkmanager]
      services: [NetworkManager.service]
```

A part imports the parts it builds on relative to its own URL, so
`services.yml` brings `packages.yml` and `mounts.yml` from the same
commit. A phase of the recipe itself, such as `features`, goes after
the phase named before it in the recipe: `packages: {}` in front of it
places it right after `packages`, and so before `services`. Anything a part sets, a recipe can change or remove (`key:
null`), see [Imports](https://github.com/Nomira-OS/nomira#imports). The
[examples](../examples/) use them.
