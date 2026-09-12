#!/usr/bin/env bash
#
# Exports a Godot project preset for the Web. Runs inside the
# 'export-godot-project-preset:godot-vX.Y-web' image, from the workspace root,
# and is driven entirely by environment variables:
#
#   GODOT_EDITOR_PATH  - Godot editor executable, relative to the workspace.
#   PROJECT_PATH       - Godot project directory, relative to the workspace.
#   PRESET_NAME        - Name of the export preset.
#   PRESET_OUTPUT_PATH - Output path, relative to the workspace; must end in '.html'.
#   PROFILE            - Optimization profile ('debug', 'release_debug', 'release').
#   PCK_ONLY           - 'true' to export a PCK file instead of a web build.
#   VERBOSE            - 'true' for verbose editor output.
#
# Read by the editor itself (pass through, may be empty):
#   GODOT_SCRIPT_ENCRYPTION_KEY
#
# The exported HTML file is renamed to 'index.html' so the output directory can
# be served as-is.

set -euo pipefail

: "${GODOT_EDITOR_PATH:?}" "${PROJECT_PATH:?}" "${PRESET_NAME:?}" "${PRESET_OUTPUT_PATH:?}" "${PROFILE:?}"
PCK_ONLY="${PCK_ONLY:-false}"
VERBOSE="${VERBOSE:-false}"

if [[ "$PRESET_OUTPUT_PATH" != *.html ]]; then
  echo "Invalid output path; expected an '.html' file: $PRESET_OUTPUT_PATH" >&2
  exit 1
fi

ARGS=(--path "$PWD/$PROJECT_PATH" --headless)
[[ "$VERBOSE" == "true" ]] && ARGS+=(--verbose)

if [[ "$PCK_ONLY" == "true" ]]; then
  ARGS+=(--export-pack)
elif [[ "$PROFILE" == "release" ]]; then
  ARGS+=(--export-release)
else
  ARGS+=(--export-debug)
fi

"$PWD/$GODOT_EDITOR_PATH" "${ARGS[@]}" "$PRESET_NAME" "$PWD/$PRESET_OUTPUT_PATH"

mv "$PWD/$PRESET_OUTPUT_PATH" "$(dirname "$PWD/$PRESET_OUTPUT_PATH")/index.html"
