# nomira-image

Das Basis-Image für nomira-Recipes: das kleinste Arch Linux, das bootc
booten kann, dazu die Werkzeuge, um auf der Maschine selbst nomira-Images
zu bauen und darauf umzustellen.

```yaml
settings:
  base: ghcr.io/nomira-os/nomira-image:2026.11.13
```

## Inhalt

| Zweck | Pakete |
|---|---|
| Grundsystem | `base` |
| Booten mit bootc | `linux`, `dracut`, `ostree`, bootc (aus dem Quelltext gebaut) |
| `bootc install` | `skopeo`, `bubblewrap`, `btrfs-progs`, `e2fsprogs`, `dosfstools` |
| Absicherung | `apparmor`, beim Start aktiv |
| nomira-Werkzeuge | `podman`, `passt`, `buildkit`, `sudo`, die nomira-CLI |

Bewusst nicht enthalten: Netzwerkverwaltung, Firmware, SSH, Desktop.
Das wählt das Recipe.

## Fester Stand

Alles, was den Inhalt bestimmt, steht in `versions.env`:

| Variable | Bedeutung |
|---|---|
| `SNAPSHOT` | Datum im Arch Linux Archive (`JJJJ/MM/TT`); legt alle Paketversionen fest |
| `BOOTC_REF` | Git-Tag von bootc |
| `NOMIRA_CLI_REF` | Git-Ref von nomira-cli; leer lässt die CLI weg |

Das Image wird nur unter dem Snapshot-Datum veröffentlicht, etwa
`ghcr.io/nomira-os/nomira-image:2026.11.13`. Einen Tag `latest` gibt es
bewusst nicht.

Die mirrorlist im Image zeigt auf denselben Snapshot. Ein `pacman -S` in
einem Recipe installiert deshalb aus demselben Paketstand wie das
Basis-Image, ohne dass das Recipe ein Datum kennen muss: Der Tag des
Basis-Images ist der Paketstand.

## AppArmor

AppArmor ist im Image aktiv: Die Kernel-Parameter in
`/usr/lib/bootc/kargs.d/10-apparmor.toml` nehmen es in die `lsm=`-Liste
auf, und `apparmor.service` lädt beim Start die Profile aus
`/etc/apparmor.d`. Profile gelten erzwingend, solange ein Profil nicht
selbst etwas anderes festlegt. Eigene Profile legt ein Recipe nach
`/etc/apparmor.d`. Prüfen lässt sich der Zustand mit `aa-status`.

bootc selbst braucht dafür keine eigene Unterstützung. Anders als SELinux
arbeitet AppArmor mit Pfaden statt mit Markierungen an den Dateien.

## CI

`.github/workflows/build.yml` baut bei jedem Push auf `main` und
veröffentlicht nach ghcr. Montags baut ein geplanter Lauf mit dem
Snapshot vom Vortag; erst wenn dieser Build durchgelaufen und
veröffentlicht ist, schreibt er das neue Datum nach `versions.env`.
Ein bestimmtes Datum lässt sich über „Run workflow“ von Hand bauen.

Der Build endet mit `bootc container lint`. Einen Boot-Test in einer VM
gibt es in der CI noch nicht.

## Lokal bauen

```sh
. ./versions.env
podman build -f Containerfile \
  --build-arg SNAPSHOT="$SNAPSHOT" \
  --build-arg BOOTC_REF="$BOOTC_REF" \
  --build-arg NOMIRA_CLI_REF="$NOMIRA_CLI_REF" \
  -t localhost/nomira-image .
```

## Hinweise für Recipes

- **Initramfs:** Nach dem Hinzufügen oder Wechseln von Kernel,
  Kernelmodulen oder früh benötigter Firmware
  `/usr/libexec/nomira-initramfs` aufrufen.
- **pacman-Cache:** Er liegt unter `/usr/lib/sysimage/cache/pacman/pkg`,
  nicht unter `/var`. Ein Cache-Mount muss auf diesen Pfad zeigen.
- **`/var`, `/opt`, `/usr/local`, `/home`:** Sie gehören nicht zum Image.
  `/opt`, `/usr/local` und `/home` sind Verweise nach `/var`, das erst auf
  der laufenden Maschine gefüllt wird. Dateien fürs Image gehören nach
  `/usr` und `/etc`.

## Herkunft

Die Schritte, die Arch mit bootc bootfähig machen, stammen aus
[bootcrew/mono](https://github.com/bootcrew/mono) (Apache-2.0), siehe
`NOTICE`.
