#!/bin/bash
# ==============================================================================
# Pulsar OS - nautilus prepare-assets.sh (Debian build)
# ==============================================================================
# Compiles the Pulsar OS Nautilus (Finder) fork with Meson and installs the
# result into the package staging tree.
#
# Run by package-and-deploy.sh as:
#   bash prepare-assets.sh <STAGE_DIR>
#
# On a Debian host it builds natively. On any other host (e.g. Arch) it builds
# inside the Debian chroot, same strategy as pulsaros-control-center.
# ==============================================================================

set -e

STAGE_DIR="$(realpath -m "$1")"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# ==============================================================================
# 1. Clean staging (keep DEBIAN): meson install will populate everything
# ==============================================================================
find "$STAGE_DIR" -mindepth 1 -maxdepth 1 ! -name DEBIAN -exec rm -rf {} +

# ==============================================================================
# 2. Install build dependencies (only if running as root, e.g. inside a chroot)
# ==============================================================================
# NOTE: must be a single line — this variable is expanded inside a
# 'bash -c "..."' inline script, where newlines would be interpreted as
# command separators ("libglib2.0-dev: command not found").
# libgirepository1.0-dev: ships gobject-introspection-1.0.pc (needed by libnautilus-extension)
# libtracker-sparql-3.0-dev: ships tracker-sparql-3.0.pc (libtinysparql-dev alone
# does not reliably expose it in trixie); cmake: required by some meson deps
BUILD_DEPS="build-essential cmake meson ninja-build gettext libgirepository1.0-dev libgtk-4-dev libadwaita-1-dev libglib2.0-dev libgnome-desktop-4-dev libgnome-autoar-0-dev libportal-dev libportal-gtk4-dev libtinysparql-dev libtracker-sparql-3.0-dev libgexiv2-dev libcloudproviders-dev libgdk-pixbuf-2.0-dev libgraphene-1.0-dev gstreamer1.0-plugins-base libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev desktop-file-utils"

IS_DEBIAN_HOST=false
if [ -f /etc/debian_version ] && [ ! -f /etc/arch-release ]; then
    IS_DEBIAN_HOST=true
fi

if $IS_DEBIAN_HOST && [ "$(id -u)" -eq 0 ]; then
    echo "📦 Instalando dependencias de compilación..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $BUILD_DEPS 2>/dev/null || true
fi

meson_build() {
    local src_dir="$1" build_dir="$2" dest_dir="$3"
    meson setup --prefix=/usr --buildtype=release \
        -D docs=false \
        -D tests=none \
        "$build_dir" "$src_dir"
    ninja -C "$build_dir" -j "$(nproc)"
    DESTDIR="$dest_dir" meson install -C "$build_dir"
}

SUDO_CMD=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
    elif command -v pkexec >/dev/null 2>&1; then
        SUDO_CMD="pkexec"
    fi
fi

if [ -z "$DEBIAN_CHROOT" ] || [ ! -d "$DEBIAN_CHROOT/usr/bin" ]; then
    for cand in \
        "$ROOTFS_TARGET" \
        "$ROOTFS_BASE" \
        "$SCRIPT_DIR/../../ISO/build/rootfs-target-${BRANCH:-stable}-debian" \
        "$SCRIPT_DIR/../../ISO/build/rootfs-base-${BRANCH:-stable}-debian" \
        "$SCRIPT_DIR/../../ISO/build/rootfs-target-${BRANCH:-stable}-debian-minimal" \
        "$SCRIPT_DIR/../../ISO/build/rootfs-base-${BRANCH:-stable}-debian-minimal" \
        "$SCRIPT_DIR/../../ISO/build"/rootfs-target-*-debian* \
        "$SCRIPT_DIR/../../ISO/build"/rootfs-base-*-debian*; do
        if [ -d "$cand/usr/bin" ] && [ -f "$cand/etc/debian_version" ]; then
            DEBIAN_CHROOT="$cand"
            break
        fi
    done
fi

if ! $IS_DEBIAN_HOST && [ -n "$DEBIAN_CHROOT" ] && [ -d "$DEBIAN_CHROOT/usr/bin" ]; then
    echo "🐧 Host no-Debian detectado (Arch). Compilando dentro del chroot Debian ($DEBIAN_CHROOT)..."

    # Ensure virtual filesystems (/proc, /sys, /dev) are mounted inside chroot if not already mounted
    MOUNTED_PROC=false
    MOUNTED_SYS=false
    MOUNTED_DEV=false
    if [ ! -f "$DEBIAN_CHROOT/proc/version" ]; then
        $SUDO_CMD mount -t proc proc "$DEBIAN_CHROOT/proc" 2>/dev/null && MOUNTED_PROC=true
    fi
    if [ ! -d "$DEBIAN_CHROOT/sys/class" ]; then
        $SUDO_CMD mount -t sysfs sys "$DEBIAN_CHROOT/sys" 2>/dev/null && MOUNTED_SYS=true
    fi
    if [ ! -e "$DEBIAN_CHROOT/dev/null" ]; then
        $SUDO_CMD mount --bind /dev "$DEBIAN_CHROOT/dev" 2>/dev/null && MOUNTED_DEV=true
    fi

    # Ensure nameserver is available inside chroot
    if [ ! -f "$DEBIAN_CHROOT/etc/resolv.conf" ] || ! grep -q "nameserver" "$DEBIAN_CHROOT/etc/resolv.conf" 2>/dev/null; then
        printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" | $SUDO_CMD tee "$DEBIAN_CHROOT/etc/resolv.conf" >/dev/null
    fi

    cleanup_chroot() {
        if $MOUNTED_DEV; then $SUDO_CMD umount -l "$DEBIAN_CHROOT/dev" 2>/dev/null || true; fi
        if $MOUNTED_SYS; then $SUDO_CMD umount -l "$DEBIAN_CHROOT/sys" 2>/dev/null || true; fi
        if $MOUNTED_PROC; then $SUDO_CMD umount -l "$DEBIAN_CHROOT/proc" 2>/dev/null || true; fi
    }
    trap cleanup_chroot EXIT INT TERM

    CHROOT_BUILD_ROOT="/tmp/nautilus-chroot-build"
    $SUDO_CMD rm -rf "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT"
    $SUDO_CMD mkdir -p "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT"
    $SUDO_CMD cp -rf "$SCRIPT_DIR/." "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT/src/"
    $SUDO_CMD rm -rf "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT/src/_build"

    $SUDO_CMD chroot "$DEBIAN_CHROOT" /bin/bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update || true
        # No '|| true' here: a silently-swallowed install failure (missing/renamed
        # package) only surfaces later as a confusing meson compiler error.
        apt-get install -y --no-install-recommends $BUILD_DEPS
        cd /tmp/nautilus-chroot-build
        meson setup --prefix=/usr --buildtype=release -D docs=false -D tests=none build src
        ninja -C build -j \$(nproc)
        DESTDIR=/tmp/nautilus-chroot-build/staging meson install -C build
    "

    mkdir -p "$STAGE_DIR"
    $SUDO_CMD cp -rf "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT/staging/"* "$STAGE_DIR/"
    $SUDO_CMD chown -R "$(id -u):$(id -g)" "$STAGE_DIR"
    $SUDO_CMD rm -rf "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT"
    cleanup_chroot
    trap - EXIT INT TERM
else
    echo "🔨 Compilando con Meson local..."
    BUILD_ROOT="/tmp/pulsaros-nautilus-build"
    rm -rf "$BUILD_ROOT"
    mkdir -p "$BUILD_ROOT"
    meson_build "$SCRIPT_DIR" "$BUILD_ROOT/build" "$STAGE_DIR"
    rm -rf "$BUILD_ROOT"
fi

# ==============================================================================
# 3. Strip dev-only files owned by stock -dev packages we don't replace
# ==============================================================================
rm -rf "$STAGE_DIR/usr/include"
find "$STAGE_DIR" -name "*.pc" -delete 2>/dev/null || true
find "$STAGE_DIR" -name "*.vapi" -delete 2>/dev/null || true
find "$STAGE_DIR" -name "Nautilus-4.gir" -delete 2>/dev/null || true
find "$STAGE_DIR" -name "libnautilus-extension.so" -type l -delete 2>/dev/null || true

echo "✅ nautilus preparado con éxito."
