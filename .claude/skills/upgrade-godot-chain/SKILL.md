---
name: upgrade-godot-chain
description: Upgrades a set of local Godot repositories (addon forks, plugins, game projects) to the Godot release that godot-infra currently targets, one dependency at a time. Given repository paths, it orders them by dependency, writes a plan for approval, then bumps each repository and waits for it to publish before starting the ones that depend on it. Progress is recorded, so re-running resumes. Run /upgrade-godot on this repository first.
disable-model-invocation: true
argument-hint: "[<repo-path>...] [godot-version]"
---

Upgrade the local checkouts named in `$ARGUMENTS` to the Godot release that `godot-infra`'s `main`
currently targets, the top row of its README version table. A trailing argument that is not an
existing path is a version override, `X.Y.Z`, for moving repositories along an older line. No
arguments at all means resume the plan on file.

The mechanical edits go through `scripts/upgrade_godot_project.py`; this skill owns what a script
cannot: the order across repositories, waiting for each stage to publish, merging upstream into the
forks, and deciding what to keep from the editor's churn. When the script gets an edit wrong, fix
the script rather than patching the file by hand, so the next repository gets it right too.

Every command below runs from this repository's root. This repository is stage zero and is handled
by `/upgrade-godot`, not here; nothing below can start until `main`'s README version table names
the target and release-please has cut the matching tag.

The work runs in two phases. **Plan** derives the order and the state of every repository, writes
them to a plan file, and stops for approval. **Execute** works that plan one stage at a time and
records what happened. Bumps span days, so every run starts by reading the plan file and re-deriving
what the repositories can say for themselves.

## The plan file

`.claude/upgrade-godot-chain.md` in this repository, which `.gitignore` already excludes. Its
format and the per-route checklist templates are in `references/plan-file.md`. What matters here
is the authority rule, which the file's horizontal rule marks:

- **Above the rule is derived.** The target, the `godot-infra` tag, and the state table, paths
  included, are rebuilt from the repositories on every run and never trusted from the file. If the
  file and a remote disagree, the remote is right.
- **Below the rule is recorded.** One checklist per repository, ticked as steps land, each tick
  carrying what happened and what was decided: conflicts and how they were resolved, settings
  kept or pruned, fixes committed, PR numbers. Nothing else records these, so this half is the
  only source for resuming inside a stage.

A second device has the table but not the ticks, and resumes at stage granularity; that is the
accepted cost of not committing the file anywhere.

## Phase 1: Plan

1. **Resolve the target** before touching any repository:

   ```bash
   python3 scripts/upgrade_godot_project.py resolve
   ```

   Add `--godot-version X.Y.Z` only when the user gave one. It prints the Godot tag (`NEW_TAG`,
   e.g. `v4.7.2-stable`; `NEW` = its major.minor) and the `godot-infra` release that targets it
   (`INFRA_TAG`, e.g. `v5.0.0`). An `infra: none` line means stage zero is not done; stop and say
   which of `/upgrade-godot`, its merge, or its release is missing.

2. **Read the existing plan file**, if there is one. When no paths were given, take them from its
   table; when paths were given, they replace the table's.

   - Same target, `status: awaiting approval`: rebuild the table and present it again.
   - Same target, in progress or complete: skip to Phase 2.
   - A different target: a previous bump is on file. Show its status and ask whether to replace
     it; a complete one is safe to replace, an in-progress one is not.

3. **Fetch every path** (`git -C <repo> fetch origin`) and classify it from its files:

   | Kind | Signature | Bumped by |
   | --- | --- | --- |
   | fork | no `.godot-version`; `.github/workflows/publish.yaml` runs `package-addon` | the `fork` route |
   | project | `.godot-version` present | the `patch` or `minor` route |

   Anything else, stop and ask. Read each repository's facts rather than assuming them: the
   default branch from `git -C <repo> symbolic-ref refs/remotes/origin/HEAD`, a fork's upstream
   from `git -C <repo> remote get-url upstream`. Each project's dependencies are the `.gitmodules`
   URLs whose repository matches another path's `origin`. A submodule that points at a repository
   not in the list is still bumped, but its `godot-v<NEW>` branch has to exist already; the script
   checks.

4. **Order the work:** forks first, then projects so that each comes after everything it
   submodules. That reproduces the historical chain: addon forks such as `gut` and `GodotSteam` →
   `godot-plugin-std` → the plugin repositories → the project template → the games. Template before
   instance is convention, not a dependency, and the two can go in either order.

5. **Derive the state** of every repository: path, current pin or target branch, `godot-infra`
   pin, what it waits on, and whether its own `godot-v<NEW>` branch is already on `origin`:

   ```bash
   git -C <repo> ls-remote --heads origin "godot-v<NEW>"
   ```

   For each fork also fetch `upstream` and count
   `git -C <repo> rev-list --count origin/<default>..upstream/<default>`; a large number is worth a
   note for approval.

6. **Write the plan file** and stop. Each repository gets the checklist template for its kind and
   route. Under "Notes for approval" put anything the user should rule on: a multi-release jump, a
   repository that classified oddly, a dependency outside the list, heavy upstream drift. Present
   the table and the notes, then wait. Approval may drop or reorder repositories; edit the file to
   match, set `status: in progress`, and go on.

## Phase 2: Execute

**On entry, every time:** rebuild the table from the remotes. A repository whose `godot-v<NEW>`
branch is published is done, whatever its checklist says: tick its open lines with
`done elsewhere` so they are not re-entered. Then start at the first open line in the first open
stage. After each step, tick its line and record what happened on the same line.

Work each stage by the procedure for its kind in `references/stage-procedures.md`: the fork
procedure merges upstream, runs the `fork` route, commits, lands, and confirms the packaged branch;
the project procedure runs the `patch` or `minor` route, triages the editor's churn, runs the
repository's gate, checks the recurring mistakes, and opens the pull request.

When the only open item in the first open stage is a wait, for a packaged branch or a release PR
someone has to merge, say what is being waited on and stop. The next run picks up here.

### Completion

When every stage is done, set `status: complete <date>` and add a `## Follow-ups` section to
the plan file: churn deferred during triage, API renames found in one repository that others may
share, and the next patch release, which is this skill again with no arguments once
`/upgrade-godot` has moved `main` to it. The `patch` route is one line per repository. The days
after the last merge bring the deferred churn and the linter's findings; the weeks after bring the
first patch release.
