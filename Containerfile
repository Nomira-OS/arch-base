# syntax=docker/dockerfile:1
#
# nomira base image: the smallest Arch Linux that bootc can boot, plus the
# tools to build nomira images on the machine itself, and Flatpak for
# applications.
#
# The bootc-on-Arch steps follow bootcrew/mono (Apache-2.0), see NOTICE.
#
# Everything is pinned through build args; hack/build-args.sh prints them
# from versions.env:
#   ARCH_IMAGE         dated Arch Linux image, tag and digest
#   SNAPSHOT           Arch Linux Archive date of that image, YYYY/MM/DD
#   SOURCE_DATE_EPOCH  midnight UTC of the same day
#   BOOTC_REF          bootc git tag, built from source
#   NOMIRA_CLI_REF     nomira-cli git ref; empty leaves the CLI out
#
# Reproducibility: files/pacman-build sets the install dates to
# SOURCE_DATE_EPOCH and drops the log and the cache, and the image has no
# pacman keyring; dracut builds a reproducible initramfs from
# SOURCE_DATE_EPOCH; CI clamps all timestamps to it when it splits the
# image into layers. Recipes on top get the same from a pacman hook
# (install dates), from the nomira frontend (SOURCE_DATE_EPOCH, timestamps)
# and from their mounts (recipes/mounts.yml: a tmpfs over logs).
ARG ARCH_IMAGE

# --- base: Arch synced to the archive snapshot ------------------------------
FROM ${ARCH_IMAGE} AS base
ARG SNAPSHOT
ARG SOURCE_DATE_EPOCH
# The mirrorlist stays in the final image, so recipes built on top install
# from the same package state. -Syyuu also downgrades, so the result does not
# depend on how new ARCH_IMAGE is. The Arch Linux Archive sometimes stalls
# for longer than pacman's download timeout; the timeout is off, here and
# in every recipe built on top.
#
# No pacman keyring stays in the image: a keyring holds a private signing
# key, which would then be the same on every machine. The Arch image's
# keyring goes (its private key is stripped, so it cannot accept new keys
# anyway). Every pacman step sets up a keyring in a tmpfs instead, see
# files/pacman-build. Recipes need none: recipes/packages.yml installs
# packages that BuildKit checked against the signed sync database.
#
# NoExtract is left open: the Arch image leaves out documentation, man
# pages and translations; this image installs packages whole, as Arch
# does, and a recipe that wants less sets NoExtract itself. All packages
# are installed again, so that the files match pacman.conf.
RUN rm -rf /etc/pacman.d/gnupg
RUN --mount=type=tmpfs,target=/etc/pacman.d/gnupg \
    --mount=type=bind,source=files/pacman-build,target=/tmp/pacman-build \
    test -n "$SNAPSHOT" && \
    printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$SNAPSHOT" \
        > /etc/pacman.d/mirrorlist && \
    sed -i -e '/DownloadUser/d' \
        -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 2/' \
        -e '/^#\?DisableDownloadTimeout/d' \
        -e '/^[[:space:]]*NoExtract[[:space:]]*=/d' \
        -e '0,/^\[options\]/s//[options]\nDisableDownloadTimeout/' /etc/pacman.conf && \
    ! grep -q '^[[:space:]]*NoExtract' /etc/pacman.conf && \
    sh /tmp/pacman-build -Syyuu --noconfirm && \
    sh /tmp/pacman-build -S --noconfirm $(pacman -Qqn)

# --- bootc, built from source -----------------------------------------------
FROM base AS bootc-build
ARG BOOTC_REF
ARG SOURCE_DATE_EPOCH
RUN --mount=type=tmpfs,target=/etc/pacman.d/gnupg \
    --mount=type=bind,source=files/pacman-build,target=/tmp/pacman-build \
    sh /tmp/pacman-build -S --noconfirm --needed make git rust go-md2man ostree glibc pkgconf
# Arch has no libselinux, so bootc is built without its selinux feature (it
# then treats SELinux as disabled). Man pages and the integration test
# binary are left out. bootc's release profile keeps full debug info for
# distributions that split it off. Kept in the image, it made bootc alone
# over 400 MB, went into the initramfs with initramfs-setup, and differed
# between two builds. The binaries are built without it and stripped, and
# in one codegen unit: with several, bootc still differed between builds.
RUN test -n "$BOOTC_REF" && \
    export CARGO_PROFILE_RELEASE_DEBUG=false CARGO_PROFILE_RELEASE_STRIP=true \
        CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 && \
    git clone --depth 1 --branch "$BOOTC_REF" https://github.com/bootc-dev/bootc.git /src && \
    make -C /src install install-ostree-hooks DESTDIR=/output DISABLE_DOCS=1 \
        CARGO_OPTIONS='--no-default-features --features "install-to-disk pre-6.15"'

# --- nomira CLI (optional) ---------------------------------------------------
# The CLI reports a release tag as its version (nomira version), any other
# commit as sha-<commit>, which Go records from the checkout.
FROM base AS cli-build
ARG NOMIRA_CLI_REF
ARG SOURCE_DATE_EPOCH
RUN --mount=type=tmpfs,target=/etc/pacman.d/gnupg \
    --mount=type=bind,source=files/pacman-build,target=/tmp/pacman-build \
    mkdir -p /output/usr/bin && \
    if [ -n "$NOMIRA_CLI_REF" ]; then \
        sh /tmp/pacman-build -S --noconfirm --needed go git && \
        git clone https://github.com/Nomira-OS/nomira-cli /src && \
        git -C /src checkout "$NOMIRA_CLI_REF" && \
        cd /src && \
        v="$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//')" && \
        CGO_ENABLED=0 go build -trimpath ${v:+-ldflags "-X main.version=$v"} -o /output/usr/bin/nomira . ; \
    fi

# --- the image ----------------------------------------------------------------
FROM base AS system
ARG SNAPSHOT
ARG BOOTC_REF
ARG SOURCE_DATE_EPOCH

# Layers are ordered by how often they change: the package set (with each
# snapshot), then configuration, then bootc (with each bootc release), and
# the nomira CLI last, because it changes most often. A change rebuilds only
# its own layer and those after it.

# /var is not part of a bootc image: bootc takes it from an image only at
# the first install. pacman's database describes the image, so it moves to
# /usr/lib/sysimage, where pacman keeps working in builds on top. Cache and
# log stay where Arch has them, in /var/cache and /var/log: machine state.
# Recipes keep them out of their images with settings.mounts, a tmpfs
# there and a BuildKit cache at /var/cache/pacman/pkg, as recipes/mounts.yml
# does.
RUN mkdir -p /usr/lib/sysimage/lib && \
    mv -v /var/lib/pacman /usr/lib/sysimage/lib/pacman && \
    sed -i 's@^#*[[:space:]]*DBPath[[:space:]]*=.*@DBPath = /usr/lib/sysimage/lib/pacman/@' /etc/pacman.conf && \
    grep -n 'DBPath' /etc/pacman.conf && pacman-conf DBPath && \
    pacman-conf DBPath | grep -qx '/usr/lib/sysimage/lib/pacman/\?'

# What bootc needs to boot and install (kernel, initramfs, ostree, skopeo,
# bubblewrap, filesystem tools, tpm2-tss for disk encryption bound to a
# TPM, and tpm2-tools, without which dracut refuses its tpm2-tss module),
# AppArmor, Flatpak for applications, which live in /var and survive
# every image update (Flathub comes preconfigured with Arch's package),
# then the nomira toolchain: buildkit, sudo, and ukify and sbsigntools,
# with which a recipe builds (and signs) a unified kernel image. Nothing
# else: no network manager, no firmware, no ssh, no container runtime.
# Recipes add those.
RUN --mount=type=tmpfs,target=/etc/pacman.d/gnupg \
    --mount=type=bind,source=files/pacman-build,target=/tmp/pacman-build \
    sh /tmp/pacman-build -S --noconfirm --needed \
        base linux dracut ostree skopeo bubblewrap \
        btrfs-progs e2fsprogs dosfstools tpm2-tss tpm2-tools \
        apparmor flatpak \
        buildkit sudo systemd-ukify sbsigntools && \
    test -e /usr/share/flatpak/remotes.d/flathub.flatpakrepo

# The initramfs follows the packages, as on any Arch system: pacman hooks
# rebuild it whenever a package changes what goes into it (kernel,
# firmware, dracut modules, …). Arch's own dracut hooks write a
# host-specific initramfs to /boot, which bootc does not boot. They are
# masked, and one hook with the same triggers rebuilds
# /usr/lib/modules/<kver>/initramfs.img instead (files/pacman-hooks). A
# recipe therefore never decides which packages need a new initramfs.
# The hook runs files/initramfs, /usr/lib/nomira/initramfs in the image,
# which takes an unchanged initramfs from a recipe's cache mount instead
# of running dracut again (see the script). The base image builds its own
# below, after bootc, with the same script and without a cache.
#
# A second hook sets the install dates in pacman's database to
# SOURCE_DATE_EPOCH, so that recipe layers do not depend on the build
# time.
COPY files/pacman-hooks/zz-nomira-installdate.hook /usr/share/libalpm/hooks/
COPY --chmod=0755 files/initramfs /usr/lib/nomira/initramfs
RUN --mount=type=bind,source=files/pacman-hooks/initramfs.action,target=/tmp/initramfs.action \
    hooks="$(grep -lis '^ *Exec *=.*dracut' /usr/share/libalpm/hooks/*.hook)" && \
    [ -n "$hooks" ] || { echo "no dracut hooks found in /usr/share/libalpm/hooks" >&2; exit 1; }; \
    mkdir -p /etc/pacman.d/hooks && \
    for h in $hooks; do \
        ln -sf /dev/null "/etc/pacman.d/hooks/$(basename "$h")" && echo "masked $h" >&2; \
        echo "# from $(basename "$h")"; \
        awk '/^\[/ { t = ($0 == "[Trigger]") } t' "$h"; \
        echo; \
    done > /usr/share/libalpm/hooks/90-nomira-initramfs.hook && \
    cat /tmp/initramfs.action >> /usr/share/libalpm/hooks/90-nomira-initramfs.hook && \
    cat /usr/share/libalpm/hooks/90-nomira-initramfs.hook

# bootc container ukify looks for ukify in PATH. Fail here rather than in a
# recipe if it, sbsign or dracut is missing; if Arch only ships ukify below
# /usr/lib/systemd, link it into PATH.
RUN if ! command -v ukify > /dev/null && [ -x /usr/lib/systemd/ukify ]; then \
        ln -s ../lib/systemd/ukify /usr/bin/ukify; \
    fi && \
    for t in ukify sbsign dracut; do \
        command -v "$t" || { echo "missing in PATH: $t" >&2; exit 1; }; \
    done

# AppArmor: the kernel only activates it when it is named in the lsm= list
# (Arch's default list plus apparmor), and apparmor.service loads the
# profiles from /etc/apparmor.d at boot. Profiles are enforcing unless a
# profile itself says otherwise.
COPY files/10-apparmor.toml /usr/lib/bootc/kargs.d/10-apparmor.toml
RUN systemctl enable apparmor.service

# buildkitd runs as root and only on demand: the socket starts it when
# `nomira` (run as root) connects. Switching the OS needs root anyway, and a
# rootful daemon needs neither rootlesskit nor a second user-mode network
# stack.
RUN systemctl enable buildkit.socket

# First boot: /etc/machine-id "uninitialized" makes systemd treat the first
# start as a first boot. systemd-firstboot then asks on the console for
# whatever the image leaves open: locale, keymap, time zone and the root
# password. The Arch image locks root ("!"), which counts as set; root gets
# "!unprovisioned" instead, which systemd treats as not set yet, so the
# password is asked for. A recipe that sets these in /etc, or a deployment
# that passes them as credentials, gets no prompt for them; the kernel
# argument systemd.firstboot=off turns the prompts off altogether.
RUN echo "uninitialized" > /etc/machine-id && \
    rm -f /etc/localtime && \
    sed -i 's/^root:[^:]*:/root:!unprovisioned:/' /etc/shadow && \
    grep -q '^root:!unprovisioned:' /etc/shadow

# Users: systemd-homed manages them, so a home can be encrypted (LUKS2 by
# default, in /home/<user>.home) and is unlocked with the user's password.
# At the first boot systemd-homed-firstboot asks for the first user; a
# drop-in puts that user into wheel, whose members may use sudo, which
# nomira build and bootc upgrade need. The drop-in keeps the unit's own command line and
# only adds --member-of=wheel. Arch's PAM and NSS configuration already
# include homed.
RUN systemctl enable systemd-homed.service systemd-homed-firstboot.service && \
    unit=/usr/lib/systemd/system/systemd-homed-firstboot.service && \
    exec="$(sed -n 's/^ExecStart=//p' "$unit")" && \
    case "$exec" in *"homectl firstboot"*) ;; *) echo "unexpected ExecStart in $unit: $exec" >&2; exit 1 ;; esac && \
    mkdir -p "$unit.d" && \
    printf '[Service]\nExecStart=\nExecStart=%s --member-of=wheel\n' "$exec" > "$unit.d/10-nomira-wheel.conf" && \
    cat "$unit.d/10-nomira-wheel.conf" && \
    printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel && \
    chmod 0440 /etc/sudoers.d/10-wheel

# The image is meant for bootc's composefs backend: the only one with which
# bootc installs systemd-boot itself. GRUB would need bootupd, which cannot
# generate its metadata on Arch (it asks rpm). This empty file marks the
# image as composefs-native, so `bootc install` picks composefs, and with no
# bootupd in the image, systemd-boot, without any options. The bootc dracut
# module copies the file into the initramfs, so it must exist before dracut
# runs.
RUN mkdir -p /usr/lib/composefs && : > /usr/lib/composefs/setup-root-conf.toml

# Initramfs configuration: with the bootc dracut module, not tied to the
# build host. A unified kernel image carries no root= argument: systemd
# finds the root partition by its GPT type (systemd-gpt-auto-generator)
# and unlocks it if it is encrypted, with a TPM if one is enrolled. Hence
# the cryptsetup and TPM modules, which dracut only adds when asked.
RUN mkdir -p /usr/lib/dracut/dracut.conf.d && \
    printf 'systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n' \
        > /usr/lib/dracut/dracut.conf.d/30-nomira-bootc-module.conf && \
    printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" bootc systemd-cryptsetup tpm2-tss "\n' \
        > /usr/lib/dracut/dracut.conf.d/30-nomira-container-build.conf

# bootc, then the initramfs, which contains bootc's dracut module.
COPY --from=bootc-build /output /
RUN --mount=type=tmpfs,target=/tmp --mount=type=tmpfs,target=/root \
    /usr/lib/nomira/initramfs && \
    img="$(echo /usr/lib/modules/*/initramfs.img)" && \
    for f in systemd-gpt-auto-generator systemd-cryptsetup libtss2-esys; do \
        lsinitrd "$img" | grep -q "$f" || { echo "initramfs lacks $f" >&2; exit 1; }; \
    done

# bootc filesystem layout: state lives in /var, the rest is the image.
RUN sed -i 's|^HOME=.*|HOME=/var/home|' /etc/default/useradd && \
    rm -rf /boot /home /root /usr/local /srv /opt /mnt /var && \
    mkdir -p /sysroot /boot /var && \
    ln -sT var/roothome /root && \
    ln -sT var/srv /srv && \
    ln -sT var/opt /opt && \
    ln -sT var/mnt /mnt && \
    ln -sT var/home /home && \
    ln -sT ../var/usrlocal /usr/local && \
    printf 'd /var/%s 0755 root root -\n' opt home srv mnt usrlocal \
        > /usr/lib/tmpfiles.d/bootc-base-dirs.conf && \
    printf 'd /var/roothome 0700 root root -\nd /run/media 0755 root root -\n' \
        >> /usr/lib/tmpfiles.d/bootc-base-dirs.conf

# The nomira CLI changes most often, so it comes last.
COPY --from=cli-build /output /

LABEL containers.bootc=1 \
      org.nomira.snapshot="${SNAPSHOT}" \
      org.nomira.bootc="${BOOTC_REF}"

RUN bootc container lint
