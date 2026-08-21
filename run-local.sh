#!/bin/bash
# ==============================================================================
# Pulsar OS Finder (nautilus fork) - local dev launcher
# ==============================================================================
# Compiles into ./build-dev and runs the binary straight from the build tree,
# without touching the system install in /usr/local.
#
# Usage:
#   bash run-local.sh [args...]        # build + run
#   NOBUILD=1 bash run-local.sh [...]  # skip rebuild
#
# Notes:
# - GResource (UI/CSS) is embedded in the binary, nothing else is needed.
# - GSETTINGS_SCHEMA_DIR points at the build tree so dev schemas are used.
# - Tag manager ontology resolves via the source-tree fallback path, so
#   starring/color tags work uninstalled.
# - Shares your real profile (~/.local/share/nautilus), like the installed app.
# ==============================================================================
set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SRC_DIR/build-dev"

if [ "${NOBUILD:-0}" != "1" ]; then
    if [ ! -f "$BUILD_DIR/build.ninja" ]; then
        meson setup "$BUILD_DIR" -Dprefix=/usr -Dtests=none -Ddocs=false
    fi
    ninja -C "$BUILD_DIR"
fi

SCHEMA_DIR="$BUILD_DIR/data"
if [ -d "$SCHEMA_DIR" ] && ls "$SCHEMA_DIR"/*.gschema.xml >/dev/null 2>&1; then
    export GSETTINGS_SCHEMA_DIR="$SCHEMA_DIR"
fi

exec "$BUILD_DIR/src/nautilus" "$@"
