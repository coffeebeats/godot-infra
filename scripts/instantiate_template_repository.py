#!/usr/bin/env python3
"""Instantiate a Godot-flavored template repository.

Creates a repository from a template, applies the recommended repository
settings, rewrites the generated contents for their new home, seeds
'release-please' at an initial version, and installs the branch rule sets.

'--template' and '--name' each take 'owner/name', or a bare name under a
default owner — @coffeebeats for the template, the authenticated user for the
new repository. The templates this was written against:

  - https://github.com/coffeebeats/godot-project-template
  - https://github.com/coffeebeats/godot-plugin-template

'--branch' takes a branch, or a commit in the default branch's history.
Template generation copies no tags, so a tag is not a valid target; pin by
commit instead.

Requires 'gh' (authenticated, with the 'repo' and 'workflow' scopes) and 'git'.
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

# The owner assumed for a '--template' given as a bare name, so the documented
# usage keeps working. Any 'owner/name' is honored as written.
DEFAULT_TEMPLATE_OWNER = "coffeebeats"

# The aggregate job @coffeebeats' workflows use to satisfy branch protection.
# A house convention rather than a universal one, hence '--status-check'.
DEFAULT_STATUS_CHECK = "branch_protection"

# GitHub's own Actions application, which reports every workflow job's status.
# Not an account-specific identifier.
GITHUB_ACTIONS_APP_ID = 15368

# The version a newly instantiated repository starts at. One constant feeds the
# 'release-please' manifest, the files it keeps in sync, and the initial tag, so
# the three cannot disagree.
INITIAL_VERSION = "0.1.0"

DEFAULT_DESCRIPTION = "A new Godot 4+ project."

RELEASE_PLEASE_CONFIG = Path(".release-please/config.json")
RELEASE_PLEASE_MANIFEST = Path(".release-please/manifest.json")

# 'gh repo edit' gained the merge-setting flags used below in v2.40.0.
MIN_GH_VERSION = (2, 40, 0)

# How long to wait for GitHub to populate a repository created from a template.
# 'gh repo create' returns before generation finishes (cli/cli#2290, #5142,
# #7055); cloning too early yields "couldn't find remote ref refs/heads/main"
# or a silently empty checkout.
POPULATE_TIMEOUT_SECONDS = 120
POPULATE_POLL_SECONDS = 2

GH_VERSION = re.compile(r"gh version (\d+)\.(\d+)\.(\d+)")
GH_SCOPES = re.compile(r"Token scopes:\s*(.+)")

README_HEADING = re.compile(r"^#\s+(?P<open>\*\*)?(?P<name>.+?)(?P<close>\*\*)?\s*$")
LICENSE_HEADING = re.compile(r"^##\s+\*\*License\*\*\s*$")

# A 'release-please' annotation, and the last double-quoted string ahead of it.
# Anchored at end of line so the capture is the nearest literal to the marker.
RELEASE_MARKER = re.compile(
    r'"(?P<literal>[^"]*)"(?P<tail>[^"]*#\s*'
    r"x-release-please-(?P<kind>version|major|minor|patch)\b.*)$"
)

# Everything ahead of the version in a literal such as "v5.2.0". Kept as-is:
# 'release-please' substitutes only the version, so a 'v' written into the file
# is the file's own text and survives every release.
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
    """The resolved path to 'name', or a failure naming what is missing."""
    found = shutil.which(name)
    if not found:
        raise RuntimeError(f"required command not found: '{name}'")
    return found


def resolve_gh() -> str:
    """The 'gh' executable, tolerating a Windows shell that only sees 'gh.exe'."""
    for name in ("gh", "gh.exe"):
        found = shutil.which(name)
        if found:
            return found
    raise RuntimeError("required command not found: 'gh'")


GH = ""
DRY_RUN = False


def gh(*args: str, check: bool = True, stdin: str | None = None) -> str:
    """A read-only 'gh' invocation, issued even under '--dry-run'."""
    return run(GH, *args, check=check, stdin=stdin)


def gh_write(*args: str, stdin: str | None = None, redact: bool = False) -> str:
    """A mutating 'gh' invocation, the one place '--dry-run' intercepts.

    Every change this script makes passes through here or 'gh_api', so dry-run
    is one branch rather than a flag threaded through each call site. 'redact'
    keeps a secret's value out of the printed payload.
    """
    if DRY_RUN:
        print(f"dry-run: gh {shlex.join(args)}")
        if stdin:
            print(indent("<redacted>" if redact else stdin))
        return ""

    return run(GH, *args, stdin=stdin)


def gh_json(*args: str, default: object = None) -> object:
    """A read whose result shapes a later write.

    Under '--dry-run' on a creating run the repository does not exist, so these
    reads cannot succeed; the default stands in for what would have been read.
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
    match = GH_VERSION.search(gh("--version"))
    if not match:
        raise RuntimeError("failed to determine the version of 'gh'")

    version = tuple(int(part) for part in match.groups())
    if version < MIN_GH_VERSION:
        want = ".".join(str(part) for part in MIN_GH_VERSION)
        have = ".".join(str(part) for part in version)
        raise RuntimeError(f"'gh' v{want} or newer is required; found v{have}")


def check_gh_scopes(required: tuple[str, ...]) -> None:
    """Authority, which 'gh auth status' alone does not prove.

    Pushing a commit that carries '.github/workflows/' needs 'workflow'; rule
    sets and repository settings need 'repo'.
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
    check_gh_version()

    # Pushing a commit that carries '.github/workflows/' needs 'workflow'; an
    # '--existing' run pushes nothing.
    check_gh_scopes(("repo", "workflow") if bootstrapping else ("repo",))

    if bootstrapping:
        need_cmd("git")


def qualify(repository: str, default_owner: str) -> str:
    """'owner/name' as given, or 'name' under 'default_owner'."""
    owner, separator, name = repository.rpartition("/")
    if separator and not owner:
        raise ValueError(f"invalid repository: '{repository}'")
    if not name:
        raise ValueError(f"invalid repository: '{repository}'")

    return f"{owner or default_owner}/{name}"


def current_user() -> str:
    user = gh("api", "user", "-q", ".login").strip()
    if not user:
        raise RuntimeError("failed to identify current GitHub user")

    return user


def git_identity() -> tuple[str, str]:
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
    """Create the repository. Everything reconfigurable lives in Configure."""
    info("Creating repository from template.")

    create = [
        "repo",
        "create",
        target,
        "--template",
        source,
        "--description",
        args.description,
        "--public" if args.public else "--private",
    ]
    if args.branch != "main":
        create.append("--include-all-branches")

    gh_write(*create)


def wait_for_population(target: str) -> None:
    """Block until the generated repository has a commit to clone."""
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
    """The commit for '--branch', preferring the remote-tracking branch.

    A fresh clone has only the default branch locally, and git's revision search
    covers 'refs/remotes/<name>' — a remote *called* '<name>', not 'origin/<name>'
    — so a remote-only branch does not resolve on its own.
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
    args: argparse.Namespace, target: str, repo: Path, identity: tuple[str, str]
) -> None:
    info(f"Cloning new repository to directory: {repo}")
    gh("repo", "clone", target, str(repo))

    name, email = identity
    run("git", "config", "--local", "user.name", name, cwd=repo)
    run("git", "config", "--local", "user.email", email, cwd=repo)

    commit = resolve_ref(repo, args.branch)
    info(f"Resetting 'main' to ref: {args.branch} ({commit[:7]})")
    run("git", "reset", "--hard", commit, cwd=repo)


def delete_other_branches(repo: Path) -> None:
    """Drop every generated branch but 'main', read from the remote.

    A fresh clone has one local branch, so the local ref list this replaces
    could never name a branch worth deleting.
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
    """Read without translating line endings, so a rewrite preserves them."""
    with path.open("r", encoding="utf-8", newline="") as file:
        return file.read()


def write_text(path: Path, text: str) -> None:
    with path.open("w", encoding="utf-8", newline="") as file:
        file.write(text)


def rewrite_readme(repo: Path, name: str, description: str, has_license: bool) -> None:
    readme = repo / "README.md"
    if not readme.is_file():
        raise RuntimeError("template has no 'README.md'")

    lines = read_text(readme).splitlines(keepends=True)
    if not lines or not lines[0].startswith("# "):
        raise RuntimeError("'README.md' does not open with a level-one heading")

    # Reuse the template's own heading decoration rather than flattening it.
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

        # Drop the heading, the blank line ahead of it, and everything after.
        body = body[: max(index - 1, 0)]

    write_text(readme, "".join(body))


def update_contents(
    args: argparse.Namespace, repo: Path, source: str, target: str, name: str
) -> None:
    info("Updating repository's contents.")

    # Only paths the template actually has are staged: a pathspec matching
    # nothing is a fatal error rather than a no-op.
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
    run("git", "commit", "--amend", "--no-edit", cwd=repo)


# ---------------------------------------------------------------------------- #
#                                   Releases                                   #
# ---------------------------------------------------------------------------- #


def release_extra_files(repo: Path) -> list[str]:
    """The files 'release-please' keeps in sync with the manifest."""
    config = repo / RELEASE_PLEASE_CONFIG
    if not config.is_file():
        return []

    packages = json.loads(config.read_text(encoding="utf-8")).get("packages", {})
    return packages.get(".", {}).get("extra-files", [])


def rewrite_release_markers(path: Path, version: str) -> int:
    """Rewrite the annotated version literals in one 'extra-files' entry."""
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
            # Keep a literal 'v' the file wrote for itself; 'release-please'
            # substitutes the version alone.
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
    info("Initializing release for the repository.")

    manifest = repo / RELEASE_PLEASE_MANIFEST
    if not manifest.is_file():
        warn(f"template has no '{RELEASE_PLEASE_MANIFEST}'; skipping release setup")
        return

    write_text(manifest, json.dumps({".": INITIAL_VERSION}, indent=2) + "\n")
    staged = [RELEASE_PLEASE_MANIFEST.as_posix()]

    # The manifest alone leaves the repository inconsistent: 'extra-files' still
    # carry the template's own version until they are rewritten too.
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
    """Create the named rule set, or update the one already carrying that name.

    The rule-set endpoint is not idempotent: a second POST creates a duplicate
    rather than replacing the original.
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

    # Code scanning needs Advanced Security on a private repository, and a rule
    # with no tool reporting blocks every merge.
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
    info("Applying repository rule sets.")

    if args.allow_direct_push:
        # Both rules go, not just the first: GitHub applies the status-check
        # rule to direct pushes as well as merges, so keeping it would block
        # every push for checks that never ran.
        info("Allowing direct pushes: omitting the pull-request and check rules.")

    put_rule_set(
        target,
        {
            "name": "main",
            "enforcement": "active",
            "target": "branch",
            # One entry, matching the family. Id 2 is a repository role; the
            # mapping is undocumented, so confirm it grants the intended bypass
            # before relying on it.
            "bypass_actors": [
                {
                    "actor_id": 2,
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

    # Not exposed by 'gh repo edit'. 'release-please' parses the squashed
    # commit's title, so it must be the pull request's.
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
    info("Updating repository security settings.")

    gh_api("PUT", f"repos/{target}/vulnerability-alerts")
    gh_api("PUT", f"repos/{target}/automated-security-fixes")

    # Secret scanning and code scanning both need Advanced Security on a
    # private repository, so both are public-only. A 'code_scanning' rule with
    # no tool reporting blocks every merge, which is what would otherwise make
    # a private repository unmergeable the moment it was created.
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
        "PUT", f"repos/{target}/code-scanning/default-setup", {"state": "configured"}
    )


def apply_actions_permissions(args: argparse.Namespace, target: str) -> None:
    info("Updating repository's GitHub Actions permissions.")

    current = gh_json("api", f"repos/{target}/actions/permissions", default={}) or {}

    # SHA pinning is deliberately off. godot-infra's own actions are consumed by
    # floating major tag ('@v5') across many dependent repositories, so
    # repository-level enforcement would mean churn in every dependent on every
    # infra release. Workflows pin third-party actions by hand instead.
    permissions = {"enabled": True, "sha_pinning_required": False}

    unrestricted = current.get("allowed_actions") == "all"
    if args.existing and unrestricted and not args.allow_action:
        # Narrowing an existing repository's allow-list is a manual act. One on
        # 'all' has no pattern list to union with, so reconciling it without
        # '--allow-action' would empty the list and break every workflow that
        # uses a third-party action. A repository being created has no workflow
        # runs to break, and 'selected' is the setting the family holds, so
        # Bootstrap always narrows and the closing checklist names whatever the
        # patterns do not cover.
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
        # Additive: a reconcile run that forgot a pattern must not silently
        # narrow what the repository already allows.
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
            # GitHub's default is off, and its hardening guidance is to leave it
            # off unless a workflow needs it. None here approves pull requests.
            "can_approve_pull_request_reviews": False,
        },
    )


def apply_secrets(args: argparse.Namespace, target: str) -> None:
    """Set each named secret from the environment variable of the same name."""
    if not args.secret:
        return

    info("Setting repository secrets.")

    for name in args.secret:
        value = os.environ.get(name)
        if not value:
            raise RuntimeError(
                f"'--secret {name}' was given, but ${name} is unset or empty"
            )

        # 'gh secret set' reads the value from stdin when '--body' is omitted,
        # so nothing sensitive reaches the process list.
        info(f"Setting secret: {name}")
        gh_write("secret", "set", name, "--repo", target, stdin=value, redact=True)


def check_visibility(args: argparse.Namespace, target: str) -> None:
    """Report, never change, a visibility that disagrees with the flag.

    Configure runs against repositories it did not create, where flipping
    visibility is never what the operator meant to ask for.
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
    """Everything that can be re-applied to an existing repository."""
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
    """What the run could not do for itself, reported rather than enforced."""

    items: list[str] = field(default_factory=list)
    ran: bool = False

    def add(self, item: str) -> None:
        self.items.append(item)

    def report(self) -> None:
        if not self.ran:
            # The content-derived checks need a checkout, which only a creating
            # run has. Saying nothing is left to do would claim more than was
            # looked at.
            info("Settings applied. Content checks need a checkout; none was made.")
            return

        if not self.items:
            info("Nothing left to do by hand.")
            return

        print("\nStill to do by hand:")
        for item in self.items:
            print(f"  - {item}")


def workflow_files(repo: Path) -> list[Path]:
    workflows = repo / ".github" / "workflows"
    if not workflows.is_dir():
        return []

    return sorted(p for p in workflows.iterdir() if p.suffix in (".yml", ".yaml"))


def configured_secrets(target: str) -> set[str]:
    secrets = gh_json("secret", "list", "--repo", target, "--json", "name", default=[])
    return {secret["name"] for secret in secrets or []}


def check_secrets(target: str, workflows: list[Path], checklist: Checklist) -> None:
    """Diff the secrets the workflows read against the ones that are set.

    This is the check that would have caught 'godot-project-template' storing a
    bot token under a name none of its workflows read: both token secrets are
    consumed as '${{ secrets.X || github.token }}', so a missing one degrades
    the pipeline silently instead of failing it.
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
    """Name third-party actions the allow-list does not cover.

    Reported only: deriving the allow-list from content would widen it
    silently, which is the opposite of what an allow-list is for.
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
    """A default of 'read' is only safe while every workflow declares its own."""
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
    """Catch references to the template that the rewrite did not reach."""
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
    """Content-derived checks, possible only while the checkout is in hand."""
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

    # 'append' adds to whatever default it is given, so the default is applied
    # here rather than seeded into the option.
    args.status_check = args.status_check or [DEFAULT_STATUS_CHECK]

    if args.existing:
        # Being past creation means being past the content stage, so nothing
        # naming content is accepted. '--description' matters most: it carries
        # a default, and writing it here would replace a live repository's own
        # description with this script's placeholder.
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
    """Everything that happens exactly once, at creation."""
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

    wait_for_population(target)

    with tempfile.TemporaryDirectory() as tmpdir:
        repo = Path(tmpdir) / name
        clone_repository(args, target, repo, identity)
        delete_other_branches(repo)
        update_contents(args, repo, source, target, name)

        if args.no_release:
            info("Skipping release setup; pushing 'main'.")
            run("git", "push", "-f", "origin", "main", cwd=repo)
        else:
            initialize_releases(repo)

        run_checks(args, repo, source, target, checklist)


def main(argv: list[str]) -> int:
    global GH, VERBOSE, DRY_RUN

    args = parse_args(argv)
    VERBOSE = args.verbose
    DRY_RUN = args.dry_run
    checklist = Checklist()

    try:
        GH = resolve_gh()

        # Nothing is pushed on an '--existing' run, so it needs no 'workflow'
        # scope and no git at all.
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
