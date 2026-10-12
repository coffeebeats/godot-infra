"""Check the files an agent just edited, as the 'godot' plugin's PostToolUse hook.

It runs gdformat and gdlint over the edited '.gd' files, the project checker with
'--fix' over every file the checker covers, and GUT over each edited script's tests, and
reports what they say back to the agent. A failed test is read from GUT's JUnit export
rather than its output, which carries every test's logging.

An edited file belongs to the nearest 'project.godot' above it, no higher than the
directory the session works in. A script's test is its '<name>_test.gd', the name
'check-project.yaml' runs GUT with, or the test '.gutconfig.json' names for it through
its prefix and suffix, beside the script or else in the directories the file lists.

The tools run at once. Only the checker writes, repairing scenes, resources and export
files but never scripts, so a test waits for it only when the edit touched one of those.

Claude Code sends one file in 'tool_input.file_path'. Codex sends a patch in
'tool_input.command', which may touch many files, so every tool runs once over all of
them rather than once per file.

The report goes out as a JSON decision on stdout and the hook always exits 0. A
non-zero exit is a failed hook in both harnesses, and PowerShell, which Codex runs hooks
through on Windows, rewrites the exit code anyway.

NOTE: The checker boots Godot once for every rule, which keeps a check near 2s. An edit
takes as long as its slowest tool, which is GUT (~3s) when a script has a test. Do not
add a boot for the checks.
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import traceback
from concurrent.futures import Future, ThreadPoolExecutor
from pathlib import Path
from xml.etree import ElementTree

# PLUGIN is the plugin root, which holds the checker this hook runs.
PLUGIN = Path(__file__).resolve().parent.parent

# CHECKER is the checker's entry script, in the forward-slash form Godot reads on every
# platform.
CHECKER = (PLUGIN / "checker" / "check.gd").as_posix()

# GUT is the test runner, which only a project that vendors it can run.
GUT = "addons/gut/gut_cmdln.gd"

# GUT_CONFIG is the file GUT reads its options from, how it finds tests included.
GUT_CONFIG = ".gutconfig.json"

# SUFFIX ends the name of a script's test in any project, since 'check-project.yaml'
# runs GUT with it whatever '.gutconfig.json' says.
SUFFIX = "_test.gd"

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
# settings conversion, teardown notices, and the exit status gdenv's Windows shim
# prints). Script errors and warnings are never matched.
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

# SCRIPT_ERROR matches the first line of an error a script raised; the line after it
# says where. GUT's export places such an error at line -1.
SCRIPT_ERROR = re.compile(r"^SCRIPT ERROR: ")

# NOTICE matches a warning or error GUT itself prints, such as why it skipped a script.
NOTICE = re.compile(r"^\[GUT (?:WARNING|ERROR)\]:")

# UNCOMPILED matches the checker's report of a script that does not compile.
UNCOMPILED = re.compile(r"^\s*res://\S+?: \[compile\] ", re.MULTILINE)

# LIMIT bounds the whole report in characters. Claude Code moves hook output past 10,000
# characters to a file, leaving the agent a 2,000-character preview.
LIMIT = 8000

# WIDTH bounds each line of a report in characters, so one long line, such as a logged
# dictionary, cannot spend the report alone.
WIDTH = 300

# ERRORS bounds how many distinct script errors a failed test run reports.
ERRORS = 10

# UNAVAILABLE matches uv failing to start a tool, rather than the tool reporting on the
# files: a sandbox denying uv its cache, or a project that does not depend on the tool.
UNAVAILABLE = re.compile(r"^error: Failed to (?:initialize cache|spawn)", re.MULTILINE)

# TIMEOUT bounds each call in seconds, since a test awaiting a signal that never comes,
# or a checker file that fails to compile, can hang the engine rather than exit.
TIMEOUT = 120


def stop(process: subprocess.Popen[str]) -> None:
    """stop kills a process and every process it started.

    NOTE: On Windows, gdenv's 'godot' shim runs the engine as its child, which killing
    the shim alone would leave running.
    """
    with contextlib.suppress(OSError, subprocess.SubprocessError):
        if os.name == "nt":
            command = ["taskkill", "/F", "/T", "/PID", str(process.pid)]
            subprocess.run(command, capture_output=True, timeout=30)
        else:
            os.killpg(process.pid, signal.SIGKILL)

    process.kill()


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    """run runs a command in a directory and returns the finished process. A command
    that cannot start, or that runs past TIMEOUT, returns as a failed run that says so.
    """
    try:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            start_new_session=os.name != "nt",
        )
    except OSError as e:
        return subprocess.CompletedProcess(command, 1, f"{command[0]}: {e}", "")

    with process:
        try:
            stdout, stderr = process.communicate(timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            stop(process)

            # A process the kill missed can hold the pipes open, so the output read
            # after it is bounded too.
            try:
                stdout, stderr = process.communicate(timeout=30)
            except subprocess.TimeoutExpired:
                stdout, stderr = "", ""

            stdout = f"{command[0]} ran past {TIMEOUT}s and was stopped\n{stdout}"

            return subprocess.CompletedProcess(command, 1, stdout, stderr)

    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


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


def clipped(line: str) -> str:
    """clipped returns line cut to WIDTH characters, saying how many it left out."""
    if len(line) <= WIDTH:
        return line

    return f"{line[:WIDTH]}... ({len(line) - WIDTH} more characters)"


def quiet(result: subprocess.CompletedProcess[str]) -> str:
    """quiet returns a run's output with only the lines lines_of keeps, each clipped."""
    lines = lines_of(f"{result.stdout}\n{result.stderr}")

    return "\n".join(clipped(line) for line in lines)


def taken(lines: list[str], budget: int) -> list[str]:
    """taken returns the first of lines that fit in budget characters, newlines
    included.
    """
    kept: list[str] = []
    size = 0

    for line in lines:
        size += len(line) + 1
        if size > budget:
            break

        kept.append(line)

    return kept


def fit(text: str, budget: int) -> str:
    """fit returns text cut to budget characters, keeping its first lines and its last,
    with a line between saying how many it left out. The last lines hold what a report
    ends on, such as where the engine raised its errors.
    """
    if len(text) <= budget:
        return text

    lines = text.splitlines()
    head = taken(lines, budget * 3 // 4)
    rest = budget - sum(len(line) + 1 for line in head) - len("... 0000 more lines ...")
    tail = taken(lines[len(head) :][::-1], rest)[::-1]
    omitted = len(lines) - len(head) - len(tail)

    return "\n".join([*head, f"... {omitted} more lines ...", *tail])


def fitted(parts: list[str]) -> list[str]:
    """fitted returns parts cut to share LIMIT characters, in their order. A part
    shorter than its share leaves the rest to the longer parts.
    """
    kept = list(parts)
    left = LIMIT

    for count, i in enumerate(sorted(range(len(parts)), key=lambda i: len(parts[i]))):
        kept[i] = fit(parts[i], left // (len(parts) - count))
        left -= len(kept[i]) + 1

    return kept


def located(output: str) -> list[str]:
    """located returns each distinct error a script raised, where, and how often, up to
    ERRORS of them.
    """
    errors: dict[str, int] = {}
    lines = lines_of(output)

    for i, line in enumerate(lines):
        if not SCRIPT_ERROR.match(line):
            continue

        error = clipped(line)
        after = lines[i + 1] if i + 1 < len(lines) else ""
        if after.strip().startswith("at:"):
            error = f"{error}\n{clipped(after)}"

        errors[error] = errors.get(error, 0) + 1

    shown = [f"[x{count}] {error}" for error, count in list(errors.items())[:ERRORS]]
    if len(errors) > ERRORS:
        shown.append(f"... {len(errors) - ERRORS} more distinct errors ...")

    return shown


def failures(export: Path) -> tuple[list[str], list[str]] | None:
    """failures returns a line for each test GUT's JUnit export records as failed, and
    the name of each suite it records, or None when there is no export to read.
    """
    try:
        results = ElementTree.parse(export).getroot()
    except (OSError, ElementTree.ParseError):
        return None

    lines = []
    suites = []

    for suite in results.iter("testsuite"):
        name = suite.get("name", "")
        suites.append(name)

        for case in suite.iter("testcase"):
            failure = case.find("failure")
            if failure is None:
                continue

            lines.append(f"- {case.get('name')} in {name}")
            for line in (failure.text or "").strip().splitlines():
                lines.append(f"    {clipped(line.strip())}")

    return lines, suites


def summarize(
    result: subprocess.CompletedProcess[str], export: Path, tests: list[str]
) -> str | None:
    """summarize returns what a GUT run over tests found, or None when every test ran
    and passed: each failed test, each test script GUT ran nothing from and why, then
    each distinct error a script raised. A run that exported nothing reports all it
    printed.

    NOTE: GUT skips a test script that does not load or extend 'GutTest', and still
    exits 0.
    """
    exported = failures(export)
    if exported is None:
        return quiet(result)

    lines, suites = exported

    # GUT names a suite by its script's path, and an inner class's by the path and the
    # class's name.
    skipped = [
        test
        for test in tests
        if not any(name == test or name.startswith(f"{test}.") for name in suites)
    ]
    if skipped:
        lines.extend(f"- GUT ran none of the tests in {test}" for test in skipped)
        out = lines_of(result.stdout)
        lines.extend(clipped(line) for line in out if NOTICE.match(line))

    if not lines:
        return quiet(result) if result.returncode != 0 else None

    errors = located(result.stderr)
    if errors:
        lines.append("script errors, where the engine raised them:")
        lines.extend(errors)

    return "\n".join(lines)


def git_root(cwd: str) -> Path | None:
    """git_root returns the repository a directory sits in, which is where a harness
    that names no project directory was started.
    """
    result = run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], Path(cwd))

    return Path(result.stdout.strip()) if result.returncode == 0 else None


def session_root(payload: dict) -> Path:
    """session_root returns the directory the session works in, above which no project
    is looked for: the one the harness names, else the repository holding the session's
    directory, else that directory.
    """
    cwd = str(payload.get("cwd") or Path.cwd())
    named = os.environ.get("CLAUDE_PROJECT_DIR")
    root = Path(named) if named else (git_root(cwd) or Path(cwd))

    return root.resolve()


def project_of(path: Path, root: Path) -> Path | None:
    """project_of returns the nearest directory above path holding a 'project.godot',
    no higher than root, or None. The plugin is enabled per repository, but a repository
    need not hold a Godot project.
    """
    for parent in path.parents:
        if (parent / "project.godot").is_file():
            return parent

        if parent == root:
            break

    return None


def edited(payload: dict) -> list[str]:
    """edited returns the paths the tool call touched, from whichever shape it used."""
    tool_input = payload.get("tool_input") or {}

    if payload.get("tool_name") == "apply_patch":
        patch = str(tool_input.get("command") or "")

        lines = patch.splitlines()

        return [m.group(1) for line in lines if (m := PATCH_FILE.match(line))]

    return [str(tool_input["file_path"])] if tool_input.get("file_path") else []


def covered(paths: list[str], cwd: str, root: Path) -> dict[Path, list[str]]:
    """covered returns the files the checks cover, by the project holding each and
    relative to it, dropping the rest: a path outside root or any project, a file that
    no longer exists, and the vendored addons, which follow their upstream style.
    """
    projects: dict[Path, list[str]] = {}

    for path in paths:
        absolute = Path(path)
        if not absolute.is_absolute():
            absolute = Path(cwd) / absolute

        try:
            absolute = absolute.resolve()
            absolute.relative_to(root)
        except (ValueError, OSError):
            continue

        project = project_of(absolute, root) if absolute.is_file() else None
        if project is None:
            continue

        relative = absolute.relative_to(project)
        if relative.parts[0] != "addons":
            projects.setdefault(project, []).append(relative.as_posix())

    return {project: list(dict.fromkeys(names)) for project, names in projects.items()}


def found(directory: Path, names: list[str], deep: bool) -> list[Path]:
    """found returns the files in directory, and below it when deep, that carry one of
    names, outside hidden directories such as '.godot'.
    """
    if not deep:
        return [directory / name for name in names if (directory / name).is_file()]

    hits = []

    for parent, children, files in os.walk(directory):
        children[:] = [child for child in children if not child.startswith(".")]
        hits.extend(Path(parent) / name for name in names if name in files)

    return hits


def tests_of(project: Path, scripts: list[str]) -> list[str]:
    """tests_of returns the tests of scripts: each script that is a test itself, and for
    any other its '<name>_test.gd' or the test '.gutconfig.json' names for it through
    its prefix and suffix, beside the script or else in the directories the file lists.
    """
    try:
        config = json.loads((project / GUT_CONFIG).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        config = {}

    if not isinstance(config, dict):
        config = {}

    # The fallbacks are GUT's own defaults.
    prefix = str(config.get("prefix", "test_"))
    suffix = str(config.get("suffix", ".gd"))
    dirs = config.get("dirs") if isinstance(config.get("dirs"), list) else []
    deep = bool(config.get("include_subdirs", False))
    tests = []

    for name in scripts:
        script = Path(name)
        if script.name.endswith(SUFFIX) or (
            script.name.startswith(prefix) and script.name.endswith(suffix)
        ):
            tests.append(name)
            continue

        names = [f"{script.stem}{SUFFIX}", f"{prefix}{script.stem}{suffix}"]
        hits = found(project / script.parent, names, False)

        if not hits:
            for directory in dirs:
                path = project / str(directory).removeprefix("res://")
                hits += found(path, names, deep)

        tests.extend(hit.relative_to(project).as_posix() for hit in hits)

    return list(dict.fromkeys(tests))


def targets(files: list[str], project: Path) -> tuple[list[str], list[str], list[str]]:
    """targets sorts the edited files into the ones each tool takes: the scripts to
    format and lint, the paths to check, and the tests to run. A test is checked too, so
    the checker reports one that does not compile.
    """
    scripts, checks = [], []

    for name in files:
        if name in (PRESETS, OVERRIDES):
            if (project / PRESETS).is_file():
                checks.append(PRESETS)
            continue

        if not name.endswith(CHECKED):
            continue

        checks.append(name)
        if name.endswith(".gd"):
            scripts.append(name)

    tests = tests_of(project, scripts) if (project / GUT).is_file() else []

    return scripts, list(dict.fromkeys([*checks, *tests])), tests


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


def check(project: Path, root: Path, files: list[str], export: Path) -> list[str]:
    """check runs every tool over the files it takes, all at once, and returns what each
    reported, in the same order however they finish. GUT writes its results to export.
    """
    scripts, checks, tests = targets(files, project)
    godot = ["godot", "--headless", "--path", project.as_posix()]
    report = []

    def named(names: list[str]) -> str:
        """named returns names as the agent knows them, relative to root."""
        paths = [(project / name).relative_to(root).as_posix() for name in names]

        return ", ".join(paths)

    def reports(label: str, names: list[str], result: subprocess.CompletedProcess[str]):
        """reports keeps a run's output when the run failed, under a neutral label,
        since the checker exits 1 for a repair as well as a problem.
        """
        if result.returncode != 0:
            report.append(f"{label} for {named(names)}:\n{quiet(result)}")

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
            # '-gdir=' empties the directories '.gutconfig.json' lists, which GUT would
            # otherwise run in full beside the named tests. Its other options apply.
            gtest = ",".join(f"res://{name}" for name in tests)
            command = [*godot, "-s", GUT, "-gdir=", f"-gtest={gtest}", "-gexit"]
            command += ["-gdisable_colors", f"-gjunit_xml_file={export.as_posix()}"]
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
        summary = summarize(tested.result(), export, tests)
        if summary is not None:
            report.append(f"test failed for {named(tests)}:\n{summary}")

    return report


def main() -> None:
    """main reports on the files a tool call touched, and prints nothing when it has
    nothing to say.
    """
    # A payload that will not parse is nothing to check rather than something to report:
    # the launcher's '||' hands the second interpreter a stream the first has drained.
    #
    # NOTE: The payload is read as bytes, since Python decodes a piped stdin by the
    # locale, which is not the UTF-8 a harness writes on Windows.
    try:
        payload = json.loads(sys.stdin.buffer.read())
    except ValueError:
        return

    if not isinstance(payload, dict) or not shutil.which("godot"):
        return

    cwd = str(payload.get("cwd") or Path.cwd())
    root = session_root(payload)
    report = []

    for project, files in covered(edited(payload), cwd, root).items():
        exports = Path(tempfile.mkdtemp())
        try:
            report.extend(check(project, root, files, exports / "results.xml"))
        finally:
            shutil.rmtree(exports, ignore_errors=True)

    if not report:
        return

    report = fitted(report)

    # Codex replaces the tool's result with the reason, so a patch is told it applied.
    # Claude Code shows the reason beside the result, which already says so.
    if payload.get("tool_name") == "apply_patch":
        report.insert(0, "The patch was applied. Checks on the files it touched:")

    print(json.dumps({"decision": "block", "reason": "\n".join(report)}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        reason = f"the edit hook failed:\n{fit(traceback.format_exc(), LIMIT)}"
        print(json.dumps({"decision": "block", "reason": reason}))
