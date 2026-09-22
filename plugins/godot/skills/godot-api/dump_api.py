"""Dump engine, project and addon API references for the `godot-api` skill.

They land in the project's '.godot/agent-api/', whose layout SKILL.md describes.

Usage: dump_api.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


def project_dir() -> Path:
    """project_dir returns the project to dump. The script ships in a plugin, so it
    finds the project through CLAUDE_PROJECT_DIR, or through git when run by hand.
    """
    named = os.environ.get("CLAUDE_PROJECT_DIR")
    if named:
        return Path(named)

    root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    )

    return Path(root.stdout.strip())


def doctool(project: Path, out: Path, *args: str) -> None:
    """doctool writes a reference into a directory, replacing what was there."""
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)

    subprocess.run(
        ["godot", "--headless", "--path", project.as_posix()]
        + ["--doctool", out.as_posix(), *args],
        capture_output=True,
        text=True,
    )


def classes(out: Path) -> int:
    """classes counts the references a dump wrote."""
    return len(list(out.rglob("*.xml")))


def has_gdscript(directory: Path) -> bool:
    """has_gdscript reports whether a directory holds GDScript to document."""
    return next(directory.rglob("*.gd"), None) is not None


def sources(project: Path) -> list[tuple[str, Path]]:
    """sources returns the name and directory of everything to document: the project's
    own directories, then the addons.

    NOTE: Hidden directories are skipped, which covers '.godot' and '.git'. The script
    templates hold '_BASE_' placeholders that do not parse.
    """
    found = []

    for directory in sorted(project.iterdir()):
        if not directory.is_dir() or directory.name.startswith("."):
            continue
        if directory.name in ("addons", "script_templates"):
            continue
        if (directory / ".gdignore").exists():
            continue

        found.append((directory.name, directory))

    for directory in sorted((project / "addons").glob("*")):
        if directory.is_dir():
            found.append((f"addons/{directory.name}", directory))

    return found


def main() -> int:
    """main dumps every reference and returns 1 when there is no project to dump."""
    project = project_dir()
    if not (project / "project.godot").is_file():
        print(f"dump_api.py: no 'project.godot' in {project}", file=sys.stderr)
        return 1

    # '.godot/' is gitignored in every Godot project. The path is absolute because
    # '--path' changes the working directory.
    out_dir = project / ".godot" / "agent-api"

    doctool(project, out_dir / "engine")
    print(f"  engine: {classes(out_dir / 'engine')} classes (signatures only)")

    for name, directory in sources(project):
        if not has_gdscript(directory):
            continue

        out = out_dir / name
        doctool(project, out, "--gdscript-docs", f"res://{name}")
        print(f"  {name}: {classes(out)} classes")

    print(f"dumped to {out_dir}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
