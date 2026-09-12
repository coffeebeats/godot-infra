"""Resolve the minors in 'godot-versions.txt' to concrete Godot release tags.

Each minor resolves to its newest '-stable' tag, or, when the minor has no
stable release yet, to its newest prerelease tag ('-dev', '-beta', '-rc'). The
result is printed as a JSON list so a workflow can use it as a matrix.

Usage: resolve_godot_versions.py [PATH]   (default: godot-versions.txt)
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

GODOT_REPOSITORY = "https://github.com/godotengine/godot"

# Prerelease kinds in ascending order of maturity.
PRERELEASE_RANK = {"dev": 0, "beta": 1, "rc": 2}

TAG = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?-(stable|dev|beta|rc)(\d*)$")


def list_tags() -> list[str]:
    out = subprocess.run(
        ["git", "ls-remote", "--tags", "--refs", GODOT_REPOSITORY],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [
        line.split("refs/tags/", 1)[1]
        for line in out.splitlines()
        if "refs/tags/" in line
    ]


def read_minors(path: Path) -> list[str]:
    minors = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            minors.append(line)
    return minors


def resolve(minor: str, tags: list[str]) -> str:
    major, minor_ = minor.split(".")
    stable: list[tuple[int, str]] = []
    pre: list[tuple[int, int, int, str]] = []

    for tag in tags:
        m = TAG.match(tag)
        if not m or m.group(1) != major or m.group(2) != minor_:
            continue
        patch = int(m.group(3) or 0)
        kind, number = m.group(4), int(m.group(5) or 0)
        if kind == "stable":
            stable.append((patch, tag))
        else:
            pre.append((patch, PRERELEASE_RANK[kind], number, tag))

    if stable:
        return max(stable)[1]
    if pre:
        return max(pre)[3]
    raise SystemExit(f"no Godot release tag found for minor {minor}")


def main() -> None:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "godot-versions.txt")
    tags = list_tags()
    print(json.dumps([resolve(minor, tags) for minor in read_minors(path)]))


if __name__ == "__main__":
    main()
