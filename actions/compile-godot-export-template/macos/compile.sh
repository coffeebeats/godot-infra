#!/usr/bin/env bash
#
# Compiles a Godot export template (or editor) for macOS. Runs inside the
# 'compile-godot-export-template:godot-vX.Y-macos' image, from the workspace
# root, and is driven entirely by environment variables:
#
#   GODOT_SRC_PATH         - Godot source directory, relative to the workspace.
#   SCONS_CACHE_PATH       - SCons cache directory, relative to the workspace.
#   ARCH                   - Target CPU architecture ('x86_64', 'arm64', 'universal').
#   TARGET                 - SCons target ('editor', 'template_debug', 'template_release').
#   PROFILE                - Optimization profile ('debug', 'release_debug', 'release').
#   USE_DOUBLE_PRECISION   - 'true' to build with double precision.
#   SCRIPT_AES256_ENCRYPTION_KEY (optional) - Script encryption key; read by SCons.
#
# A 'universal' build compiles 'x86_64' first and then 'arm64' with
# 'generate_bundle=yes', which makes SCons lipo the two binaries into one bundle.
# Only bundles ('.app' / '.zip') are left in 'bin/'; intermediate binaries are
# removed.

set -euo pipefail

: "${GODOT_SRC_PATH:?}" "${SCONS_CACHE_PATH:?}" "${ARCH:?}" "${TARGET:?}" "${PROFILE:?}"
USE_DOUBLE_PRECISION="${USE_DOUBLE_PRECISION:-false}"

# NOTE: It's unclear why 'arm64' builds fail using this toolchain setup (is Godot
# not cross-compiled regularly?). Disabling the 'c99-designator' warning unblocks
# builds for now. Note that multiple 'ccflags' cannot be passed in via 'SCONSFLAGS',
# so pass it in via a command line argument.
CCFLAGS="-Wno-ordered-compare-function-pointers -Wno-c99-designator"

case "$ARCH" in
  x86_64) ARCHES=(x86_64) ;;
  arm64) ARCHES=(arm64) ;;
  universal) ARCHES=(x86_64 arm64) ;;
  *)
    echo "Unrecognized architecture: $ARCH" >&2
    exit 1
    ;;
esac

compile() {
  local arch="$1" bundle="$2"

  local args=(
    -j"$(nproc)"
    -C "$GODOT_SRC_PATH"
    "cache_path=$PWD/$SCONS_CACHE_PATH"
    verbose=yes warnings=extra werror=yes
    "ccflags=$CCFLAGS"
    "arch=$arch"
    "target=$TARGET"
  )

  [[ "$USE_DOUBLE_PRECISION" == "true" ]] && args+=(precision=double)

  case "$PROFILE" in
    debug) args+=(debug_symbols=yes optimize=debug) ;;
    release_debug) args+=(production=yes debug_symbols=yes optimize=speed_trace) ;;
    release) args+=(production=yes optimize=speed) ;;
    *)
      echo "Unrecognized optimization profile: $PROFILE" >&2
      exit 1
      ;;
  esac

  [[ "$bundle" == "true" ]] && args+=(generate_bundle=yes)
  [[ "$TARGET" == "editor" ]] && args+=(bundle_sign_identity=)

  scons "${args[@]}"

  if [[ "$TARGET" == "editor" && "$bundle" == "true" ]]; then
    rcodesign sign \
      --entitlements-xml-path "$GODOT_SRC_PATH/misc/dist/macos/editor.entitlements" \
      "$GODOT_SRC_PATH/bin/godot_macos_editor.app"
  fi
}

LAST="${ARCHES[${#ARCHES[@]} - 1]}"
for arch in "${ARCHES[@]}"; do
  BUNDLE=false
  [[ "$arch" == "$LAST" ]] && BUNDLE=true
  compile "$arch" "$BUNDLE"
done

find "$GODOT_SRC_PATH/bin" -maxdepth 1 -type f ! -name '*.app' ! -name '*.zip' -exec rm -rf {} \;
