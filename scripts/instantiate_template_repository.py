#!/usr/bin/env python3
"""Instantiate a Godot-flavored template repository.

NOTE: Bootstrap requires Git and an authenticated `gh` with repo and workflow scopes.
Reconciliation requires only `gh` and repo scope; CLI help lists the available modes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

# DEFAULT_TEMPLATE_OWNER supplies the owner for a bare template name.
DEFAULT_TEMPLATE_OWNER = "coffeebeats"

# DEFAULT_STATUS_CHECK names the family's aggregate job; `--status-check` overrides it.
DEFAULT_STATUS_CHECK = "branch_protection"

# GITHUB_ACTIONS_APP_ID identifies GitHub Actions as the required-check provider.
GITHUB_ACTIONS_APP_ID = 15368

# REPOSITORY_ADMIN_ROLE_ID grants admins a bypass when merging pull requests.
REPOSITORY_ADMIN_ROLE_ID = 5

# INITIAL_VERSION keeps the initial manifest, annotated files and tag in sync.
INITIAL_VERSION = "0.1.0"

DEFAULT_DESCRIPTION = "A new Godot 4+ project."

RELEASE_PLEASE_CONFIG = Path(".release-please/config.json")
RELEASE_PLEASE_MANIFEST = Path(".release-please/manifest.json")

# MIN_GH_VERSION requires support for the merge-setting flags in `gh repo edit`.
MIN_GH_VERSION = (2, 40, 0)

# POPULATE_TIMEOUT_SECONDS bounds the wait for asynchronous template generation.
#
# NOTE: Cloning early can return an empty checkout (cli/cli#2290, #5142, #7055).
POPULATE_TIMEOUT_SECONDS = 120
POPULATE_POLL_SECONDS = 2

GH_VERSION = re.compile(r"gh version (\d+)\.(\d+)\.(\d+)")
GH_SCOPES = re.compile(r"Token scopes:\s*(.+)")

README_HEADING = re.compile(r"^#\s+(?P<open>\*\*)?(?P<name>.+?)(?P<close>\*\*)?\s*$")
LICENSE_HEADING = re.compile(r"^##\s+\*\*License\*\*\s*$")

# RELEASE_MARKER captures the nearest quoted literal before a release-please marker.
RELEASE_MARKER = re.compile(
    r'"(?P<literal>[^"]*)"(?P<tail>[^"]*#\s*'
    r"x-release-please-(?P<kind>version|major|minor|patch)\b.*)$"
)

# VERSION_PREFIX captures the nonnumeric prefix preserved during version replacement.
VERSION_PREFIX = re.compile(r"^(?P<prefix>\D*)\d+\.\d+\.\d+$")

SECRET_REFERENCE = re.compile(r"secrets\.([A-Za-z_][A-Za-z0-9_]*)")
USES_REFERENCE = re.compile(r"uses:\s*['\"]?([^\s@'\"]+)@")
JOB_ID = re.compile(r"^  ([A-Za-z_][A-Za-z0-9_-]*):", re.MULTILINE)
TOP_LEVEL_PERMISSIONS = re.compile(r"^permissions:", re.MULTILINE)


# ---------------------------------------------------------------------------- #
#                                    Output                                    #
# ---------------------------------------------------------------------------- #


def info(message: str) -> None:
    print(f"info: {message}")


def warn(message: str) -> None:
    print(f"warning: {message}")


# ---------------------------------------------------------------------------- #
#                                   Commands                                   #
# ---------------------------------------------------------------------------- #


VERBOSE = False


def run(
    *args: str,
    cwd: Path | None = None,
    check: bool = True,
    stdin: str | None = None,
) -> str:
    """run returns captured stdout and raises on failure unless `check` is false.

    NOTE: Verbose output includes arguments; secret values must never appear
    in them.
    """
    if VERBOSE:
        print(f"run: {' '.join(args)}", file=sys.stderr)

    result = subprocess.run(
        args,
        cwd=cwd,
        check=check,
        capture_output=True,
        text=True,
        input=stdin,
    )
    return result.stdout


def need_cmd(name: str) -> str:
    """need_cmd returns the executable path for `name`, or raises if it is
    unavailable.
    """
    found = shutil.which(name)
    if not found:
        raise RuntimeError(f"required command not found: '{name}'")
    return found


def resolve_gh() -> str:
    """resolve_gh returns the path to `gh` or `gh.exe`, or raises if neither is
    available.
    """
    for name in ("gh", "gh.exe"):
        found = shutil.which(name)
        if found:
            return found
    raise RuntimeError("required command not found: 'gh'")


GH = ""
DRY_RUN = False


def gh(*args: str, check: bool = True, stdin: str | None = None) -> str:
    """gh returns stdout from a read-only GitHub CLI command, including during
    dry runs.
    """
    return run(GH, *args, check=check, stdin=stdin)


def gh_write(*args: str, stdin: str | None = None) -> str:
    """gh_write executes a mutating GitHub CLI command and returns stdout. During
    a dry run, it prints the command and returns an empty string.

    NOTE: Arguments and stdin must contain no secret values.
    """
    if DRY_RUN:
        print(f"dry-run: gh {shlex.join(args)}")
        if stdin:
            print(indent(stdin))
        return ""

    return run(GH, *args, stdin=stdin)


def gh_json(*args: str, default: object = None) -> object:
    """gh_json returns parsed CLI output, or `default` for empty output. Failed
    reads return `default` during dry runs and raise otherwise.
    """
    result = subprocess.run([GH, *args], capture_output=True, text=True)
    if result.returncode != 0:
        if DRY_RUN:
            return default
        raise RuntimeError(f"'gh {shlex.join(args)}' failed: {result.stderr.strip()}")

    return json.loads(result.stdout) if result.stdout.strip() else default


def indent(text: str, prefix: str = "  ") -> str:
    return "\n".join(prefix + line for line in text.splitlines())


def gh_api(
    method: str,
    path: str,
    payload: dict | None = None,
    check: bool = True,
) -> str:
    """gh_api returns the response to a GitHub API request with an optional JSON
    payload. Dry runs print mutating requests without sending them.

    NOTE: `check` controls failure handling only for GET requests.
    """
    args = [
        "api",
        "--method",
        method,
        "-H",
        "Accept: application/vnd.github+json",
        "-H",
        "X-GitHub-Api-Version: 2022-11-28",
    ]
    if payload is not None:
        args += ["--input", "-"]
    args.append(path)

    body = json.dumps(payload, indent=2) if payload is not None else None
    if method == "GET":
        return gh(*args, check=check, stdin=body)

    return gh_write(*args, stdin=body)


# ---------------------------------------------------------------------------- #
#                                   Preflight                                  #
# ---------------------------------------------------------------------------- #


def check_gh_version() -> None:
    """check_gh_version raises if the GitHub CLI version is unrecognized or
    unsupported.
    """
    match = GH_VERSION.search(gh("--version"))
    if not match:
        raise RuntimeError("failed to determine the version of 'gh'")

    version = tuple(int(part) for part in match.groups())
    if version < MIN_GH_VERSION:
        want = ".".join(str(part) for part in MIN_GH_VERSION)
        have = ".".join(str(part) for part in version)
        raise RuntimeError(f"'gh' v{want} or newer is required; found v{have}")


def check_gh_scopes(required: tuple[str, ...]) -> None:
    """check_gh_scopes raises if authentication fails or reported scopes omit
    `required`. Unreadable scope information produces a warning.
    """
    status = subprocess.run(
        [GH, "auth", "status"],
        capture_output=True,
        text=True,
    )
    if status.returncode != 0:
        raise RuntimeError(
            "failed to identify the current GitHub user; authenticate via 'gh'"
        )

    match = GH_SCOPES.search(status.stdout + status.stderr)
    if not match:
        warn("could not read token scopes from 'gh auth status'; continuing")
        return

    scopes = {scope.strip().strip("'\"") for scope in match.group(1).split(",")}
    missing = [scope for scope in required if scope not in scopes]
    if missing:
        raise RuntimeError(
            f"the authenticated token is missing required scopes: {', '.join(missing)}"
        )


def preflight(bootstrapping: bool) -> None:
    """preflight checks GitHub CLI availability and authorization. Bootstrap mode
    also requires Git and permission to push workflows.
    """
    check_gh_version()

    check_gh_scopes(("repo", "workflow") if bootstrapping else ("repo",))

    if bootstrapping:
        need_cmd("git")


def qualify(repository: str, default_owner: str) -> str:
    """qualify returns `repository` as owner/name, using `default_owner` for a
    bare name. An empty name or explicit empty owner raises ValueError.
    """
    owner, separator, name = repository.rpartition("/")
    if separator and not owner:
        raise ValueError(f"invalid repository: '{repository}'")
    if not name:
        raise ValueError(f"invalid repository: '{repository}'")

    return f"{owner or default_owner}/{name}"


def current_user() -> str:
    """current_user returns the authenticated GitHub login, or raises if it is empty."""
    user = gh("api", "user", "-q", ".login").strip()
    if not user:
        raise RuntimeError("failed to identify current GitHub user")

    return user


def git_identity() -> tuple[str, str]:
    """git_identity returns the configured Git name and email, or raises if
    either is missing.
    """
    name = run("git", "config", "user.name").strip()
    if not name:
        raise RuntimeError("failed to identify the current Git user's name")

    email = run("git", "config", "user.email").strip()
    if not email:
        raise RuntimeError("failed to identify the current Git user's email address")

    return name, email


# ---------------------------------------------------------------------------- #
#                                   Bootstrap                                  #
# ---------------------------------------------------------------------------- #


def create_repository(args: argparse.Namespace, source: str, target: str) -> None:
    """create_repository creates `target` with the requested visibility and description.

    The template API is used for `main`; other refs are copied from a source clone so a
    commit or branch pin is honored. Dry runs print the creation command.
    """
    info(
        "Creating repository from template."
        if args.branch == "main"
        else "Creating repository."
    )

    create = ["repo", "create", target]
    if args.branch == "main":
        create += ["--template", source]
    create += [
        "--description",
        args.description,
        "--public" if args.public else "--private",
    ]

    gh_write(*create)


def wait_for_population(target: str) -> None:
    """wait_for_population waits for `target` to expose a commit, or raises after
    the population timeout.
    """
    info("Waiting for GitHub to populate the repository.")

    deadline = time.monotonic() + POPULATE_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        result = subprocess.run(
            [GH, "api", f"repos/{target}/commits?per_page=1"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            try:
                commits = json.loads(result.stdout)
            except json.JSONDecodeError:
                commits = []
            if commits:
                return

        time.sleep(POPULATE_POLL_SECONDS)

    raise RuntimeError(
        f"repository '{target}' was not populated within "
        f"{POPULATE_TIMEOUT_SECONDS}s; retry once generation finishes"
    )


def resolve_ref(repo: Path, ref: str) -> str:
    """resolve_ref returns a commit hash from `repo`, preferring the remote-
    tracking branch over the bare `ref`. It raises if neither resolves.

    NOTE: The template API copies no history, so non-default refs are resolved
    in a source clone before its tree is pushed to the new repository.
    """
    for candidate in (f"origin/{ref}", ref):
        result = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", f"{candidate}^{{commit}}"],
            cwd=repo,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return result.stdout.strip()

    raise RuntimeError(
        f"failed to resolve '{ref}' in the new repository; template generation "
        "copies no tags, so pin by branch or commit"
    )


def clone_repository(
    args: argparse.Namespace,
    source: str,
    target: str,
    repo: Path,
    identity: tuple[str, str],
) -> None:
    """clone_repository prepares `repo` from the generated target or a pinned source
    tree.

    The checkout is configured with `identity` and points its origin at `target`.
    """
    info(f"Cloning new repository to directory: {repo}")
    if args.branch == "main":
        gh("repo", "clone", target, str(repo))
    else:
        gh("repo", "clone", source, str(repo))
        commit = resolve_ref(repo, args.branch)
        run("git", "checkout", "--detach", commit, cwd=repo)
        run("git", "switch", "--orphan", "main", cwd=repo)
        run("git", "reset", cwd=repo)
        run(
            "git",
            "remote",
            "set-url",
            "origin",
            f"https://github.com/{target}.git",
            cwd=repo,
        )
        run("git", "add", "-A", cwd=repo)
        run("git", "commit", "-m", "chore: initialize repository", cwd=repo)

    name, email = identity
    run("git", "config", "--local", "user.name", name, cwd=repo)
    run("git", "config", "--local", "user.email", email, cwd=repo)

    if args.branch == "main":
        info("Using the generated template commit.")


def delete_other_branches(repo: Path) -> None:
    """delete_other_branches deletes every remote branch except `main` from the
    repository at `repo`.
    """
    for line in run("git", "ls-remote", "--heads", "origin", cwd=repo).splitlines():
        _, _, ref = line.partition("\t")
        branch = ref.strip().removeprefix("refs/heads/")
        if not branch or branch == "main":
            continue

        info(f"Deleting branch on remote repository: {branch}")
        run("git", "push", "origin", "--delete", branch, cwd=repo)


# ---------------------------------------------------------------------------- #
#                                   Contents                                   #
# ---------------------------------------------------------------------------- #


def read_text(path: Path) -> str:
    """read_text returns UTF-8 text without translating line endings."""
    with path.open("r", encoding="utf-8", newline="") as file:
        return file.read()


def write_text(path: Path, text: str) -> None:
    """write_text overwrites `path` with UTF-8 text without translating line endings."""
    with path.open("w", encoding="utf-8", newline="") as file:
        file.write(text)


def rewrite_readme(repo: Path, name: str, description: str, has_license: bool) -> None:
    """rewrite_readme replaces the title and description and optionally removes
    the license section. Missing expected headings raise RuntimeError.
    """
    readme = repo / "README.md"
    if not readme.is_file():
        raise RuntimeError("template has no 'README.md'")

    lines = read_text(readme).splitlines(keepends=True)
    if not lines or not lines[0].startswith("# "):
        raise RuntimeError("'README.md' does not open with a level-one heading")

    heading = README_HEADING.match(lines[0].rstrip("\r\n"))
    decoration = (heading.group("open") or "") if heading else ""
    ending = lines[0][len(lines[0].rstrip("\r\n")) :] or "\n"

    title = f"# {decoration}{name}{decoration}{ending}"
    body = [title, ending, f"{description}{ending}", *lines[3:]]

    if not has_license:
        index = next(
            (i for i, line in enumerate(body) if LICENSE_HEADING.match(line.rstrip())),
            None,
        )
        if index is None:
            raise RuntimeError("failed to remove the license section of 'README.md'")

        body = body[: max(index - 1, 0)]

    write_text(readme, "".join(body))


def update_contents(
    args: argparse.Namespace, repo: Path, source: str, target: str, name: str
) -> None:
    """update_contents rewrites template metadata and amends the generated
    commit. Private repositories lose their license and README license
    section.
    """
    info("Updating repository's contents.")

    # NOTE: Git rejects a staging pathspec that matches no files.
    staged = ["README.md"]

    license_path = repo / "LICENSE"
    had_license = license_path.is_file()
    if had_license:
        staged.append("LICENSE")
        if not args.public:
            info("Removing license for private repository.")
            license_path.unlink()
    else:
        warn("template has no 'LICENSE'")

    changelog = repo / "CHANGELOG.md"
    if changelog.is_file():
        staged.append("CHANGELOG.md")
        write_text(changelog, "# Changelog\n")
    else:
        warn("template has no 'CHANGELOG.md' to reset")

    rewrite_readme(repo, name, args.description, had_license and args.public)

    readme = repo / "README.md"
    write_text(readme, read_text(readme).replace(f"/{source}", f"/{target}"))

    run("git", "add", "-A", "--", *staged, cwd=repo)
    run("git", "commit", "--amend", "-m", "chore: initialize repository", cwd=repo)

    if args.no_release:
        removed = []
        for relative in (
            ".github/workflows/release-please.yaml",
            ".release-please/config.json",
            ".release-please/manifest.json",
        ):
            path = repo / relative
            if path.is_file():
                path.unlink()
                removed.append(relative)
        if removed:
            run("git", "add", "-A", "--", *removed, cwd=repo)
            run("git", "commit", "--amend", "--no-edit", cwd=repo)


# ---------------------------------------------------------------------------- #
#                                   Releases                                   #
# ---------------------------------------------------------------------------- #


def release_extra_files(repo: Path) -> list[str]:
    """release_extra_files returns the root package's release-please extra files,
    or an empty list when its configuration is absent.
    """
    config = repo / RELEASE_PLEASE_CONFIG
    if not config.is_file():
        return []

    packages = json.loads(config.read_text(encoding="utf-8")).get("packages", {})
    return packages.get(".", {}).get("extra-files", [])


def rewrite_release_markers(path: Path, version: str) -> int:
    """rewrite_release_markers writes annotated version literals and returns
    their count. `version` must contain three dot-separated components.
    """
    major, minor, patch = version.split(".")
    components = {"version": version, "major": major, "minor": minor, "patch": patch}

    rewritten = 0
    lines = []
    for line in read_text(path).splitlines(keepends=True):
        match = RELEASE_MARKER.search(line.rstrip("\r\n"))
        if not match:
            lines.append(line)
            continue

        replacement = components[match.group("kind")]
        if match.group("kind") == "version":
            # NOTE: Release-please supplies bare versions; existing prefixes must
            # survive.
            prefix = VERSION_PREFIX.match(match.group("literal"))
            replacement = (prefix.group("prefix") if prefix else "") + replacement

        head = line[: match.start()]
        ending = line[len(line.rstrip("\r\n")) :]
        lines.append(f'{head}"{replacement}"{match.group("tail")}{ending}')
        rewritten += 1

    if rewritten:
        write_text(path, "".join(lines))

    return rewritten


def initialize_releases(repo: Path) -> None:
    """initialize_releases seeds release metadata, amends and force-pushes
    `main`, then publishes the initial tag. A missing manifest skips release
    setup.
    """
    info("Initializing release for the repository.")

    manifest = repo / RELEASE_PLEASE_MANIFEST
    if not manifest.is_file():
        warn(f"template has no '{RELEASE_PLEASE_MANIFEST}'; skipping release setup")
        return

    write_text(manifest, json.dumps({".": INITIAL_VERSION}, indent=2) + "\n")
    staged = [RELEASE_PLEASE_MANIFEST.as_posix()]

    for entry in release_extra_files(repo):
        path = repo / entry
        if not path.is_file():
            warn(f"'extra-files' names a missing file: {entry}")
            continue

        if rewrite_release_markers(path, INITIAL_VERSION):
            staged.append(entry)
        else:
            warn(f"'extra-files' entry carries no release markers: {entry}")

    run("git", "add", "--", *staged, cwd=repo)
    run("git", "commit", "--amend", "--no-edit", cwd=repo)

    info("Updating remote branch 'main'")
    run("git", "push", "-f", "origin", "main", cwd=repo)

    tag = f"v{INITIAL_VERSION}"
    info(f"Tagging initial commit: {tag}")
    run("git", "tag", tag, cwd=repo)
    run("git", "push", "origin", "tag", tag, cwd=repo)


# ---------------------------------------------------------------------------- #
#                                   Rule sets                                  #
# ---------------------------------------------------------------------------- #


def put_rule_set(target: str, payload: dict) -> None:
    """put_rule_set applies `payload` to the first ruleset with the same name,
    creating one if absent. `payload` must include `name`.

    NOTE: Repeated POST requests create duplicates; existing rulesets require
    PUT.
    """
    existing = gh_json("api", f"repos/{target}/rulesets", default=[])
    match = next(
        (rule for rule in existing if rule.get("name") == payload["name"]), None
    )

    if match:
        info(f"Updating existing rule set: {payload['name']}")
        gh_api("PUT", f"repos/{target}/rulesets/{match['id']}", payload)
    else:
        info(f"Creating rule set: {payload['name']}")
        gh_api("POST", f"repos/{target}/rulesets", payload)


def main_branch_rules(args: argparse.Namespace) -> list[dict]:
    """main_branch_rules returns default-branch rules for the requested
    visibility and direct-push policy.
    """
    rules: list[dict] = [
        {"type": "creation"},
        {"type": "deletion"},
        {"type": "required_linear_history"},
    ]

    if not args.allow_direct_push:
        rules.append(
            {
                "type": "pull_request",
                "parameters": {
                    "allowed_merge_methods": ["squash"],
                    "dismiss_stale_reviews_on_push": True,
                    "require_code_owner_review": True,
                    "require_last_push_approval": False,
                    "required_approving_review_count": 0,
                    "required_review_thread_resolution": True,
                    "required_reviewers": [],
                    "require_extra_approval_for_unattributed_changes": True,
                },
            }
        )
        rules.append(
            {
                "type": "required_status_checks",
                "parameters": {
                    "do_not_enforce_on_create": True,
                    "strict_required_status_checks_policy": True,
                    "required_status_checks": [
                        {
                            "context": context,
                            "integration_id": GITHUB_ACTIONS_APP_ID,
                        }
                        for context in args.status_check
                    ],
                },
            }
        )

    # NOTE: A required scanner with no results blocks merges; private scanning is paid.
    if args.public:
        rules.append(
            {
                "type": "code_scanning",
                "parameters": {
                    "code_scanning_tools": [
                        {
                            "tool": "CodeQL",
                            "security_alerts_threshold": "all",
                            "alerts_threshold": "all",
                        }
                    ]
                },
            }
        )

    return rules


def apply_rule_sets(args: argparse.Namespace, target: str) -> None:
    """apply_rule_sets reconciles the default-branch `main` and `push` rulesets.
    Force-push protection remains active when direct pushes are allowed.
    """
    info("Applying repository rule sets.")

    if args.allow_direct_push:
        # NOTE: Required checks also gate direct pushes, before their workflows can run.
        info("Allowing direct pushes: omitting the pull-request and check rules.")

    put_rule_set(
        target,
        {
            "name": "main",
            "enforcement": "active",
            "target": "branch",
            "bypass_actors": [
                {
                    "actor_id": REPOSITORY_ADMIN_ROLE_ID,
                    "actor_type": "RepositoryRole",
                    "bypass_mode": "pull_request",
                },
            ],
            "conditions": {"ref_name": {"exclude": [], "include": ["~DEFAULT_BRANCH"]}},
            "rules": main_branch_rules(args),
        },
    )

    put_rule_set(
        target,
        {
            "name": "push",
            "enforcement": "active",
            "target": "branch",
            "bypass_actors": [],
            "conditions": {"ref_name": {"exclude": [], "include": ["~DEFAULT_BRANCH"]}},
            "rules": [{"type": "non_fast_forward"}],
        },
    )


def apply_repository_settings(target: str) -> None:
    """apply_repository_settings applies merge defaults and disables projects and
    the wiki. Repository identity and issue settings remain unchanged.
    """
    info("Updating repository settings.")

    gh_write(
        "repo",
        "edit",
        target,
        "--allow-update-branch",
        "--delete-branch-on-merge",
        "--enable-auto-merge",
        "--enable-squash-merge",
        "--enable-merge-commit=false",
        "--enable-rebase-merge=false",
        "--enable-projects=false",
        "--enable-wiki=false",
    )

    # NOTE: Release-please parses squash titles; these fields require the REST API.
    gh_api(
        "PATCH",
        f"repos/{target}",
        {
            "squash_merge_commit_title": "PR_TITLE",
            "squash_merge_commit_message": "COMMIT_MESSAGES",
            "merge_commit_title": "MERGE_MESSAGE",
            "merge_commit_message": "PR_TITLE",
        },
    )


def apply_security_settings(args: argparse.Namespace, target: str) -> None:
    """apply_security_settings enables dependency alerts and fixes, plus secret
    and code scanning when `args.public` is true.
    """
    info("Updating repository security settings.")

    gh_api("PUT", f"repos/{target}/vulnerability-alerts")
    gh_api("PUT", f"repos/{target}/automated-security-fixes")

    # NOTE: Private scanning requires a paid entitlement this script does not provision.
    if not args.public:
        info("Skipping secret and code scanning: private repository.")
        return

    gh_write(
        "repo",
        "edit",
        target,
        "--enable-secret-scanning",
        "--enable-secret-scanning-push-protection",
    )
    gh_api(
        "PATCH", f"repos/{target}/code-scanning/default-setup", {"state": "configured"}
    )


def apply_actions_permissions(args: argparse.Namespace, target: str) -> None:
    """apply_actions_permissions applies token defaults and unions action
    patterns with the existing allowlist. Unrestricted existing repositories
    stay unrestricted unless patterns are supplied.
    """
    info("Updating repository's GitHub Actions permissions.")

    current = gh_json("api", f"repos/{target}/actions/permissions", default={}) or {}

    # NOTE: SHA enforcement rejects the floating major tags used for godot-infra
    # actions.
    permissions = {"enabled": True, "sha_pinning_required": False}

    unrestricted = current.get("allowed_actions") == "all"
    if args.existing and unrestricted and not args.allow_action:
        # NOTE: Switching an unrestricted repository to an empty allowlist breaks
        # actions.
        warn(
            "actions are unrestricted and no '--allow-action' was given; "
            "leaving 'allowed_actions' alone"
        )
    else:
        permissions["allowed_actions"] = "selected"

    gh_api("PUT", f"repos/{target}/actions/permissions", permissions)

    if permissions.get("allowed_actions") == "selected":
        selected = (
            gh_json(
                "api",
                f"repos/{target}/actions/permissions/selected-actions",
                default={},
            )
            or {}
        )
        # NOTE: Reconciliation must preserve patterns omitted from this invocation.
        patterns = sorted(
            set(selected.get("patterns_allowed", [])) | set(args.allow_action)
        )
        gh_api(
            "PUT",
            f"repos/{target}/actions/permissions/selected-actions",
            {
                "github_owned_allowed": True,
                "verified_allowed": True,
                "patterns_allowed": patterns,
            },
        )

    gh_api(
        "PUT",
        f"repos/{target}/actions/permissions/workflow",
        {
            "default_workflow_permissions": args.workflow_permissions,
            "can_approve_pull_request_reviews": False,
        },
    )


def set_secret(target: str, name: str) -> None:
    """set_secret reads the environment variable `name` and stores it on
    `target`. An unset or empty value raises; dry runs print only the secret
    name.

    NOTE: Secret values go through stdin and never enter verbose command
    output.
    """
    if not os.environ.get(name):
        raise RuntimeError(
            f"'--secret {name}' was given, but ${name} is unset or empty"
        )

    if DRY_RUN:
        # NOTE: CodeQL taints the name used to look up a secret; printing it is
        # intentional.
        print(f"dry-run: gh secret set {name} --repo {target} (value from ${name})")
        return

    subprocess.run(
        [GH, "secret", "set", name, "--repo", target],
        input=os.environ[name],
        capture_output=True,
        text=True,
        check=True,
    )


def apply_secrets(args: argparse.Namespace, target: str) -> None:
    """apply_secrets stores each requested secret from its environment variable.
    An unset or empty value stops the operation.
    """
    if not args.secret_names:
        return

    # NOTE: Printing only the count keeps CodeQL secret taint out of the shared logger.
    info(f"Setting {len(args.secret_names)} repository secret(s).")

    for name in args.secret_names:
        set_secret(target, name)


def check_visibility(args: argparse.Namespace, target: str) -> None:
    """check_visibility warns if the repository visibility differs from
    `args.public`, without changing either the visibility or the argument.
    """
    view = gh_json("repo", "view", target, "--json", "isPrivate", default=None)
    if view is None:
        return

    private = view["isPrivate"]
    if private == (not args.public):
        return

    actual = "private" if private else "public"
    wanted = "public" if args.public else "private"
    warn(f"repository is {actual}, but '{wanted}' was requested; leaving it alone")


def configure(args: argparse.Namespace, target: str) -> None:
    """configure reapplies repository settings, secrets and rulesets without
    changing content or visibility. Failures may leave earlier settings
    applied.
    """
    check_visibility(args, target)
    apply_repository_settings(target)
    apply_security_settings(args, target)
    apply_actions_permissions(args, target)
    apply_secrets(args, target)
    apply_rule_sets(args, target)


# ---------------------------------------------------------------------------- #
#                                    Checks                                    #
# ---------------------------------------------------------------------------- #


@dataclass
class Checklist:
    """Checklist collects follow-up actions and distinguishes unchecked content
    from a completed check with no findings.
    """

    # items preserves findings in reporting order.
    items: list[str] = field(default_factory=list)
    # ran distinguishes skipped checks from checks with no findings.
    ran: bool = False

    def add(self, item: str) -> None:
        self.items.append(item)

    def report(self) -> None:
        """report prints collected findings, or distinguishes a clean checklist
        from content checks that did not run.
        """
        if not self.ran:
            info("Settings applied. Content checks need a checkout; none was made.")
            return

        if not self.items:
            info("Nothing left to do by hand.")
            return

        print("\nStill to do by hand:")
        for item in self.items:
            print(f"  - {item}")


def workflow_files(repo: Path) -> list[Path]:
    """workflow_files returns sorted YAML paths directly under
    `.github/workflows`, or an empty list if the directory is absent.
    """
    workflows = repo / ".github" / "workflows"
    if not workflows.is_dir():
        return []

    return sorted(p for p in workflows.iterdir() if p.suffix in (".yml", ".yaml"))


def configured_secrets(target: str) -> set[str]:
    """configured_secrets returns repository secret names without accessing values."""
    secrets = gh_json("secret", "list", "--repo", target, "--json", "name", default=[])
    return {secret["name"] for secret in secrets or []}


def check_secrets(target: str, workflows: list[Path], checklist: Checklist) -> None:
    """check_secrets adds missing workflow secret names to `checklist`, excluding
    the built-in GITHUB_TOKEN.
    """
    wanted: set[str] = set()
    for workflow in workflows:
        wanted |= set(SECRET_REFERENCE.findall(workflow.read_text(encoding="utf-8")))

    wanted -= {"GITHUB_TOKEN"}
    missing = sorted(wanted - configured_secrets(target))
    for name in missing:
        checklist.add(f"set the '{name}' secret, which a workflow reads")


def check_third_party_actions(
    args: argparse.Namespace, target: str, workflows: list[Path], checklist: Checklist
) -> None:
    """check_third_party_actions adds external actions uncovered by explicit
    allow-action patterns to `checklist`. It does not change the allowlist.
    """
    owner = target.partition("/")[0]
    allowed = {pattern.partition("@")[0] for pattern in args.allow_action}

    uncovered: set[str] = set()
    for workflow in workflows:
        for action in USES_REFERENCE.findall(workflow.read_text(encoding="utf-8")):
            action_owner = action.partition("/")[0]
            if action_owner in ("actions", "github", owner) or action.startswith("./"):
                continue
            if action in allowed or f"{action_owner}/*" in allowed:
                continue

            uncovered.add(action)

    for action in sorted(uncovered):
        checklist.add(
            f"confirm '{action}' runs: no '--allow-action' pattern covers it, so "
            "it is permitted only if its creator is verified"
        )


def check_status_checks(
    args: argparse.Namespace, workflows: list[Path], checklist: Checklist
) -> None:
    """check_status_checks adds required contexts with no matching workflow job
    ID to `checklist`.
    """
    defined: set[str] = set()
    for workflow in workflows:
        defined |= set(JOB_ID.findall(workflow.read_text(encoding="utf-8")))

    for context in args.status_check:
        if context not in defined:
            checklist.add(
                f"no workflow defines a job named '{context}', so the required "
                "status check can never report"
            )


def check_workflow_permissions(workflows: list[Path], checklist: Checklist) -> None:
    """check_workflow_permissions adds workflows with no top-level permissions
    block to `checklist`.
    """
    for workflow in workflows:
        text = workflow.read_text(encoding="utf-8")
        if not TOP_LEVEL_PERMISSIONS.search(text):
            checklist.add(
                f"'{workflow.name}' declares no top-level 'permissions:' block, "
                "so it inherits the repository default"
            )


def check_code_owners(
    args: argparse.Namespace, repo: Path, checklist: Checklist
) -> None:
    """check_code_owners reports missing CODEOWNERS files when pull requests are
    required.
    """
    if args.allow_direct_push:
        return

    locations = (
        repo / "CODEOWNERS",
        repo / ".github/CODEOWNERS",
        repo / "docs/CODEOWNERS",
    )
    if any(path.is_file() for path in locations):
        return

    checklist.add(
        "the 'main' rule set requires code-owner review, but there is no "
        "CODEOWNERS file, so the rule is inert until someone adds one"
    )


def check_template_links(repo: Path, source: str, checklist: Checklist) -> None:
    """check_template_links adds readable files still referencing `source` to
    `checklist`, excluding Git metadata.
    """
    survivors = []
    for path in sorted(repo.rglob("*")):
        if not path.is_file() or ".git" in path.parts:
            continue

        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue

        if source in text:
            survivors.append(path.relative_to(repo).as_posix())

    for path in survivors:
        checklist.add(f"'{path}' still refers to '{source}'")


def run_checks(
    args: argparse.Namespace,
    repo: Path,
    source: str,
    target: str,
    checklist: Checklist,
) -> None:
    """run_checks marks content checks as attempted and collects findings from
    `repo`. A repository with no workflow files skips all checks.
    """
    checklist.ran = True

    workflows = workflow_files(repo)
    if not workflows:
        return

    check_secrets(target, workflows, checklist)
    check_third_party_actions(args, target, workflows, checklist)
    check_status_checks(args, workflows, checklist)
    check_workflow_permissions(workflows, checklist)
    check_code_owners(args, repo, checklist)
    check_template_links(repo, source, checklist)


# ---------------------------------------------------------------------------- #
#                                      CLI                                     #
# ---------------------------------------------------------------------------- #


def parse_args(argv: list[str]) -> argparse.Namespace:
    """parse_args validates CLI options and supplies defaults. Invalid
    combinations exit through argparse before repository operations begin.
    """
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    target = parser.add_argument_group("target")
    target.add_argument(
        "-n",
        "--name",
        required=True,
        help="the new repository's name, or 'owner/name' to target another owner",
    )
    target.add_argument(
        "-d",
        "--description",
        help=f"a description for the new repository (default={DEFAULT_DESCRIPTION!r})",
    )
    target.add_argument(
        "-t",
        "--template",
        help=(
            "the template repository, as 'name' or 'owner/name' "
            f"(default owner={DEFAULT_TEMPLATE_OWNER})"
        ),
    )
    target.add_argument(
        "-b",
        "--branch",
        help="the template's branch or commit to instantiate (default=main)",
    )
    target.add_argument(
        "--public",
        action="store_true",
        help="make the repository public (default=false)",
    )

    policy = parser.add_argument_group("policy")
    policy.add_argument(
        "--status-check",
        action="append",
        default=[],
        metavar="CONTEXT",
        help=(
            "a status check required to merge into the default branch; "
            f"repeatable (default={DEFAULT_STATUS_CHECK})"
        ),
    )
    policy.add_argument(
        "--allow-action",
        action="append",
        default=[],
        metavar="PATTERN",
        help=(
            "permit a third-party action pattern, in addition to those already "
            "allowed; repeatable"
        ),
    )
    policy.add_argument(
        "--allow-direct-push",
        action="store_true",
        help="drop the pull-request and status-check rules from the 'main' rule set",
    )
    policy.add_argument(
        "--workflow-permissions",
        choices=("read", "write"),
        default="read",
        help="the default GITHUB_TOKEN permissions (default=read)",
    )
    policy.add_argument(
        "--no-release",
        action="store_true",
        help="skip 'release-please' seeding and the initial tag",
    )

    secrets = parser.add_argument_group("secrets")
    secrets.add_argument(
        "--secret",
        dest="secret_names",
        action="append",
        default=[],
        metavar="NAME",
        help=(
            "set a repository secret from the environment variable of the same "
            "name; repeatable"
        ),
    )

    mode = parser.add_argument_group("mode")
    mode.add_argument(
        "--existing",
        action="store_true",
        help="skip creation and content bootstrap; apply settings only",
    )
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="print every mutating call without issuing it",
    )
    mode.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="print each command before running it",
    )

    args = parser.parse_args(argv)

    # NOTE: An argparse append default would remain when explicit checks are supplied.
    args.status_check = args.status_check or [DEFAULT_STATUS_CHECK]

    if args.existing:
        # NOTE: Bootstrap defaults must not overwrite an existing repository's metadata.
        for option, value in (
            ("--description", args.description),
            ("--branch", args.branch),
            ("--template", args.template),
        ):
            if value is not None:
                parser.error(f"argument {option}: not allowed with argument --existing")
    elif not args.template:
        parser.error("argument -t/--template: required unless --existing is given")

    args.description = args.description or DEFAULT_DESCRIPTION
    args.branch = args.branch or "main"

    return args


def repository_exists(target: str) -> bool:
    """repository_exists reports whether GitHub CLI can resolve `target`. Lookup
    failures, including authorization failures, return false.
    """
    return (
        subprocess.run(
            [GH, "repo", "view", target], capture_output=True, text=True
        ).returncode
        == 0
    )


def bootstrap(
    args: argparse.Namespace,
    source: str,
    target: str,
    name: str,
    checklist: Checklist,
) -> None:
    """bootstrap generates and initializes a new repository, refusing an existing
    target. Dry runs omit cloning and content changes.
    """
    if repository_exists(target):
        raise RuntimeError(
            "repository already exists; pass '--existing' to apply settings to it"
        )

    info("Verified repository doesn't exist yet.")

    identity = git_identity()
    create_repository(args, source, target)

    if DRY_RUN:
        info("Skipping content bootstrap: there is no repository to clone.")
        return

    if args.branch == "main":
        wait_for_population(target)

    with tempfile.TemporaryDirectory() as tmpdir:
        repo = Path(tmpdir) / name
        clone_repository(args, source, target, repo, identity)
        delete_other_branches(repo)
        update_contents(args, repo, source, target, name)

        if args.no_release:
            info("Skipping release setup; pushing 'main'.")
            run("git", "push", "-f", "origin", "main", cwd=repo)
        else:
            initialize_releases(repo)

        run_checks(args, repo, source, target, checklist)


def main(argv: list[str]) -> int:
    """main runs the requested bootstrap or reconciliation and returns zero on
    success or one on an operational failure. Invalid arguments exit through
    argparse.
    """
    global GH, VERBOSE, DRY_RUN

    args = parse_args(argv)
    VERBOSE = args.verbose
    DRY_RUN = args.dry_run
    checklist = Checklist()

    try:
        GH = resolve_gh()

        preflight(bootstrapping=not args.existing)

        target = qualify(args.name, current_user())
        name = target.rpartition("/")[2]
        source = qualify(args.template, DEFAULT_TEMPLATE_OWNER) if args.template else ""

        info("Executing command with the following parameters:")
        if source:
            print(f"  template (source): {source}")
            print(f"  branch (source): {args.branch}")
        print(f"  repository (target): {target}")
        if not args.existing:
            print(f"  description (target): {args.description}")

        if args.existing:
            if not repository_exists(target):
                raise RuntimeError(f"repository does not exist: {target}")
        else:
            bootstrap(args, source, target, name, checklist)

        configure(args, target)

        if args.existing:
            names = sorted(configured_secrets(target))
            info(f"Secrets currently set: {', '.join(names) if names else 'none'}")

        info(f"Configured repository: https://github.com/{target}")
        checklist.report()
        return 0
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", "") or ""
        print(f"error: {error}\n{detail}".rstrip(), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
