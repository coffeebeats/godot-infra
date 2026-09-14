#!/bin/sh
# plugins/godot/skills/godot-api/dump_api.sh
#
# Dumps engine, project and addon API references into the project's '.godot/agent-api/'
# for the `godot-api` skill, whose SKILL.md describes the layout.

set -eu

# The script ships in a plugin, so it finds the project through CLAUDE_PROJECT_DIR, or
# through git when run by hand.
project_dir="${CLAUDE_PROJECT_DIR:-}"
[ -n "$project_dir" ] || project_dir="$(git rev-parse --show-toplevel)"

if command -v cygpath >/dev/null 2>&1; then
  project_dir="$(cygpath -u "$project_dir")"
fi

if [ ! -f "$project_dir/project.godot" ]; then
  echo "dump_api.sh: no 'project.godot' in $project_dir" >&2
  exit 1
fi

# '.godot/' is gitignored in every Godot project. The path is absolute because '--path'
# changes the working directory.
out_dir="$project_dir/.godot/agent-api"

has_gdscript() {
  [ -n "$(find "$1" -name '*.gd' | head -n 1)" ]
}

# dump_gdscript writes the references for the GDScript under a 'res://' path into
# '$out_dir/<name>'.
dump_gdscript() {
  name="$1"
  source_path="$2"

  rm -rf "${out_dir:?}/$name"
  mkdir -p "$out_dir/$name"

  godot --headless --path "$project_dir" \
    --doctool "$out_dir/$name" --gdscript-docs "$source_path" >/dev/null 2>&1

  echo "  $name: $(find "$out_dir/$name" -name '*.xml' | wc -l) classes"
}

rm -rf "${out_dir:?}/engine"
mkdir -p "$out_dir/engine"
godot --headless --doctool "$out_dir/engine" >/dev/null 2>&1
echo "  engine: $(find "$out_dir/engine" -name '*.xml' | wc -l) classes (signatures only)"

# NOTE: A glob skips hidden directories, which covers '.godot' and '.git'. The script
# templates hold '_BASE_' placeholders that do not parse.
for dir in "$project_dir"/*/; do
  name="$(basename "$dir")"

  case "$name" in
    addons | script_templates) continue ;;
  esac

  [ ! -e "$dir/.gdignore" ] || continue
  has_gdscript "$dir" || continue

  dump_gdscript "$name" "res://$name"
done

for dir in "$project_dir"/addons/*/; do
  [ -d "$dir" ] || continue
  has_gdscript "$dir" || continue

  name="$(basename "$dir")"
  dump_gdscript "addons/$name" "res://addons/$name"
done

echo "dumped to $out_dir"
