# Recipe parts

Parts of recipes for systems on this image, to import by URL. The base
image itself carries none of them, so a recipe is free to do everything
its own way; these are a start.

| Part | What it adds |
|---|---|
| [`mounts.yml`](mounts.yml) | `settings.mounts`: logs and temporary files to a tmpfs, pacman's downloads to a BuildKit cache |
| [`packages.yml`](packages.yml) | The collector `packages`: one `pacman -S` for everything the groups name, with the keyring in a cache. Imports `mounts.yml` |
| [`services.yml`](services.yml) | The collector `services`: one `systemctl enable`. Imports `packages.yml` |
| [`uki.yml`](uki.yml) | The phases `kernel` and `uki`: a unified kernel image, as bootc builds a sealed image. Imports `services.yml` |
| [`lint.yml`](lint.yml) | The phase `lint`: `bootc container lint` on the finished image. Import it last |

A recipe imports them by a URL pinned to a commit, so that it builds the
same tomorrow, and adds its own groups:

```yaml
# syntax=ghcr.io/nomira-os/nomira:sha-…
imports:
  - https://raw.githubusercontent.com/Nomira-OS/arch-base/<commit>/recipes/services.yml
  - https://raw.githubusercontent.com/Nomira-OS/arch-base/<commit>/recipes/lint.yml
settings:
  base: ghcr.io/nomira-os/arch-base:sha-…
build:
  features:
    network:
      packages: [networkmanager]
      services: [NetworkManager.service]
```

A part imports the parts it builds on relative to its own URL, so
`services.yml` brings `packages.yml` and `mounts.yml` from the same
commit. Anything a part sets, a recipe can change or remove (`key:
null`), see [Imports](https://github.com/Nomira-OS/nomira#imports). The
[examples](../examples/) use them.
