#!/usr/bin/env bash
#
# Exports a Godot project preset for macOS. Runs inside the
# 'export-godot-project-preset:godot-vX.Y-macos' image, from the workspace root,
# and is driven entirely by environment variables:
#
#   GODOT_EDITOR_PATH  - Godot editor executable, relative to the workspace.
#   PROJECT_PATH       - Godot project directory, relative to the workspace.
#   PRESET_NAME        - Name of the export preset.
#   PRESET_OUTPUT_PATH - Output path, relative to the workspace.
#   PROFILE            - Optimization profile ('debug', 'release_debug', 'release').
#   PCK_ONLY           - 'true' to export a PCK file instead of an app bundle.
#   VERBOSE            - 'true' for verbose editor output.
#
# Read by the editor itself (pass through, may be empty):
#   GODOT_SCRIPT_ENCRYPTION_KEY, GODOT_MACOS_CODESIGN_CERTIFICATE_FILE,
#   GODOT_MACOS_CODESIGN_CERTIFICATE_PASSWORD, GODOT_MACOS_CODESIGN_PROVISIONING_PROFILE,
#   GODOT_MACOS_NOTARIZATION_API_UUID, GODOT_MACOS_NOTARIZATION_API_KEY,
#   GODOT_MACOS_NOTARIZATION_API_KEY_ID, GODOT_MACOS_NOTARIZATION_APPLE_ID_NAME,
#   GODOT_MACOS_NOTARIZATION_APPLE_ID_PASSWORD

set -euo pipefail

: "${GODOT_EDITOR_PATH:?}" "${PROJECT_PATH:?}" "${PRESET_NAME:?}" "${PRESET_OUTPUT_PATH:?}" "${PROFILE:?}"
PCK_ONLY="${PCK_ONLY:-false}"
VERBOSE="${VERBOSE:-false}"

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
