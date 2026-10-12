"""Check the files an agent just edited, as the 'godot' plugin's PostToolUse hook.

It runs gdformat and gdlint over the edited '.gd' files, the project checker with
'--fix' over every file the checker covers, and the '<name>_test.gd' beside each edited
script, and reports what they say back to the agent. A failed test run reports GUT's
summary and the engine's distinct errors rather than the run's output, which carries
every test's logging.

The tools run at once. Only the checker writes, repairing scenes, resources and export
files but never scripts, so a test waits for it only when the edit touched one of those.

Claude Code sends one file in 'tool_input.file_path'. Codex sends a patch in
'tool_input.command', which may touch many files, so every tool runs once over all of
them rather than once per file.

The report goes out as a JSON decision on stdout and the hook always exits 0. A
non-zero exit is a failed hook in both harnesses, and PowerShell, which Codex runs hooks
through on Windows, rewrites the exit code anyway.

NOTE: The checker boots Godot once for every rule, which keeps a check near 2s, and an
edit takes as long as its slowest tool: GUT's boot (~3s) when a test sits beside the
script. Do not add a boot for the checks.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import traceback
from concurrent.futures import Future, ThreadPoolExecutor
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
# The anchor is exact, since a hunk's context lines begin with a space and would
# otherwise let a patch that quotes this grammar name a file it never touched.
PATCH_FILE = re.compile(r"^\*{3} (?:Add File|Update File|Move to): (.+?)\s*$")

# NOISE matches the boilerplate every headless run prints (the banner, godotsteam's
# settings conversion, teardown notices). Script errors and warnings are never matched.
NOISE = re.compile(
    r"Godot Engine v"
    r"|WARNING: Found older |   at: register_settings"
    r"|WARNING: \d+ ObjectDB instances were leaked|   at: cleanup "
    r"|ERROR: \d+ resources still in use at exit|   at: clear "
    r"|exit status \d+$"
)

# BACKTRACE matches the line the engine prints above an error's GDScript backtrace, and
# FRAME each frame below it. The frames are often a tool's own, and the error's 'at:'
# line already says where it was raised.
BACKTRACE = re.compile(r"^\s*GDScript backtrace \(most recent call first\):$")
FRAME = re.compile(r"^\s*\[\d+\] .+ \(.+:\d+\)$")

# EXPECTED matches the list of tokens gdtoolkit's parser would have accepted below a
# syntax error, which runs to dozens of lines. The error's line and column say where.
EXPECTED = re.compile(r"^(?:Expected one of: ?|\t\* \S+)$")

# ANSI matches the color codes a tool or a project's logger writes, which tell an agent
# nothing.
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

# SUMMARY is the header GUT prints above its run summary, which names each test that did
# not pass and why, then the totals. Everything printed before it is the tests' own
# output, a project's logging included.
SUMMARY = "= Run Summary"

# FAILURE matches the first line of an error the engine raised. The line after it says
# where, and the backtrace below that is left out.
FAILURE = re.compile(r"^(?:SCRIPT ERROR|ERROR): ")

# BROKEN matches the engine's report of a script that does not compile. GUT skips a test
# script that fails to load, says nothing was run, and still exits 0.
BROKEN = re.compile(r"^SCRIPT ERROR: (?:Parse|Compile) Error: ")

# UNCOMPILED matches the checker's report of a script that does not compile.
UNCOMPILED = re.compile(r"^\s*res://\S+?: \[compile\] ", re.MULTILINE)

# PUSHED matches the line placing an error a script raised through 'push_error'. A test
# may raise one on purpose, and GUT's summary already names a test that did not expect
# it, so the engine's errors leave it out.
PUSHED = re.compile(r"^\s*at: push_error ")

# HEAD and TAIL bound each report in lines, keeping its first and last lines. A script
# that stops compiling fails every test that loads it, and a full report of that would
# flood the agent's context. The tail keeps GUT's totals.
HEAD = 60
TAIL = 15

# ERRORS bounds how many distinct engine errors a failed test run reports.
ERRORS = 10

# UNAVAILABLE matches uv failing to start a tool, rather than the tool reporting on the
# files: a sandbox denying uv its cache, or a project that does not depend on the tool.
UNAVAILABLE = re.compile(r"^error: Failed to (?:initialize cache|spawn)", re.MULTILINE)

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


def lines_of(output: str) -> list[str]:
    """lines_of returns output's lines without the color codes, the boilerplate, the
    backtraces, the parser's expected tokens or the blank lines.
    """
    kept = []
    frames = False

    for line in ANSI.sub("", output).replace("\r\n", "\n").splitlines():
        if BACKTRACE.match(line):
            frames = True
            continue

        if frames and FRAME.match(line):
            continue

        frames = False
        if line.strip() and not NOISE.match(line) and not EXPECTED.match(line):
            kept.append(line)

    return kept


def bounded(lines: list[str]) -> list[str]:
    """bounded returns the first HEAD and the last TAIL of lines, with a line saying how
    many it left out between them.
    """
    if len(lines) <= HEAD + TAIL:
        return lines

    omitted = len(lines) - HEAD - TAIL

    return [*lines[:HEAD], f"... {omitted} more lines ...", *lines[-TAIL:]]


def quiet(result: subprocess.CompletedProcess[str]) -> str:
    """quiet returns a run's output, bounded, with only the lines lines_of keeps."""
    return "\n".join(bounded(lines_of(f"{result.stdout}{result.stderr}")))


def failed(result: subprocess.CompletedProcess[str]) -> bool:
    """failed reports whether a run failed, by the code it exited with."""
    return result.returncode != 0


def failed_tests(result: subprocess.CompletedProcess[str]) -> bool:
    """failed_tests reports whether a GUT run failed: by its exit code, or by a script
    that did not compile, which GUT skips without failing the run.
    """
    return failed(result) or any(BROKEN.match(line) for line in lines_of(result.stderr))


def summarize(result: subprocess.CompletedProcess[str]) -> str:
    """summarize returns what a failed GUT run found: GUT's run summary, bounded, then
    each distinct error the engine raised, where, and how often. A run with no summary,
    as when GUT ran nothing, reports all it printed in place of the summary.
    """
    out = lines_of(result.stdout)
    start = next((i for i, line in enumerate(out) if line.strip() == SUMMARY), 0)

    errors: dict[str, int] = {}
    err = lines_of(result.stderr)
    for i, line in enumerate(err):
        if not FAILURE.match(line):
            continue

        after = err[i + 1] if i + 1 < len(err) else ""
        if PUSHED.match(after):
            continue

        error = f"{line}\n{after}" if after.strip().startswith("at:") else line
        errors[error] = errors.get(error, 0) + 1

    report = bounded(out[start:])
    if errors:
        report.append(f"engine errors ({len(errors)} distinct):")
        shown = list(errors.items())[:ERRORS]
        report.extend(f"[x{count}] {error}" for error, count in shown)
        if len(errors) > ERRORS:
            report.append(f"... {len(errors) - ERRORS} more distinct errors ...")

    return "\n".join(report)


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

        # 'relative' has no parts when the path is the project root itself, which the
        # file test rejects first.
        if not absolute.is_file() or relative.parts[0] == "addons":
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
    """gdtoolkit runs a gdtoolkit command over files, through uv or else from the PATH,
    and returns None when neither can start it.

    uv comes first so that the version the project locked is the one that runs, and the
    hook agrees with CI about formatting. Where uv cannot start the tool — a sandbox
    denying it its cache, or a project that does not depend on gdtoolkit — whatever is
    on the PATH runs instead.
    """
    tool = command[0]

    if shutil.which("uv"):
        result = run(["uv", "run", *command], project)
        if not UNAVAILABLE.search(f"{result.stdout}{result.stderr}"):
            return result

    if shutil.which(tool):
        return run(command, project)

    return None


def check(project: Path, files: list[str]) -> list[str]:
    """check runs every tool over the files it takes, all at once, and returns what each
    reported, in the same order however they finish.
    """
    scripts, checks, tests = targets(files, project)
    godot = ["godot", "--headless", "--path", project.as_posix()]
    report = []

    def reports(
        label: str,
        names: list[str],
        result: subprocess.CompletedProcess[str],
        text=quiet,
        judge=failed,
    ):
        """reports keeps what text makes of a run's output when judge finds the run
        failed, under a neutral label: the engine cannot tell a problem from a repair
        through its exit code.
        """
        if judge(result):
            report.append(f"{label} for {', '.join(names)}:\n{text(result)}")

    with ThreadPoolExecutor() as pool:
        linters: list[tuple[str, str, Future]] = []
        if scripts:
            for command, label in (
                (["gdformat", "--check"], "gdformat --check failed"),
                (["gdlint"], "gdlint failed"),
            ):
                started = pool.submit(gdtoolkit, project, [*command, *scripts])
                linters.append((command[0], label, started))

        checked = None
        if checks:
            command = [*godot, "-s", CHECKER, "--", "--fix", *checks]
            checked = pool.submit(run, command, project)

        tested = None
        if tests:
            # '-gdir=' empties the directories a project's '.gutconfig.json' lists,
            # which GUT would otherwise run in full beside the named tests. The file's
            # other options still apply.
            gtest = ",".join(f"res://{name}" for name in tests)
            command = [*godot, "-s", GUT, "-gdir=", f"-gtest={gtest}", "-gexit"]
            repairs = any(not name.endswith(".gd") for name in checks)

            def test(command: list[str]) -> subprocess.CompletedProcess[str]:
                """test runs the tests once the checker has repaired any file they
                might load.
                """
                if checked is not None and repairs:
                    checked.result()

                return run(command, project)

            tested = pool.submit(test, command)

    for tool, label, started in linters:
        result = started.result()
        if result is None:
            report.append(f"{tool} was skipped: neither uv nor the PATH could start it")
        else:
            reports(label, scripts, result)

    if checked is not None:
        reports("project check reported", checks, checked.result())

    # A script that does not compile fails every test that loads it, on the error the
    # checker has just reported.
    uncompiled = checked is not None and UNCOMPILED.search(checked.result().stdout)
    if tested is not None and not uncompiled:
        reports("test failed", tests, tested.result(), summarize, failed_tests)

    return report


def main() -> None:
    """main reports on the files a tool call touched, and prints nothing when it has
    nothing to say.
    """
    # A payload that will not parse is nothing to check rather than something to report:
    # the launcher's '||' hands the second interpreter a stream the first has drained.
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, UnicodeDecodeError):
        return

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
