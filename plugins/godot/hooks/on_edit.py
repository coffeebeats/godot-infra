"""Check the files an agent just edited, as the 'godot' plugin's PostToolUse hook.

It runs gdformat and gdlint over the edited '.gd' files, the project checker with
'--fix' over every file the checker covers, and the '<name>_test.gd' beside each edited
script, and reports what they say back to the agent.

Claude Code sends one file in 'tool_input.file_path'. Codex sends a patch in
'tool_input.command', which may touch many files, so every tool runs once over all of
them rather than once per file.

The report goes out as a JSON decision on stdout and the hook always exits 0. A
non-zero exit is a failed hook in both harnesses, and PowerShell, which Codex runs hooks
through on Windows, rewrites the exit code anyway.

NOTE: The checker boots Godot once for every rule, which keeps a check near 1.1s; a test
beside the script adds a ~4s GUT boot. Do not add a boot for the checks.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import traceback
from pathlib import Path

# PLUGIN is the plugin root, which holds the checker this hook runs.
PLUGIN = Path(__file__).resolve().parent.parent

# CHECKER is the checker's entry script, in the forward-slash form Godot reads on every
# platform.
CHECKER = (PLUGIN / "checker" / "check.gd").as_posix()

# GUT is the test runner, which only a project that vendors it can run.
GUT = "addons/gut/gut_cmdln.gd"

# PRESETS and OVERRIDES are the export files. The export rule reads the declaration and
# the presets from the presets file, so an edit to either is checked there.
PRESETS = "export_presets.cfg"
OVERRIDES = "export_overrides.cfg"

# CHECKED are the file types the checker covers.
CHECKED = (".gd", ".tscn", ".tres")

# PATCH_FILE matches the line naming a file in a patch. 'Delete File' is left out: a
# file that is gone cannot be checked, and a moved file is checked at its destination.
PATCH_FILE = re.compile(r"^\s*\*{3} (?:Add File|Update File|Move to): (.+?)\s*$")

# NOISE matches the boilerplate every headless run prints (the banner, godotsteam's
# settings conversion, teardown notices). Script errors and warnings are never matched.
NOISE = re.compile(
    r"Godot Engine v"
    r"|WARNING: Found older |   at: register_settings"
    r"|WARNING: \d+ ObjectDB instances were leaked|   at: cleanup "
    r"|ERROR: \d+ resources still in use at exit|   at: clear "
    r"|exit status \d+$"
)

# UNAVAILABLE matches uv failing to start a tool, rather than the tool reporting on the
# files. Codex's Windows sandbox denies uv its cache, which is this line.
UNAVAILABLE = re.compile(r"^error: Failed to initialize cache", re.MULTILINE)

# TIMEOUT bounds each call in seconds, since a checker file that fails to compile can
# hang the engine rather than exit.
TIMEOUT = 300


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    """run runs a command in a directory and returns the finished process."""
    return subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=TIMEOUT,
    )


def quiet(result: subprocess.CompletedProcess[str]) -> str:
    """quiet returns a run's output without the boilerplate or the blank lines."""
    lines = f"{result.stdout}{result.stderr}".replace("\r\n", "\n").splitlines()

    return "\n".join(line for line in lines if line.strip() and not NOISE.match(line))


def git_root(cwd: str) -> Path | None:
    """git_root returns the repository a directory sits in, which is where a harness
    that names no project directory was started.
    """
    try:
        result = run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], Path(cwd))
    except OSError:
        return None

    return Path(result.stdout.strip()) if result.returncode == 0 else None


def project_dir(payload: dict) -> Path | None:
    """project_dir returns the Godot project the edit belongs to, or None when the
    session is not in one. The plugin is enabled per repository, but a repository need
    not be a Godot project.
    """
    cwd = str(payload.get("cwd") or Path.cwd())
    named = os.environ.get("CLAUDE_PROJECT_DIR")
    root = Path(named) if named else (git_root(cwd) or Path(cwd))

    return root.resolve() if (root / "project.godot").is_file() else None


def edited(payload: dict) -> list[str]:
    """edited returns the paths the tool call touched, from whichever shape it used."""
    tool_input = payload.get("tool_input") or {}

    if payload.get("tool_name") == "apply_patch":
        patch = str(tool_input.get("command") or "")

        lines = patch.splitlines()

        return [m.group(1) for line in lines if (m := PATCH_FILE.match(line))]

    return [str(tool_input["file_path"])] if tool_input.get("file_path") else []


def covered(paths: list[str], cwd: str, project: Path) -> list[str]:
    """covered returns the project-relative files the checks cover, dropping the rest:
    a path outside the project, a file that no longer exists, and the vendored addons,
    which follow their upstream style.
    """
    kept = []

    for path in paths:
        absolute = Path(path)
        if not absolute.is_absolute():
            absolute = Path(cwd) / absolute

        try:
            relative = absolute.resolve().relative_to(project)
        except (ValueError, OSError):
            continue

        if relative.parts[0] == "addons" or not absolute.is_file():
            continue

        kept.append(relative.as_posix())

    return list(dict.fromkeys(kept))


def targets(files: list[str], project: Path) -> tuple[list[str], list[str], list[str]]:
    """targets sorts the edited files into the ones each tool takes: the scripts to
    format and lint, the paths to check, and the tests to run beside them.
    """
    scripts, checks, tests = [], [], []
    has_gut = (project / GUT).is_file()

    for name in files:
        if name in (PRESETS, OVERRIDES):
            if (project / PRESETS).is_file():
                checks.append(PRESETS)
            continue

        if not name.endswith(CHECKED):
            continue

        checks.append(name)

        if not name.endswith(".gd"):
            continue

        scripts.append(name)

        test = name if name.endswith("_test.gd") else f"{name[: -len('.gd')]}_test.gd"
        if has_gut and (project / test).is_file():
            tests.append(test)

    return scripts, list(dict.fromkeys(checks)), list(dict.fromkeys(tests))


def gdtoolkit(
    project: Path, command: list[str]
) -> subprocess.CompletedProcess[str] | None:
    """gdtoolkit runs a gdtoolkit command over files, from the PATH or else through uv,
    and returns None when neither can start it.
    """
    tool = command[0]

    if shutil.which(tool):
        return run(command, project)

    if shutil.which("uv"):
        return run(["uv", "run", *command], project)

    return None


def check(project: Path, files: list[str]) -> list[str]:
    """check runs every tool over the files it takes and returns what each reported."""
    scripts, checks, tests = targets(files, project)
    report = []

    def reports(label: str, names: list[str], result: subprocess.CompletedProcess[str]):
        """reports keeps a run's output when the run failed, under a neutral label: the
        engine cannot tell a problem from a repair through its exit code.
        """
        if result.returncode != 0:
            report.append(f"{label} for {', '.join(names)}:\n{quiet(result)}")

    for command, label in (
        (["gdformat", "--check"], "gdformat --check failed"),
        (["gdlint"], "gdlint failed"),
    ):
        if not scripts:
            break

        result = gdtoolkit(project, [*command, *scripts])
        if result is None:
            report.append(f"{command[0]} was skipped: neither it nor uv is on the PATH")
        elif UNAVAILABLE.search(f"{result.stdout}{result.stderr}"):
            report.append(f"{command[0]} was skipped: uv could not start")
        else:
            reports(label, scripts, result)

    if checks:
        reports(
            "project check reported",
            checks,
            run(
                ["godot", "--headless", "--path", project.as_posix()]
                + ["-s", CHECKER, "--", "--fix", *checks],
                project,
            ),
        )

    if tests:
        gtest = ",".join(f"res://{name}" for name in tests)
        reports(
            "test failed",
            tests,
            run(
                ["godot", "--headless", "--path", project.as_posix()]
                + ["-s", GUT, f"-gtest={gtest}", "-gexit"],
                project,
            ),
        )

    return report


def main() -> None:
    """main reports on the files a tool call touched, and prints nothing when it has
    nothing to say.
    """
    payload = json.loads(sys.stdin.read())

    project = project_dir(payload)
    if project is None or not shutil.which("godot"):
        return

    cwd = str(payload.get("cwd") or Path.cwd())
    files = covered(edited(payload), cwd, project)
    if not files:
        return

    report = check(project, files)
    if not report:
        return

    # Codex replaces the tool's result with the reason, so a patch is told it applied.
    # Claude Code shows the reason beside the result, which already says so.
    if payload.get("tool_name") == "apply_patch":
        report.insert(0, "The patch was applied. Checks on the files it touched:")

    print(json.dumps({"decision": "block", "reason": "\n".join(report)}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        reason = f"the edit hook failed:\n{traceback.format_exc()}"
        print(json.dumps({"decision": "block", "reason": reason}))
