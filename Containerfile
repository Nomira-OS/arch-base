# syntax=docker/dockerfile:1
#
# nomira base image: the smallest Arch Linux that bootc can boot, plus the
# tools to build and switch to nomira images on the machine itself.
#
# The bootc-on-Arch steps follow bootcrew/mono (Apache-2.0), see NOTICE.
#
# Everything is pinned through build args (see versions.env):
#   SNAPSHOT        Arch Linux Archive date, YYYY/MM/DD: fixes all packages
#   BOOTC_REF       bootc git tag, built from source
#   NOMIRA_CLI_REF  nomira-cli git ref; empty leaves the CLI out

ARG ARCH_IMAGE=docker.io/archlinux/archlinux:latest

# --- base: Arch synced to the archive snapshot ------------------------------
FROM ${ARCH_IMAGE} AS base
ARG SNAPSHOT
# The mirrorlist stays in the final image, so recipes built on top install
# from the same package state. -Syyuu also downgrades, so the result does not
# depend on how new ARCH_IMAGE is.
RUN test -n "$SNAPSHOT" && \
    printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$SNAPSHOT" \
        > /etc/pacman.d/mirrorlist && \
    sed -i '/DownloadUser/d' /etc/pacman.conf && \
    pacman -Syyuu --noconfirm

# --- bootc, built from source -----------------------------------------------
FROM base AS bootc-build
ARG BOOTC_REF
RUN pacman -S --noconfirm --needed make git rust go-md2man ostree glibc pkgconf
RUN test -n "$BOOTC_REF" && \
    git clone --depth 1 --branch "$BOOTC_REF" https://github.com/bootc-dev/bootc.git /src && \
    make -C /src bin install-all DESTDIR=/output

# --- nomira CLI (optional) ---------------------------------------------------
FROM base AS cli-build
ARG NOMIRA_CLI_REF
RUN mkdir -p /output/usr/bin && \
    if [ -n "$NOMIRA_CLI_REF" ]; then \
        pacman -S --noconfirm --needed go git && \
        git clone https://github.com/Nomira-OS/nomira-cli /src && \
        git -C /src checkout "$NOMIRA_CLI_REF" && \
        cd /src && CGO_ENABLED=0 go build -trimpath -o /output/usr/bin/nomira . ; \
    fi

# --- the image ----------------------------------------------------------------
FROM base AS system
ARG SNAPSHOT
ARG BOOTC_REF

COPY --from=bootc-build /output /
COPY --from=cli-build /output /
COPY --chmod=0755 files/nomira-initramfs /usr/libexec/nomira-initramfs

# /var is not part of a bootc image. Keep pacman's database, cache and log
# under /usr/lib/sysimage so pacman keeps working in builds on top.
RUN grep "= */var" /etc/pacman.conf | sed "/= *\/var/s/.*=// ; s/ //" | \
        xargs -n1 sh -c 'mkdir -p "/usr/lib/sysimage/$(dirname $(echo $1 | sed "s@/var/@@"))" && mv -v "$1" "/usr/lib/sysimage/$(echo "$1" | sed "s@/var/@@")"' '' && \
    sed -i -e "/= *\/var/ s/^#//" -e "s@= */var@= /usr/lib/sysimage@g" /etc/pacman.conf

# What bootc needs to boot and install (kernel, initramfs, ostree, skopeo,
# bubblewrap, filesystem tools), then the nomira toolchain. Nothing else:
# no network manager, no firmware, no ssh. Recipes add those.
RUN pacman -S --noconfirm --needed \
        base linux dracut ostree skopeo bubblewrap \
        btrfs-progs e2fsprogs dosfstools \
        podman passt buildkit sudo && \
    pacman -Scc --noconfirm

# No interactive first-boot prompts; systemd generates the machine-id.
RUN systemctl mask systemd-firstboot.service && \
    echo "uninitialized" > /etc/machine-id && \
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Initramfs with the bootc dracut module, not tied to the build host.
RUN mkdir -p /usr/lib/dracut/dracut.conf.d && \
    printf 'systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n' \
        > /usr/lib/dracut/dracut.conf.d/30-nomira-bootc-module.conf && \
    printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" bootc "\n' \
        > /usr/lib/dracut/dracut.conf.d/30-nomira-container-build.conf
RUN --mount=type=tmpfs,target=/tmp --mount=type=tmpfs,target=/root \
    /usr/libexec/nomira-initramfs

# bootc filesystem layout: state lives in /var, the rest is the image.
RUN sed -i 's|^HOME=.*|HOME=/var/home|' /etc/default/useradd && \
    rm -rf /boot /home /root /usr/local /srv /opt /mnt /var \
        /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg && \
    mkdir -p /sysroot /boot /usr/lib/ostree /var && \
    ln -sT sysroot/ostree /ostree && \
    ln -sT var/roothome /root && \
    ln -sT var/srv /srv && \
    ln -sT var/opt /opt && \
    ln -sT var/mnt /mnt && \
    ln -sT var/home /home && \
    ln -sT ../var/usrlocal /usr/local && \
    printf 'd /var/%s 0755 root root -\n' opt home srv mnt usrlocal \
        > /usr/lib/tmpfiles.d/bootc-base-dirs.conf && \
    printf 'd /var/roothome 0700 root root -\nd /run/media 0755 root root -\n' \
        >> /usr/lib/tmpfiles.d/bootc-base-dirs.conf && \
    printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' \
        > /usr/lib/ostree/prepare-root.conf

LABEL containers.bootc=1 \
      org.nomira.snapshot="${SNAPSHOT}" \
      org.nomira.bootc="${BOOTC_REF}"

RUN bootc container lint
