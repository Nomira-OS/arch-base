# Example recipes

Recipes built on this image, each in its own directory. Copy one as a
starting point. CI checks every one with `nomira lint`.

| Example | What it is |
|---|---|
| [`minimal`](minimal/recipe.yml) | The base image plus NetworkManager: enough to boot and get online. The [quick start](https://nomira-os.github.io/nomira-web/docs/getting-started/quickstart/) uses it. |
| [`uki`](uki/recipe.yml) | A system for a real machine: firmware, network, SSH, an editor, all languages, and a unified kernel image. The [installation guide](https://nomira-os.github.io/nomira-web/docs/getting-started/installation/) uses it. |

Every image carries its recipe, read-only, in `/usr/share/nomira/recipe`:
the recipe files and everything the recipe copies from its directory.
On the first boot the base image copies it to `/etc/nomira`, where
`nomira build` finds it. Nothing in the recipe has to do that.

## Adapting `uki`

- **`hardware`**: the firmware and microcode your machine needs. Arch
  splits the firmware by vendor (`linux-firmware-intel`,
  `linux-firmware-amdgpu`, `linux-firmware-realtek`, …); see
  [Linux firmware](https://wiki.archlinux.org/title/Linux_firmware) and
  [Microcode](https://wiki.archlinux.org/title/Microcode).
- **`firmware` or `packages`**: both collectors install the same way,
  and the base image rebuilds the initramfs whenever a package changes
  what goes into it, wherever the package is listed. The only difference
  is the build cache: a collector installs all of its packages again when
  one of them changes, so put what rarely changes under `firmware:`.
- **`network`**: NetworkManager is an example; any option from
  [Network configuration](https://wiki.archlinux.org/title/Network_configuration)
  works the same way.
- **Language and keymap** are asked at the first boot; `glibc-locales`
  makes every answer work. To set them in the image instead, copy
  `/etc/locale.conf` and `/etc/vconsole.conf` in a group of `features`.
  The initramfs is only rebuilt by package changes, so for the keymap to
  reach it as well, rebuild it after the copy:
  `run for d in /usr/lib/modules/*/; do dracut --force --tmpdir /tmp --kver "$(basename "$d")" "${d}initramfs.img"; done`.
- **Files**: `copy files/… /etc/…` in any group. The record picks up
  every file the recipe copies.

The tags in the `# syntax=` and `base:` lines are the ones the examples
were last checked with; newer ones are on the
[package pages](https://github.com/orgs/Nomira-OS/packages).
