#!/bin/sh
set -eu

# This script instantiates one of @coffeebeats' template repositories. The list
# of supported repositories includes:
#
#   - https://github.com/coffeebeats/godot-project-template
#   - https://github.com/coffeebeats/godot-plugin-template
#   - https://github.com/coffeebeats/godot-prototype-template

# ------------------------------ Define: Cleanup ----------------------------- #

trap cleanup EXIT

cleanup() {
    cd
    if [ ! -z "${REPO_TMPDIR:-}" ]; then
        echo "Removing temporary directory: $REPO_TMPDIR"
    fi
}

# ------------------------------ Define: Logging ----------------------------- #

info() {
    if [ "$1" != "" ]; then
        echo info: "$@"
    fi
}

warn() {
    if [ "$1" != "" ]; then
        echo warning: "$1"
    fi
}

error() {
    if [ "$1" != "" ]; then
        echo error: "$1" >&2
    fi
}

fatal() {
    error "$1"
    exit 1
}

# ------------------------------- Define: Usage ------------------------------ #

usage() {
    cat <<EOF
instantiate-template-repository: Instantiates a @coffeebeats Godot-flavored
template repository.

Usage: instantiate-template-repository [OPTIONS]

NOTE: The following dependencies are required:
    - gh (GitHub CLI)
    - git

Available options:
    -h, --help          Print this help and exit
    -v, --verbose       Print script debug info (default=false)
    -n, --name          The name of the new repository.
    -d, --description   A description for the new repository.
    -t, --template      The name of the @coffeebeats template repository.
    -b, --branch        The template repository's branch or ref to instantiate (default=main).
    --public            Make the repository public (default=false).
EOF
    exit
}

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

need_cmd() {
    if ! check_cmd "$1"; then
        fatal "required command not found: '$1'"
    fi
}

# ------------------------------ Define: Params ------------------------------ #

parse_params() {
    BRANCH_NAME="main"
    REPO_NAME=""
    REPO_DESCRIPTION="A new Godot 4+ project."
    TEMPLATE_NAME=""
    PUBLIC=0

    while :; do
        case "${1:-}" in
        -h | --help) usage ;;
        -v | --verbose) set -x ;;

        -b | --branch)
            shift
            BRANCH_NAME="$1"
            ;;
        -d | --description)
            shift
            REPO_DESCRIPTION="$1"
            ;;
        -n | --name)
            shift
            REPO_NAME="$1"
            ;;
        --public)
            PUBLIC=1
            ;;
        -t | --template)
            shift
            TEMPLATE_NAME="$1"
            ;;

        -?*) fatal "Unknown option: $1" ;;
        "") break ;;
        esac
        shift
    done

    if [ -z "$BRANCH_NAME" ]; then fatal "Missing input: --branch"; fi
    if [ -z "$REPO_DESCRIPTION" ]; then fatal "Missing input: --description"; fi
    if [ -z "$REPO_NAME" ]; then fatal "Missing required input: --name"; fi
    if [ -z "$TEMPLATE_NAME" ]; then fatal "Missing required input: --template"; fi

    return 0
}

parse_params "$@"

# -------------------------------- Define: gh -------------------------------- #

GH="gh"
if ! check_cmd gh && check_cmd gh.exe; then
    GH="gh.exe"
fi

# ------------------------------- Define: User ------------------------------- #

need_cmd $GH

if ! $GH auth status >/dev/null 2>&1; then
    fatal "Failed to identify current GitHub user; please authenticate via 'gh'"
fi

GH_USER="$($GH api user -q ".login")"
if [ -z "$GH_USER" ]; then
    fatal "Failed to identify current GitHub user"
fi

GIT_USER_NAME=$(git config user.name)
if [ -z "$GIT_USER_NAME" ]; then
    fatal "Failed to identify current Git user's name"
fi

GIT_USER_EMAIL=$(git config user.email)
if [ -z "$GIT_USER_EMAIL" ]; then
    fatal "Failed to identify current Git user's email address"
fi

# ---------------------------- Define: Repository ---------------------------- #

SRC_REPOSITORY="coffeebeats/${TEMPLATE_NAME#coffeebeats/}"
DST_REPOSITORY="$GH_USER/$REPO_NAME"

info "Executing command with the following parameters:"
echo "  template (source): $SRC_REPOSITORY"
echo "  branch (source): $BRANCH_NAME"
echo "  repository (target): $DST_REPOSITORY"
echo "  description (target): $REPO_DESCRIPTION"

# --------------------------- Validate: Repository --------------------------- #

# Check if the repository exists
if $GH repo view "$DST_REPOSITORY" >/dev/null 2>&1; then
    fatal "Repository already exists; exiting without making changes."
fi

info "Verified repository doesn't exist yet."

# -------------------------- Run: Create repository -------------------------- #

create_repository() {
    info "Creating repository from template."

    $GH repo create "$DST_REPOSITORY" \
        --template "$SRC_REPOSITORY" \
        $([ "$BRANCH_NAME" != "main" ] && echo "--include-all-branches" || :) \
        --description "$REPO_DESCRIPTION" \
        --disable-wiki \
        --private

    # Update repository settings
    info "Updating repository settings."
    $GH repo edit "$DST_REPOSITORY" \
        --allow-update-branch \
        --delete-branch-on-merge \
        --enable-auto-merge \
        --enable-squash-merge \
        --enable-merge-commit=false \
        --enable-rebase-merge=false \
        --enable-projects=false
}

# ------------------ Run: Update GitHub Actions permissions ------------------ #

update_gha_permissions() {
    info "Updating repository's GitHub Actions permissions."

    cat <<EOM | $GH api --method PUT -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" --input - "repos/$DST_REPOSITORY/actions/permissions"
{
"enabled": true,
"allowed_actions": "all"
}
EOM

    cat <<EOM | $GH api --method PUT -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" --input - "repos/$DST_REPOSITORY/actions/permissions/workflow"
{
"default_workflow_permissions":"write",
"can_approve_pull_request_reviews":true
}
EOM
}

# --------------------------- Run: Clone repository -------------------------- #

need_cmd git
need_cmd mktemp

clone_repository() {
    REPO_TMPDIR="$(mktemp -d)"

    info "Cloning new repository to directory: $REPO_TMPDIR"
    $GH repo clone "$DST_REPOSITORY" "$REPO_TMPDIR"

    cd "$REPO_TMPDIR"

    # Configure the git user
    git config --local user.name "$GIT_USER_NAME"
    git config --local user.email "$GIT_USER_EMAIL"

    # Reset 'main' to the target ref
    git reset --hard "$BRANCH_NAME"

    # Push changes to remote repository
    info "Updating remote branch 'main' to ref: $BRANCH_NAME"
    git push -f origin main

    # Delete other branches
    for branch in $(git for-each-ref --format='%(refname:strip=2)' "refs/heads/"); do
        if [ "$branch" = "main" ]; then
            continue
        fi

        info "Deleting branch on remote repository: $branch"
        git push origin --delete "$branch"
    done
}

# --------------------------- Run: Update contents --------------------------- #

update_contents() {
    info "Updating repository's contents."

    # Remove LICENSE
    if [ "$PUBLIC" -eq 0 ]; then
        info "Removing license for private repository."
        rm LICENSE
    fi

    # Update CHANGELOG
    echo "# Changelog" >CHANGELOG.md

    # Update README
    cat <<EOM >README.md
# $REPO_NAME

$REPO_DESCRIPTION
$(tail -n+4 README.md)
EOM

    git add LICENSE CHANGELOG.md README.md
    git commit --amend --no-edit
}

# --------------------- Run: Initialize 'release-please' --------------------- #

initialize_releases() {
    info "Initializing release for the repository."

    # Update 'release-please' manifest
    cat <<EOM >.release-please/manifest.json
{
".": "0.1.0"
}
EOM

    # Commit changes
    git add .release-please/manifest.json
    git commit --amend --no-edit

    # Push changes to remote repository
    info "Updating 'release-please' manifest on remote"
    git push -f origin main

    # Tag the initial commit
    info "Tagging initial commit: v0.1.0"
    git tag v0.1.0
    git push origin tag v0.1.0
}

# ----------------------- Run: Create repository rules ----------------------- #

create_rule_sets() {
    info "Creating repository rule sets."

    # Create a rule which requires PRs and status checks to merge into the
    # default branch.
    cat <<EOM | $GH api --method POST -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" --input - "repos/$DST_REPOSITORY/rulesets"
{
    "name": "main",
    "enforcement": "active",
    "target": "branch",
    "bypass_actors": [
        {
            "actor_id": 2,
            "actor_type": "RepositoryRole"
        },
        {
            "actor_id": 4,
            "actor_type": "RepositoryRole"
        }
    ],
    "conditions": {
        "ref_name": {
            "exclude": [],
            "include": ["~DEFAULT_BRANCH"]
        }
    },
    "rules": [
        {
            "type": "creation"
        },
        {
            "type": "deletion"
        },
        {
            "type": "required_linear_history"
        },
        {
            "type": "pull_request",
            "parameters": {
                "allowed_merge_methods": ["squash"],
                "dismiss_stale_reviews_on_push": true,
                "require_code_owner_review": true,
                "require_last_push_approval": false,
                "required_approving_review_count": 0,
                "required_review_thread_resolution": true
            }
        },
        {
            "type": "required_status_checks",
            "parameters": {
                "do_not_enforce_on_create": true,
                "strict_required_status_checks_policy": true,
                "required_status_checks": [
                    {
                        "context": "branch_protection",
                        "integration_id": 15368
                    }
                ]
            }
        }
    ]
}
EOM

    # Create a rule which blocks everyone from force pushing to the default
    # branch.
    cat <<EOM | $GH api --method POST -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" --input - "repos/$DST_REPOSITORY/rulesets"
{
    "name": "push",
    "enforcement": "active",
    "target": "branch",
    "bypass_actors": [],
    "conditions": {
        "ref_name": {
            "exclude": [],
            "include": ["~DEFAULT_BRANCH"]
        }
    },
    "rules": [
        {
            "type": "non_fast_forward"
        }
    ]
}
EOM
}

# --------------------------------- Run: Main -------------------------------- #

main() {
    create_repository || fatal "Failed to create repository."
    update_gha_permissions || fatal "Failed to update GitHub Actions permissions."
    clone_repository || fatal "Failed to clone repository."
    update_contents || fatal "Failed to update repository contents."
    initialize_releases || fatal "Failed to initialize releases."
    create_rule_sets || fatal "Failed to create rule sets."
}

main
