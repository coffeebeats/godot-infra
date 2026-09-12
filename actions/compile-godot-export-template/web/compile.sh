#!/usr/bin/env bash
#
# Compiles a Godot export template for the Web. Runs inside the
# 'compile-godot-export-template:godot-vX.Y-web' image, from the workspace root,
# and is driven entirely by environment variables:
#
#   GODOT_SRC_PATH         - Godot source directory, relative to the workspace.
#   SCONS_CACHE_PATH       - SCons cache directory, relative to the workspace.
#   ARCH                   - Target CPU architecture ('wasm32').
#   TARGET                 - SCons target ('template_debug', 'template_release').
#   PROFILE                - Optimization profile ('debug', 'release_debug', 'release').
#   USE_DOUBLE_PRECISION   - 'true' to build with double precision.
#   ENABLE_JAVASCRIPT_EVAL - 'true' to expose the JavaScript singleton.
#   ENABLE_GDEXTENSION     - 'true' to enable GDExtension support (dlink).
#   ENABLE_THREADS         - 'false' to disable WebWorker threads (default 'true').
#   SCRIPT_AES256_ENCRYPTION_KEY (optional) - Script encryption key; read by SCons.
#
# The resulting archive is renamed to 'web[_dlink]_{release,debug}.zip', which is
# the name the Godot editor expects for a custom web export template.

set -euo pipefail

: "${GODOT_SRC_PATH:?}" "${SCONS_CACHE_PATH:?}" "${ARCH:?}" "${TARGET:?}" "${PROFILE:?}"
USE_DOUBLE_PRECISION="${USE_DOUBLE_PRECISION:-false}"
ENABLE_JAVASCRIPT_EVAL="${ENABLE_JAVASCRIPT_EVAL:-false}"
ENABLE_GDEXTENSION="${ENABLE_GDEXTENSION:-false}"
ENABLE_THREADS="${ENABLE_THREADS:-true}"

ARGS=(
  -j"$(nproc)"
  -C "$GODOT_SRC_PATH"
  "cache_path=$PWD/$SCONS_CACHE_PATH"
  verbose=yes warnings=extra werror=yes
  "arch=$ARCH"
  "target=$TARGET"
)

[[ "$USE_DOUBLE_PRECISION" == "true" ]] && ARGS+=(precision=double)
[[ "$ENABLE_JAVASCRIPT_EVAL" != "true" ]] && ARGS+=(javascript_eval=no)
[[ "$ENABLE_GDEXTENSION" == "true" ]] && ARGS+=(dlink_enabled=yes)
if [[ "$ENABLE_THREADS" == "true" ]]; then
  ARGS+=(threads=yes)
else
  ARGS+=(threads=no)
fi

case "$PROFILE" in
  debug) ARGS+=(debug_symbols=yes optimize=debug) ;;
  release_debug) ARGS+=(production=yes debug_symbols=yes optimize=speed_trace) ;;
  release) ARGS+=(production=yes optimize=speed) ;;
  *)
    echo "Unrecognized optimization profile: $PROFILE" >&2
    exit 1
    ;;
esac

scons "${ARGS[@]}"

DLINK=""
[[ "$ENABLE_GDEXTENSION" == "true" ]] && DLINK="_dlink"
SUFFIX="debug"
[[ "$PROFILE" == "release" ]] && SUFFIX="release"

mv "$GODOT_SRC_PATH"/bin/godot.web.*.zip "$GODOT_SRC_PATH/bin/web${DLINK}_${SUFFIX}.zip"

rm -rf .web_zip ./*.js ./*.wasm
