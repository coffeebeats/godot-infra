"""Run the 'godot' plugin's project checker, and its edit hook, over each case in
'tests/checker'.

A case is a Godot project whose 'expected.txt' holds the checker's output over it,
followed by the code the checker exited with. A case may also hold these files:

- 'args' lists the arguments to pass, one per line.
- 'delete-after-import' lists paths deleted once the project is imported, which leaves
  the uid cache as a move made since the last import does.
- 'expected-fixed.txt' holds the output of a second check, after '--fix' and a fresh
  import.
- 'payload.json' is a hook payload, as a harness sends it. The case then runs the edit
  hook over the copy instead of the checker, through the command line 'hooks.json'
  carries, so the wiring is covered too. 'expected.txt' holds what the hook reported,
  whichever channel it used.
- 'env' lists 'NAME=value' lines to set for the hook. 'CLAUDE_PROJECT_DIR' belongs here,
  since only some harnesses set it.

'{root}' in 'payload.json' and 'env' becomes the path of the copy the case runs on.

Each case runs on a copy, so neither an import nor a fix writes into the repository.

Usage: test_project_checker.py [--update] [CASE...]

'--update' writes each output into its case rather than comparing it.
"""

from __future__ import annotations

import difflib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

# ROOT is the repository root.
ROOT = Path(__file__).resolve().parent.parent

# CASES is the directory holding one Godot project per case.
CASES = ROOT / "tests" / "checker"

# PLUGIN is the plugin root a harness hands its hooks, in the forward-slash form the
# hook command is substituted with on every platform.
PLUGIN = (ROOT / "plugins" / "godot").as_posix()

# HOOKS holds the hook commands, which the cases run rather than restate.
HOOKS = ROOT / "plugins" / "godot" / "hooks" / "hooks.json"

# CHECKER is the checker's entry script, in the forward-slash form Godot reads on every
# platform.
CHECKER = (ROOT / "plugins" / "godot" / "checker" / "check.gd").as_posix()

# BANNER opens the line naming the engine build, which Godot prints ahead of any output.
BANNER = "Godot Engine v"

# TIMEOUT bounds each Godot call in seconds, since a checker file that fails to compile
# can hang the engine rather than exit.
TIMEOUT = 120


class Failure(Exception):
    """Failure is a Godot call that never finished, which no output could show."""


@dataclass
class Run:
    """Run is one output of the checker and the case file that holds it."""

    # expected is the case file the output is compared with, or written to.
    expected: Path
    # actual is the output, without the engine's banner, and the exit code after it.
    actual: str


def godot(project: Path, *args: str) -> subprocess.CompletedProcess[str]:
    """godot runs the engine headless on a project and returns the finished process."""
    command = ["godot", "--headless", "--path", project.as_posix(), *args]

    try:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=TIMEOUT,
        )
    except subprocess.TimeoutExpired as e:
        raise Failure(f"'{' '.join(args)}' timed out after {TIMEOUT}s") from e


def checker(project: Path, args: list[str]) -> str:
    """checker runs the checker over a project and returns its output, followed by the
    code it exited with.
    """
    result = godot(project, "-s", CHECKER, "--", *args)

    lines = result.stdout.replace("\r\n", "\n").splitlines()
    kept = [line.rstrip() for line in lines if not line.startswith(BANNER)]
    output = "\n".join(kept).strip("\n")

    return f"{output}\nexit {result.returncode}\n".lstrip("\n")


def hook_command() -> str:
    """hook_command returns the edit hook's command line, as a harness runs it: the one
    'hooks.json' holds, with the plugin root substituted.
    """
    config = json.loads(HOOKS.read_text(encoding="utf-8"))
    command = config["hooks"]["PostToolUse"][0]["hooks"][0]["command"]

    return command.replace("${CLAUDE_PLUGIN_ROOT}", PLUGIN)


def reported(result: subprocess.CompletedProcess[str]) -> str:
    """reported returns what a hook run told the agent, from whichever channel it used:
    a JSON decision on stdout, or the stderr that an exit code carries.
    """
    text = result.stderr

    try:
        decision = json.loads(result.stdout)
    except json.JSONDecodeError:
        decision = None

    if isinstance(decision, dict):
        # Both harnesses act on a PostToolUse decision only when it blocks, so anything
        # else is a report the agent never sees. Fail rather than compare it.
        if decision.get("decision") != "block" or "reason" not in decision:
            raise Failure(f"the hook's decision blocks nothing: {result.stdout}")

        text = decision["reason"]

    lines = text.replace("\r\n", "\n").splitlines()

    return "\n".join(line.rstrip() for line in lines).strip("\n")


def hook(project: Path, case: Path) -> str:
    """hook runs the edit hook over a copy of a case, with the case's payload on stdin,
    and returns what it reported, followed by the code it exited with.
    """
    root = project.as_posix()
    payload = (case / "payload.json").read_text(encoding="utf-8")
    payload = payload.replace("{root}", root)

    # Only some harnesses name the project in the environment, so the case decides what
    # is set rather than the shell the tests happen to run in.
    env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}
    env["CLAUDE_PLUGIN_ROOT"] = PLUGIN
    for line in read_lines(case / "env"):
        name, _, value = line.partition("=")
        env[name] = value.replace("{root}", root)

    try:
        result = subprocess.run(
            hook_command(),
            shell=True,
            cwd=project,
            env=env,
            input=payload,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=TIMEOUT,
        )
    except subprocess.TimeoutExpired as e:
        raise Failure(f"the edit hook timed out after {TIMEOUT}s") from e

    return f"{reported(result)}\nexit {result.returncode}\n".lstrip("\n")


def import_project(project: Path) -> None:
    """import_project imports a project, so the uids its files carry resolve."""
    godot(project, "--quit", "--import")


def read_lines(path: Path) -> list[str]:
    """read_lines returns a case file's non-empty lines, or none if it is absent."""
    if not path.exists():
        return []

    return [line for line in path.read_text(encoding="utf-8").splitlines() if line]


def run_case(case: Path) -> list[Run]:
    """run_case runs the checker, or the edit hook, over a copy of a case and returns
    every output.
    """
    args = read_lines(case / "args")

    with tempfile.TemporaryDirectory() as tmpdir:
        project = Path(tmpdir, case.name)
        shutil.copytree(case, project, ignore=shutil.ignore_patterns(".godot"))

        import_project(project)
        for name in read_lines(case / "delete-after-import"):
            (project / name).unlink()

        if (case / "payload.json").exists():
            return [Run(case / "expected.txt", hook(project, case))]

        runs = [Run(case / "expected.txt", checker(project, args))]

        fixed = case / "expected-fixed.txt"
        if fixed.exists():
            checker(project, ["--fix", *args])
            import_project(project)
            runs.append(Run(fixed, checker(project, args)))

    return runs


def compare(run: Run) -> bool:
    """compare reports whether a run matches its case file, printing a diff if not."""
    name = run.expected.relative_to(CASES).as_posix()
    expected = ""
    if run.expected.exists():
        expected = run.expected.read_text(encoding="utf-8")

    if expected == run.actual:
        print(f"ok   {name}")
        return True

    print(f"FAIL {name}")
    sys.stdout.writelines(
        difflib.unified_diff(
            expected.splitlines(keepends=True),
            run.actual.splitlines(keepends=True),
            fromfile=name,
            tofile="actual",
        )
    )

    return False


def main(argv: list[str]) -> int:
    """main runs the cases named in `argv`, or every case, and returns 1 if any failed,
    or 2 if 'godot' is missing.
    """
    if not shutil.which("godot"):
        print("error: 'godot' was not found on the PATH", file=sys.stderr)
        return 2

    update = "--update" in argv
    names = [arg for arg in argv if arg != "--update"]
    cases = [CASES / name for name in names] or sorted(
        path.parent for path in CASES.glob("*/project.godot")
    )

    failed = False

    for case in cases:
        if not (case / "project.godot").exists():
            print(f"error: not a case: {case.name}", file=sys.stderr)
            return 2

        try:
            runs = run_case(case)
        except Failure as e:
            print(f"FAIL {case.name}: {e}")
            failed = True
            continue

        for run in runs:
            if update:
                run.expected.write_text(run.actual, encoding="utf-8", newline="\n")
                print(f"wrote {run.expected.relative_to(CASES).as_posix()}")
            elif not compare(run):
                failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
