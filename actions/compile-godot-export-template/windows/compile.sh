#!/usr/bin/env bash
#
# Compiles a Godot export template (or editor) for Windows. Runs inside the
# 'compile-godot-export-template:godot-vX.Y-windows' image, from the workspace
# root, and is driven entirely by environment variables:
#
#   GODOT_SRC_PATH         - Godot source directory, relative to the workspace.
#   SCONS_CACHE_PATH       - SCons cache directory, relative to the workspace.
#   ARCH                   - Target CPU architecture (e.g. 'x86_64').
#   TARGET                 - SCons target ('editor', 'template_debug', 'template_release').
#   PROFILE                - Optimization profile ('debug', 'release_debug', 'release').
#   USE_DOUBLE_PRECISION   - 'true' to build with double precision.
#   SCRIPT_AES256_ENCRYPTION_KEY (optional) - Script encryption key; read by SCons.

set -euo pipefail

: "${GODOT_SRC_PATH:?}" "${SCONS_CACHE_PATH:?}" "${ARCH:?}" "${TARGET:?}" "${PROFILE:?}"
USE_DOUBLE_PRECISION="${USE_DOUBLE_PRECISION:-false}"

ARGS=(
  -j"$(nproc)"
  -C "$GODOT_SRC_PATH"
  "cache_path=$PWD/$SCONS_CACHE_PATH"
  verbose=yes warnings=extra werror=yes
  "arch=$ARCH"
  "target=$TARGET"
)

[[ "$TARGET" == "editor" ]] && ARGS+=(agility_sdk_path=)
[[ "$USE_DOUBLE_PRECISION" == "true" ]] && ARGS+=(precision=double)

case "$PROFILE" in
  debug) ARGS+=(debug_symbols=yes optimize=debug) ;;
  release_debug) ARGS+=(production=yes debug_symbols=yes optimize=speed_trace) ;;
  release) ARGS+=(production=yes optimize=speed) ;;
  *)
    echo "Unrecognized optimization profile: $PROFILE" >&2
    exit 1
    ;;
esac

[[ "$PROFILE" != "release" ]] && ARGS+=(pix_path=/opt/pix)

scons "${ARGS[@]}"
