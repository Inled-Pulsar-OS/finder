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

if [ "$(id -u)" -eq 0 ]; then
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

IS_DEBIAN_HOST=false
if [ -f /etc/debian_version ] && [ ! -f /etc/arch-release ]; then
    IS_DEBIAN_HOST=true
fi

DEBIAN_CHROOT="$SCRIPT_DIR/../../ISO/build/rootfs-base-stable-debian"
if [ ! -d "$DEBIAN_CHROOT/usr/bin" ]; then
    DEBIAN_CHROOT="$SCRIPT_DIR/../../ISO/build/rootfs-target-stable-debian"
fi

if ! $IS_DEBIAN_HOST && [ -d "$DEBIAN_CHROOT/usr/bin" ]; then
    echo "🐧 Host no-Debian detectado (Arch). Compilando dentro del chroot Debian..."
    CHROOT_BUILD_ROOT="/tmp/nautilus-chroot-build"
    pkexec rm -rf "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT"
    pkexec mkdir -p "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT"
    pkexec cp -rf "$SCRIPT_DIR/." "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT/src/"
    pkexec rm -rf "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT/src/_build"

    pkexec chroot "$DEBIAN_CHROOT" /bin/bash -c "
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
    pkexec cp -rf "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT/staging/"* "$STAGE_DIR/"
    pkexec chown -R "$(id -u):$(id -g)" "$STAGE_DIR"
    pkexec rm -rf "$DEBIAN_CHROOT$CHROOT_BUILD_ROOT"
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
