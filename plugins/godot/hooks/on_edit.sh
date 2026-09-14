#!/bin/sh
# plugins/godot/hooks/on_edit.sh
#
# Claude Code PostToolUse hook. It runs gdformat and gdlint on an edited `.gd` file, the
# project checker with `--fix` on any file the checker covers, and the script's
# `<name>_test.gd` if one exists. It exits 2 with details on stderr, so a failure or a
# repair the checker made reaches the agent.
#
# NOTE: The checker boots Godot once for every rule, which keeps a check near 1.1s; a
# test beside the script adds a ~4s GUT boot. Do not add a boot for the checks.

set -eu

for tool in jq uv godot; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "on_edit.sh: '$tool' not found in PATH; skipping checks." >&2
    exit 0
  fi
done

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"

[ -n "$file_path" ] || exit 0

project_dir="${CLAUDE_PROJECT_DIR:-}"
checker="${CLAUDE_PLUGIN_ROOT:-}/checker/check.gd"

[ -n "$project_dir" ] || exit 0

# The payload and the harness variables carry native absolute paths, which on Windows
# are not what the shell or the engine expect.
if command -v cygpath >/dev/null 2>&1; then
  file_path="$(cygpath -u "$file_path")"
  project_dir="$(cygpath -u "$project_dir")"
  checker="$(cygpath -m "$checker")"
fi

# The plugin is enabled per repository, but a repository need not be a Godot project.
[ -f "$project_dir/project.godot" ] || exit 0
[ -f "$file_path" ] || exit 0

# The engine resolves paths against the project root, so hand it a relative one.
case "$file_path" in
  "$project_dir"/*) rel_path="${file_path#"$project_dir"/}" ;;
  /*) exit 0 ;;
  *) rel_path="$file_path" ;;
esac

# Vendored addons follow their upstream style, so the hook skips them as the format and
# lint commands do.
case "$rel_path" in
  addons/*) exit 0 ;;
esac

case "$rel_path" in
  *.gd | *.tscn | *.tres) ;;
  *) exit 0 ;;
esac

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

status=0

# NOISE matches the boilerplate every headless run prints (the banner, godotsteam's
# settings conversion, teardown notices). Script errors and warnings are never matched.
NOISE='^Godot Engine v'
NOISE="$NOISE|^WARNING: Found older |^   at: register_settings"
NOISE="$NOISE|^WARNING: [0-9]+ ObjectDB instances were leaked|^   at: cleanup "
NOISE="$NOISE|^ERROR: [0-9]+ resources still in use at exit|^   at: clear "
NOISE="$NOISE|^exit status [0-9]+$"

# report prints a label and the filtered output to stderr, since stdout never reaches
# the agent, and marks the hook as blocking.
report() {
  echo "$1 for $rel_path:" >&2
  grep -Ev "$NOISE" "$out" | sed '/^[[:space:]]*$/d' >&2 || true
  status=2
}

case "$rel_path" in
  *.gd)
    (cd "$project_dir" && uv run gdformat --check "$rel_path") >"$out" 2>&1 ||
      report "gdformat --check failed"
    (cd "$project_dir" && uv run gdlint "$rel_path") >"$out" 2>&1 ||
      report "gdlint failed"
    ;;
esac

# The engine cannot tell a problem from a repair through its exit code, so the label
# stays neutral.
godot --headless --path "$project_dir" -s "$checker" -- --fix "$rel_path" \
  >"$out" 2>&1 || report "project check reported"

# GUT boots Godot again, so the test beside the edited script runs only when it exists;
# pointed at nothing, GUT spends ~3s and exits 0.
case "$rel_path" in
  *_test.gd) test_path="$rel_path" ;;
  *.gd) test_path="${rel_path%.gd}_test.gd" ;;
  *) test_path="" ;;
esac

if [ -n "$test_path" ] &&
  [ -f "$project_dir/$test_path" ] &&
  [ -f "$project_dir/addons/gut/gut_cmdln.gd" ]; then
  godot --headless --path "$project_dir" \
    -s addons/gut/gut_cmdln.gd -gtest="res://$test_path" -gexit >"$out" 2>&1 ||
    report "test failed"
fi

exit "$status"
