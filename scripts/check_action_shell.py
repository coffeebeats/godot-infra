"""Run 'shellcheck' over the 'run:' blocks of this repository's actions.

'actionlint' checks the 'run:' blocks of workflows but not of composite actions,
so this script extracts every 'bash' and 'sh' step from each 'action.yml' and
checks those instead. Each finding is reported at its line in the action file.

Usage: check_action_shell.py [SHELLCHECK OPTION...]
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

import yaml

# ROOT is the repository root, which actions are found under and reported against.
ROOT = Path(__file__).resolve().parent.parent

# ACTION_GLOBS matches the public and the private actions.
ACTION_GLOBS = ("actions/**/action.y*ml", ".github/actions/**/action.y*ml")

# EXPRESSION matches a one-line GitHub expression, which 'shellcheck' cannot parse.
EXPRESSION = re.compile(r"\$\{\{.*?\}\}")

# FINDING matches one line of 'shellcheck --format=gcc' output.
FINDING = re.compile(r"^(?P<file>[^:]+):(?P<line>\d+):(?P<column>\d+): (?P<rest>.*)$")

# SHELL_OPTIONS holds the options GitHub runs a bare 'bash' or 'sh' shell with.
SHELL_OPTIONS = {"bash": "set -eo pipefail", "sh": "set -e"}


@dataclass
class Script:
    """Script is one 'run:' block and the position of its text in the action."""

    # action is the action file the step belongs to.
    action: Path
    # shell is the dialect 'shellcheck' reads the text as, 'bash' or 'sh'.
    shell: str
    # options is the 'set' command for GitHub's shell options, or empty for a
    # custom shell command.
    options: str
    # text is the step's script with each GitHub expression replaced.
    text: str
    # line is the zero-based line on which the script's text begins.
    line: int
    # column is the zero-based column at which each line of the text begins.
    column: int
    # exact is false when the text's lines differ from the action's, in which case
    # findings are reported at the script's first line.
    exact: bool


def mapping_value(node: yaml.Node | None, key: str) -> yaml.Node | None:
    """mapping_value returns the value under `key`, or None if `node` is not a
    mapping or has no such key.
    """
    if not isinstance(node, yaml.MappingNode):
        return None

    for name, value in node.value:
        if isinstance(name, yaml.ScalarNode) and name.value == key:
            return value

    return None


def extract_scripts(action: Path) -> list[Script]:
    """extract_scripts returns the 'bash' and 'sh' steps of a composite action,
    each GitHub expression replaced by a variable of the same length.
    """
    source = action.read_text(encoding="utf-8")
    lines = source.splitlines()

    steps = mapping_value(mapping_value(yaml.compose(source), "runs"), "steps")
    if not isinstance(steps, yaml.SequenceNode):
        return []

    scripts = []
    for step in steps.value:
        run = mapping_value(step, "run")
        shell = mapping_value(step, "shell")
        if not isinstance(run, yaml.ScalarNode) or not isinstance(
            shell, yaml.ScalarNode
        ):
            continue

        command = shell.value.split()
        if not command or command[0] not in SHELL_OPTIONS:
            continue

        # NOTE: A custom command such as 'bash {0}' runs without GitHub's options.
        options = SHELL_OPTIONS[command[0]] if len(command) == 1 else ""

        mark = run.start_mark
        if run.style in ("|", ">"):
            # PyYAML marks a block scalar at its indicator, a line above the text.
            line = mark.line + 1
            first = next((text for text in lines[line:] if text.strip()), "")
            column = len(first) - len(first.lstrip())
        else:
            line = mark.line
            column = mark.column + (1 if run.style in ("'", '"') else 0)

        # Folding rewrites line breaks, so only a literal block or a scalar on one
        # line keeps the action's lines.
        exact = run.style == "|" or mark.line == run.end_mark.line

        # NOTE: 'shellcheck' treats an uppercase variable as a set environment
        # variable, so an expression reads as the runtime value it stands for.
        text = EXPRESSION.sub(
            lambda match: "${" + "X" * (len(match[0]) - 3) + "}", run.value
        )
        scripts.append(Script(action, command[0], options, text, line, column, exact))

    return scripts


def main(argv: list[str]) -> int:
    """main checks every action's scripts, passing `argv` through to
    'shellcheck', and returns its exit code, or 2 if 'shellcheck' is missing.
    """
    if not shutil.which("shellcheck"):
        print("error: 'shellcheck' was not found on the PATH", file=sys.stderr)
        return 2

    actions = sorted(path for pattern in ACTION_GLOBS for path in ROOT.glob(pattern))
    scripts = [script for action in actions for script in extract_scripts(action)]
    if not scripts:
        return 0

    with tempfile.TemporaryDirectory() as tmpdir:
        files: dict[str, Script] = {}
        for index, script in enumerate(scripts):
            name = f"{index:04d}.sh"
            files[name] = script

            # Padding puts the text on the line it occupies in the action.
            padding = [f"# shellcheck shell={script.shell}"]
            padding += [""] * (script.line - len(padding))

            # NOTE: The options go last so a directive atop the script covers all
            # of it; SC2317 is off because they follow any final 'exit'.
            options = ["# shellcheck disable=SC2317", script.options]
            text = "\n".join([*padding, script.text, *options])
            Path(tmpdir, name).write_text(text, encoding="utf-8", newline="\n")

        # NOTE: 'shellcheck' takes the first '--format', so `argv` cannot override it.
        result = subprocess.run(
            ["shellcheck", "--format=gcc", *argv, *files],
            cwd=tmpdir,
            capture_output=True,
            text=True,
        )

    for output in result.stdout.splitlines():
        finding = FINDING.match(output)
        if not finding or finding["file"] not in files:
            print(output)
            continue

        script = files[finding["file"]]
        path = script.action.relative_to(ROOT).as_posix()
        if script.exact:
            line = int(finding["line"])
            column = int(finding["column"]) + script.column
        else:
            line, column = script.line + 1, script.column + 1

        print(f"{path}:{line}:{column}: {finding['rest']}")

    print(result.stderr, end="", file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
