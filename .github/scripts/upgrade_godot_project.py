#!/usr/bin/env python3
"""Rewrite a Godot project's version pins for a new Godot release.

The mechanical half of an upgrade. 'upgrade' reads the project's '.godot-version'
pin, resolves the target release upstream, and picks one route:

  none   the pin is already current; nothing changes
  patch  '.godot-version' only
  minor  patch, plus 'godot-vX.Y' submodule branches and gitlinks,
         'config/features', and a plugin README's version table

The pin is written by 'gdenv pin'. A minor route fails before writing anything
when a submodule branch is not published yet. 'godot-infra' action tags are
left to dependabot.

What changed is written as JSON to '--output'. Reimporting and committing are
the caller's job. 'prune-settings' drops named 'project.godot' keys.
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
    """Resolve '' (newest), 'X.Y' (newest patch of X.Y) or 'X.Y.Z' (as given)."""
    requested = requested.strip().removeprefix("v").removesuffix("-stable")
    if not requested:
        return releases[-1]

    parts = requested.split(".")
    if len(parts) == 2:
        major, minor = int(parts[0]), int(parts[1])
        candidates = [r for r in releases if (r.major, r.minor) == (major, minor)]
        if not candidates:
            raise ValueError(f"no stable release of Godot {requested} exists")
        return candidates[-1]

    target = Version.parse(requested)
    if target not in releases:
        raise ValueError(f"no such Godot release: '{target.tag}'")
    return target


def to_https(url: str) -> str:
    """Rewrite an SSH GitHub URL so it can be queried without an SSH key."""
    match = re.match(r"^(?:ssh://)?git@github\.com[:/](.+?)(?:\.git)?$", url)
    return f"https://github.com/{match.group(1)}" if match else url


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
            f"project.godot: config/features does not name {old.major_minor}; left as is"
        )


def upgrade_submodules(
    project: Path, old: Version, new: Version, summary: Summary
) -> None:
    gitmodules = project / ".gitmodules"
    if not gitmodules.is_file():
        return

    old_branch, new_branch = f"godot-v{old.major_minor}", f"godot-v{new.major_minor}"
    # 'git config' exits 1 when nothing matches; that is the warning below.
    tracking = run(
        "git",
        "config",
        "-f",
        ".gitmodules",
        "--get-regexp",
        "--fixed-value",
        r"^submodule\..*\.branch$",
        old_branch,
        cwd=project,
        check=False,
    ).splitlines()
    if not tracking:
        summary.warnings.append(
            f".gitmodules: no submodule tracks '{old_branch}'; left as is"
        )
        return

    # Resolve every new branch before writing anything, so a missing branch
    # fails the upgrade as a whole and leaves the tree untouched. A clone would
    # let 'git submodule update --remote' do this, but a shallow clone is
    # single-branch and a full one pulls every packaged binary in the fork.
    resolved = []
    missing = []
    for line in tracking:
        key = line.split()[0].removesuffix(".branch")
        path = run("git", "config", "-f", ".gitmodules", f"{key}.path", cwd=project)
        url = run("git", "config", "-f", ".gitmodules", f"{key}.url", cwd=project)
        path, url = path.strip(), url.strip()
        output = run(
            "git", "ls-remote", "--heads", to_https(url), f"refs/heads/{new_branch}"
        )
        if not output:
            missing.append(f"{url} has no '{new_branch}' branch")
            continue
        before = run("git", "rev-parse", f"HEAD:{path}", cwd=project).strip()
        resolved.append((path, before, output.split()[0]))
    if missing:
        raise RuntimeError(
            "submodule branches are not published yet:\n  " + "\n  ".join(missing)
        )

    # 'git submodule set-branch' would do this, but it re-indents the line.
    replace_in_file(
        gitmodules,
        re.compile(
            rf"^([ \t]*branch[ \t]*=[ \t]*){re.escape(old_branch)}[ \t]*$",
            re.MULTILINE,
        ),
        rf"\g<1>{new_branch}",
    )
    for path, before, after in resolved:
        run(
            "git",
            "update-index",
            "--add",
            "--cacheinfo",
            f"160000,{after},{path}",
            cwd=project,
        )
        summary.changes.append(
            f"{path}: {old_branch}@{before[:7]} -> {new_branch}@{after[:7]}"
        )


def bump_release_tag(tag: str) -> str:
    """'v4' -> 'v5'; 'v0.2' -> 'v0.3' (pre-1.0 plugins bump the minor)."""
    parts = tag.removeprefix("v").split(".")
    parts[-1] = str(int(parts[-1]) + 1)
    return "v" + ".".join(parts)


def upgrade_readme(project: Path, old: Version, new: Version, summary: Summary) -> None:
    """Rewrite the plugin README's version table, if it is in the known format:

    - `main` / `godot-v4.6` (`v4`): `v4.6`
    - `godot-v4.5` (`v3`): `v4.5`
    """
    path = project / "README.md"
    if not path.is_file():
        return
    pattern = re.compile(
        r"^- `main` / `godot-v"
        + re.escape(old.major_minor)
        + r"` \(`(v[\d.]+)`\): `v"
        + re.escape(old.major_minor)
        + r"`$",
        re.MULTILINE,
    )
    text = path.read_text()
    match = pattern.search(text)
    if not match:
        if f"godot-v{old.major_minor}" in text:
            summary.warnings.append(
                f"README.md: mentions godot-v{old.major_minor} outside the known"
                " version table format; left as is"
            )
        return
    release = match.group(1)
    rows = (
        f"- `main` / `godot-v{new.major_minor}` (`{bump_release_tag(release)}`): `v{new.major_minor}`\n"
        f"- `godot-v{old.major_minor}` (`{release}`): `v{old.major_minor}`"
    )
    path.write_text(text[: match.start()] + rows + text[match.end() :])
    summary.changes.append(f"README.md: version table gains godot-v{new.major_minor}")


def run_upgrade(args: argparse.Namespace) -> int:
    project = Path(args.project).resolve()
    pin_path = project / ".godot-version"
    if not pin_path.is_file():
        print(f"error: {pin_path} not found", file=sys.stderr)
        return 1

    if shutil.which("gdenv") is None:
        print("error: 'gdenv' is not installed", file=sys.stderr)
        return 1

    old = Version.parse(pin_path.read_text())
    new = resolve_target(args.godot_version, list_stable_releases())

    if new == old:
        route = "none"
    elif new < old:
        print(f"error: {new.tag} is older than the pinned {old.tag}", file=sys.stderr)
        return 1
    elif (new.major, new.minor) == (old.major, old.minor):
        route = "patch"
    else:
        route = "minor"

    if route == "minor":
        title = f"chore!: update to Godot `v{new.major_minor}`"
    else:
        title = f"chore: upgrade Godot to `v{new.tag}`"
    summary = Summary(title, new.tag, old.tag, route)
    print(f"route: {route} (v{old.tag} -> v{new.tag})")

    if route == "minor":
        upgrade_submodules(project, old, new, summary)
    if route != "none":
        upgrade_pin(project, new, summary)
    if route == "minor":
        upgrade_features(project, old, new, summary)
        upgrade_readme(project, old, new, summary)

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

    upgrade = subparsers.add_parser(
        "upgrade", help="rewrite the project's version pins"
    )
    upgrade.add_argument("--project", default=".", help="path to the Godot project")
    upgrade.add_argument(
        "--godot-version",
        default="",
        help="'X.Y.Z', 'X.Y' (newest patch), or empty (newest stable)",
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
