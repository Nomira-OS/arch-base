# nomira-image

> **Alpha.** Inhalt und Aufbau des Images können sich noch ändern.

Das Basis-Image für nomira-Recipes: das kleinste Arch Linux, das bootc
booten kann, dazu die Werkzeuge, um auf der Maschine selbst nomira-Images
zu bauen und darauf umzustellen.

```yaml
settings:
  base: ghcr.io/nomira-os/nomira-image:0.1.0
```

## Inhalt

| Zweck | Pakete |
|---|---|
| Grundsystem | `base` |
| Booten mit bootc | `linux`, `dracut`, `ostree`, bootc (aus dem Quelltext gebaut) |
| `bootc install` | `skopeo`, `bubblewrap`, `btrfs-progs`, `e2fsprogs`, `dosfstools` |
| Absicherung | `apparmor`, beim Start aktiv |
| nomira-Werkzeuge | `podman`, `passt`, `buildkit`, `sudo`, die nomira-CLI |

Bewusst nicht enthalten: Netzwerkverwaltung, Firmware, SSH, Desktop und
der Boot-Test mit bcvk (er bräuchte QEMU). Das wählt das Recipe.

buildkitd läuft als root und nur bei Bedarf: `buildkit.socket` ist
aktiviert und startet den Daemon, sobald `sudo nomira switch` ihn
anspricht.

## Fester Stand

Alles, was den Inhalt bestimmt, steht in `versions.env`:

| Variable | Bedeutung |
|---|---|
| `SNAPSHOT` | Datum im Arch Linux Archive (`JJJJ/MM/TT`); legt alle Paketversionen fest |
| `BOOTC_REF` | Git-Tag von bootc |
| `NOMIRA_CLI_REF` | Git-Ref von nomira-cli; leer lässt die CLI weg |

Releases werden als `<Version>` und zusätzlich als
`<Version>-<Snapshot-Datum>` veröffentlicht, etwa `0.2.0` und
`0.2.0-2026.11.13`. Einen Tag `latest` gibt es bewusst nicht.

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

## CI und Releases

- **Jeder Commit auf `main`** wird gebaut und als unveränderlicher
  Entwicklungsstand `sha-<commit>` veröffentlicht.
- **Releases** entstehen von Hand: im Actions-Tab den Workflow „release“
  starten und `beta` oder `final` wählen. Version und Changelog ergeben
  sich aus den Conventional Commits, siehe
  [Nomira-OS/ci](https://github.com/Nomira-OS/ci).
- **Neuer Snapshot:** Montags prüft der Workflow „snapshot“, ob das Image
  mit dem Snapshot vom Vortag baut, und schreibt das Datum dann als
  `fix:`-Commit nach `versions.env`. Veröffentlicht wird dabei nichts;
  das nächste Release nimmt den neuen Stand mit.

Alle Images sind mit cosign signiert und tragen einen Herkunftsnachweis.
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

## Erster Start

Das Image legt Sprache, Tastaturbelegung, Zeitzone und root-Passwort
nicht fest. Beim ersten Start fragt `systemd-firstboot` deshalb auf der
Konsole danach. Es fragt nur nach dem, was noch offen ist:

- Ein Recipe, das die Werte nach `/etc` schreibt (`locale.conf`,
  `vconsole.conf`, `localtime`), bekommt dafür keine Frage.
- Für unbeaufsichtigte Installationen lassen sich die Werte als
  systemd-Credentials mitgeben.
- Der Kernel-Parameter `systemd.firstboot=off` schaltet die Fragen ganz
  ab, etwa für Tests in einer VM.

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

## Lizenz und Herkunft

EUPL-1.2, siehe `LICENSES/`; die Angaben je Datei stehen in `REUSE.toml`.
Die Schritte, die Arch mit bootc bootfähig machen, stammen aus
[bootcrew/mono](https://github.com/bootcrew/mono) (Apache-2.0). Das
`Containerfile` steht deshalb unter beiden Lizenzen, siehe `NOTICE`.
