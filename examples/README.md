# Example recipes

Recipes built on this image, each in its own directory. Copy one as a
starting point. CI checks every one with `nomira lint`.

| Example | What it is |
|---|---|
| [`minimal`](minimal/recipe.yml) | The base image plus NetworkManager: enough to boot and get online. The [quick start](https://nomira-os.github.io/nomira-web/docs/getting-started/quickstart/) uses it. |
| [`uki`](uki/recipe.yml) | A system for a real machine: firmware, network, SSH, an editor, all languages, and a unified kernel image whose initramfs is only rebuilt when the packages boot needs change. The [installation guide](https://nomira-os.github.io/nomira-web/docs/getting-started/installation/) uses it. |

## Adapting `uki`

- **`hardware`**: the firmware and microcode your machine needs. Arch
  splits the firmware by vendor (`linux-firmware-intel`,
  `linux-firmware-amdgpu`, `linux-firmware-realtek`, …); see
  [Linux firmware](https://wiki.archlinux.org/title/Linux_firmware) and
  [Microcode](https://wiki.archlinux.org/title/Microcode). Whatever early
  boot needs, disk tools such as `lvm2` included, goes under `boot:`;
  everything else under `packages:`.
- **`network`**: NetworkManager is an example; any option from
  [Network configuration](https://wiki.archlinux.org/title/Network_configuration)
  works the same way.
- **Language and keymap** are asked at the first boot; `glibc-locales`
  makes every answer work. To set them in the image instead, and have
  the initramfs know the keymap, copy `/etc/locale.conf` and
  `/etc/vconsole.conf` in a phase between `boot` and the initramfs stage
  and let the stage start from that phase.
- **Files**: once the recipe copies files, add
  `copy files/ /etc/nomira/files/` to the group `recipe`, so that the
  installed machine has everything it needs to build itself.

The tags in the `# syntax=` and `base:` lines are the ones the examples
were last checked with; newer ones are on the
[package pages](https://github.com/orgs/Nomira-OS/packages).
