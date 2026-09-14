#!/usr/bin/env python3
"""Rewrite a Godot project's version pins for a new Godot release.

The mechanical half of an upgrade. 'upgrade' reads the project's '.godot-version'
pin, resolves the requested target release, and picks one route:

  none   the pin is already current; nothing changes
  patch  '.godot-version' only
  minor  patch, plus 'config/features' in 'project.godot'

The pin is written by 'gdenv pin'. Addon submodules track their 'dist' branch
and move with their own releases, so no route touches them. 'godot-infra' is not
involved either; its actions and workflows select toolchain images from the pin
at run time.

What changed is written as JSON to '--output'. Reimporting and committing are
the caller's job. 'resolve' prints the target release without touching the
project; 'prune-settings' drops named 'project.godot' keys.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

GODOT_REPOSITORY = "https://github.com/godotengine/godot"
STABLE_TAG = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?-stable$")


# ---------------------------------------------------------------------------- #
#                                   Versions                                   #
# ---------------------------------------------------------------------------- #


@dataclass(frozen=True, order=True)
class Version:
    major: int
    minor: int
    patch: int

    @property
    def full(self) -> str:
        """The version as Godot tags it: no patch component for '.0'."""
        return (
            self.major_minor if self.patch == 0 else f"{self.major_minor}.{self.patch}"
        )

    @property
    def major_minor(self) -> str:
        return f"{self.major}.{self.minor}"

    @property
    def tag(self) -> str:
        return f"{self.full}-stable"

    @classmethod
    def parse(cls, text: str) -> Version:
        text = text.strip().removeprefix("v")

        text, _, label = text.partition("-")
        if label and label != "stable":
            raise ValueError(f"only stable releases are supported, got '{label}'")

        parts = text.split(".")
        if len(parts) not in (2, 3) or not all(p.isdigit() for p in parts):
            raise ValueError(f"unrecognized Godot version: '{text}'")

        return cls(
            int(parts[0]), int(parts[1]), int(parts[2]) if len(parts) == 3 else 0
        )


def run(*args: str, cwd: Path | None = None, check: bool = True) -> str:
    result = subprocess.run(args, cwd=cwd, check=check, capture_output=True, text=True)
    return result.stdout


def list_stable_releases() -> list[Version]:
    output = run("git", "ls-remote", "--tags", "--refs", GODOT_REPOSITORY)
    releases = []
    for line in output.splitlines():
        _, _, ref = line.partition("\t")
        match = STABLE_TAG.match(ref.removeprefix("refs/tags/"))
        if match:
            major, minor, patch = match.groups()
            releases.append(Version(int(major), int(minor), int(patch or 0)))
    if not releases:
        raise RuntimeError("failed to list Godot releases")
    return sorted(releases)


def resolve_target(requested: str, releases: list[Version]) -> Version:
    """Resolve 'X.Y' (newest patch of X.Y) or 'X.Y.Z' (as given).

    A full tag is taken as given too: 'X.Y-stable' is how Godot names X.Y.0.
    """
    requested = requested.strip().removeprefix("v")
    is_tag = requested.endswith("-stable")
    requested = requested.removesuffix("-stable")

    parts = requested.split(".")
    if len(parts) == 2 and not is_tag:
        major, minor = int(parts[0]), int(parts[1])
        candidates = [r for r in releases if (r.major, r.minor) == (major, minor)]
        if not candidates:
            raise ValueError(f"no stable release of Godot {requested} exists")
        return candidates[-1]

    target = Version.parse(requested)
    if target not in releases:
        raise ValueError(f"no such Godot release: '{target.tag}'")
    return target


# ---------------------------------------------------------------------------- #
#                                    Upgrade                                   #
# ---------------------------------------------------------------------------- #


@dataclass
class Summary:
    """What an upgrade did; 'new' and 'old' are Godot release tags."""

    commit_title: str
    new: str
    old: str
    route: str
    changes: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def write(self, path: Path) -> None:
        path.write_text(json.dumps(asdict(self), indent=2) + "\n")


def replace_in_file(path: Path, pattern: re.Pattern[str], replacement: str) -> int:
    text = path.read_text()
    updated, count = pattern.subn(replacement, text)
    if count:
        path.write_text(updated)
    return count


def upgrade_pin(project: Path, new: Version, summary: Summary) -> None:
    run("gdenv", "pin", "--path", str(project), new.full)
    summary.changes.append(f".godot-version: v{summary.old} -> v{summary.new}")


def upgrade_features(
    project: Path, old: Version, new: Version, summary: Summary
) -> None:
    path = project / "project.godot"
    if not path.is_file():
        summary.warnings.append("project.godot not found; skipped config/features")
        return
    pattern = re.compile(
        r'^(config/features=PackedStringArray\(")' + re.escape(old.major_minor) + '"',
        re.MULTILINE,
    )
    if replace_in_file(path, pattern, rf'\g<1>{new.major_minor}"'):
        summary.changes.append(
            f"project.godot: config/features {old.major_minor} -> {new.major_minor}"
        )
    else:
        summary.warnings.append(
            f"project.godot: config/features does not name {old.major_minor}; "
            "left as is"
        )


def resolve_requested(requested: str) -> Version:
    """The '--godot-version' given, as a full stable release."""
    return resolve_target(requested, list_stable_releases())


def run_resolve(args: argparse.Namespace) -> int:
    new = resolve_requested(args.godot_version)
    print(f"godot: v{new.tag}")
    return 0


def run_upgrade(args: argparse.Namespace) -> int:
    project = Path(args.project).resolve()
    pin_path = project / ".godot-version"
    if not pin_path.is_file():
        print(f"error: {project} has no .godot-version pin", file=sys.stderr)
        return 1

    old = Version.parse(pin_path.read_text())
    new = resolve_requested(args.godot_version)

    if new < old:
        print(f"error: {new.tag} is older than the pinned {old.tag}", file=sys.stderr)
        return 1
    if new == old:
        route = "none"
    elif (new.major, new.minor) == (old.major, old.minor):
        route = "patch"
    else:
        route = "minor"

    if route != "none" and shutil.which("gdenv") is None:
        print("error: 'gdenv' is not installed", file=sys.stderr)
        return 1

    if route == "minor":
        title = f"chore: update to Godot `v{new.major_minor}`"
    else:
        title = f"chore: upgrade Godot to `v{new.tag}`"
    summary = Summary(title, new.tag, old.tag, route)
    print(f"route: {route} (v{old.tag} -> v{new.tag})")

    if route != "none":
        upgrade_pin(project, new, summary)
    if route == "minor":
        upgrade_features(project, old, new, summary)

    for change in summary.changes:
        print(f"changed: {change}")
    for warning in summary.warnings:
        print(f"warning: {warning}")
    summary.write(Path(args.output))
    return 0


# ---------------------------------------------------------------------------- #
#                                Prune settings                                #
# ---------------------------------------------------------------------------- #


def run_prune_settings(args: argparse.Namespace) -> int:
    """Drop excluded keys from project.godot, and any section that empties."""
    path = Path(args.project).resolve() / "project.godot"
    if not path.is_file() or not args.exclude:
        return 0

    excluded = set(args.exclude)
    sections: list[list[str]] = [[]]
    for line in path.read_text().splitlines(keepends=True):
        if line.startswith("["):
            sections.append([])
        sections[-1].append(line)

    removed = []
    kept: list[str] = []
    for section in sections:
        header = section[:1] if section and section[0].startswith("[") else []
        body = []
        for line in section[len(header) :]:
            key = line.partition("=")[0].strip()
            if "=" in line and key in excluded:
                removed.append(key)
            else:
                body.append(line)
        emptied = len(body) < len(section) - len(header)
        if emptied and not any("=" in line for line in body):
            continue
        kept.extend(header + body)

    if not removed:
        return 0
    path.write_text("".join(kept))
    for key in removed:
        print(f"pruned: {key}")

    # Append to an 'upgrade' summary so the pull request lists what was pruned.
    output = Path(args.output)
    if output.is_file():
        summary = Summary(**json.loads(output.read_text()))
        summary.changes.extend(f"project.godot: pruned {key}" for key in removed)
        summary.write(output)
    return 0


# ---------------------------------------------------------------------------- #
#                                     Main                                     #
# ---------------------------------------------------------------------------- #


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    subparsers = parser.add_subparsers(dest="command", required=True)

    resolve = subparsers.add_parser("resolve", help="print the target release")
    resolve.add_argument(
        "--godot-version",
        required=True,
        help="'X.Y.Z' or 'X.Y' (newest patch)",
    )
    resolve.set_defaults(func=run_resolve)

    upgrade = subparsers.add_parser(
        "upgrade", help="rewrite the project's version pins"
    )
    upgrade.add_argument("--project", default=".", help="path to the Godot project")
    upgrade.add_argument(
        "--godot-version",
        required=True,
        help="'X.Y.Z' or 'X.Y' (newest patch)",
    )
    upgrade.add_argument("--output", default="upgrade-summary.json")
    upgrade.set_defaults(func=run_upgrade)

    prune = subparsers.add_parser(
        "prune-settings", help="remove unwanted project settings"
    )
    prune.add_argument("--project", default=".")
    prune.add_argument(
        "--exclude", nargs="*", default=[], help="project setting keys to remove"
    )
    prune.add_argument(
        "--output",
        default="upgrade-summary.json",
        help="an 'upgrade' summary to record the pruned keys in, if it exists",
    )
    prune.set_defaults(func=run_prune_settings)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", "") or ""
        print(f"error: {error}\n{detail}".rstrip(), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
