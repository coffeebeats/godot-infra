"""List the classes a 'disable_3d' export template does not define.

A template built with 'disable_3d = "yes"' registers no class guarded by the
engine's '_3D_DISABLED', so a script naming one parses in the editor and fails
in the exported game. An editor is not built with the flag and so defines every
one of them, which leaves the engine source as the only place to read the list.

This prints the names the rule cannot match by shape, ready to paste over
'STRIPPED_NAMES'. Regenerate it when the engine pin moves to a new minor.

Usage: list_stripped_classes.py TAG   (e.g. '4.7.2-stable')
"""

from __future__ import annotations

import re
import sys
import tarfile
import urllib.request

SOURCE_URL = (
    "https://github.com/godotengine/godot/releases/download/{tag}/godot-{tag}.tar.xz"
)

# GUARD opens a block compiled out by 'disable_3d'. Only the engine's own 3D
# guard counts, since 'PHYSICS_3D_DISABLED' and 'XR_DISABLED' are options a
# project sets on their own.
GUARD = re.compile(r"^#ifndef\s+_3D_DISABLED\b")

REGISTRATION = re.compile(r"GDREGISTER(?:_ABSTRACT|_INTERNAL|_VIRTUAL)?_CLASS\((\w+)\)")


def registrations(text: str) -> set[str]:
    """registrations returns the classes one file registers inside the 3D guard."""
    found: set[str] = set()
    depth, inside = 0, 0

    for line in text.splitlines():
        line = line.strip()

        if line.startswith("#if"):
            depth += 1
            if GUARD.match(line):
                inside = inside or depth
        elif line.startswith("#endif"):
            if inside == depth:
                inside = 0
            depth -= 1
        elif inside:
            found.update(REGISTRATION.findall(line))

    return found


def stripped(tag: str) -> set[str]:
    """stripped returns every class the release registers inside the 3D guard.

    NOTE: The archive is streamed, so members arrive in order and nothing is
    written to disk.
    """
    names: set[str] = set()

    with (
        urllib.request.urlopen(SOURCE_URL.format(tag=tag)) as response,
        tarfile.open(fileobj=response, mode="r|xz") as archive,
    ):
        for member in archive:
            parts = member.name.split("/")
            if not member.name.endswith(".cpp") or "thirdparty" in parts:
                continue

            source = archive.extractfile(member)
            if source is None:
                continue

            text = source.read().decode("utf-8", errors="replace")
            if "_3D_DISABLED" in text and "GDREGISTER" in text:
                names |= registrations(text)

    return names


def main() -> None:
    """main prints the rule's name list for the release named on the CLI."""
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)

    names = stripped(sys.argv[1])

    # A name ending in '3D' is matched by shape, so only the rest is listed.
    rest = sorted(name for name in names if not name.endswith("3D"))

    summary = f"# {len(names)} classes, {len(rest)} of them not named `*3D`:"
    print(summary, file=sys.stderr)
    for name in rest:
        print(f'\t\t"{name}",')


if __name__ == "__main__":
    main()
