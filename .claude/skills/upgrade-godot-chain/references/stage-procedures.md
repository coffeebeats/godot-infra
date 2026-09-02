# Stage procedures

Placeholders: `NEW_TAG`, `NEW`, and `INFRA_TAG` come from `resolve`; `OLD` is the major.minor of
the `old` field in the repository's summary JSON; `<default>` is the repository's default branch
as read from `origin/HEAD`; `<name>` is the repository's directory name.

## A fork

An addon fork carries upstream's history plus one publish workflow. On every push to the default
branch, `package-addon` flattens the addon into an orphan `godot-v<NEW>` branch, which is what
dependents submodule.

1. **Preflight:** clean tree, on `<default>`, `git pull --ff-only`.

2. **Merge upstream, never rebase.** The `upstream` remote is already configured and may live
   outside GitHub. Merge the upstream branch that carries the target Godot line: `<default>`
   usually, but an upstream that stages a release on a version branch (`git branch -r` lists
   something like `upstream/godot_4_7`) is merged from that branch instead, and `<default>` is
   left alone until upstream folds the branch back. A plain merge keeps the shared history, so the
   later merge of `<default>` sees those commits as already present; a squash would replay every
   one of them as a conflict.

   ```bash
   git fetch upstream && git merge upstream/<branch>
   ```

   Resolve conflicts inside `.github/` in favor of the fork's workflow. A conflict anywhere else is
   the user's call: show it, record the resolution, and stop if they need to look.

3. **Run the script.** The `fork` route rewrites the three tokens in `publish.yaml`: the target
   branch, the editor version, and the `package-addon` pin, which keeps its floating-major shape.

   ```bash
   python3 scripts/upgrade_godot_project.py upgrade --project <repo> --godot-version "<NEW_TAG>" --output "${TMPDIR:-/tmp}/<name>-upgrade.json"
   ```

4. **Check the addon against the new editor** when the fork has a `project.godot`:
   `gdenv install <NEW_TAG>`, then `godot --headless --import` from inside the repository. Errors
   and warnings here are the content fixes history shows: a stringification fix one release, a
   hundred generated `.uid` files another. Commit fixes separately from the merge and record them.

5. **Commit the workflow change** with the summary's `commit_title`, its own commit after the
   merge and any fixes.

6. **Land it:** `git push origin <default>`. If branch protection rejects the push, open a pull
   request instead and wait for its merge. Then confirm the packaged branch appeared before moving
   on:

   ```bash
   git ls-remote --heads origin "godot-v<NEW>"
   ```

   Dependents fail their gate until that line prints.

## A project

1. **Preflight:** clean tree. When `chore/godot/upgrade` exists and is not yet merged into
   `<default>` (`git branch --no-merged <default>` lists it), this stage was started earlier:
   switch to it and continue from the checklist. A merged one is left over from a previous bump:
   delete it. Otherwise start from `<default>`: `git pull --ff-only`, then
   `git switch -c chore/godot/upgrade`.

2. **Run the script.** It resolves every remote fact before its first write, so a failed gate
   leaves the tree untouched.

   ```bash
   python3 scripts/upgrade_godot_project.py upgrade --project <repo> --godot-version "<NEW_TAG>" --output "${TMPDIR:-/tmp}/<name>-upgrade.json"
   ```

   Read the summary JSON: `route`, `commit_title`, `old`, `changes`, `warnings`. `route: none`
   means this repository is done; move on. A warning is a file the script declined to guess at,
   and each one needs a decision, recorded on the checklist line.

3. **Check out the moved submodules** on the minor route, so the editor imports the new addons:

   ```bash
   git submodule update --init --recursive
   ```

4. **Run the editor** with the pin the script just wrote, from inside the repository, since
   `gdenv install` with no argument reads the pin in the working directory:

   ```bash
   gdenv install && godot --headless --import
   ```

   Then triage the churn, which is where every follow-up PR in the history came from:

   - **`project.godot` injected settings.** List every new key. Some stay (`[steam]`
     initialization, `vram_compression/import_etc2_astc`), some were reverted days later
     (`[animation] compatibility/...` in two repositories). Decide each with the user, checking the
     plan file for the same key decided in an earlier stage, and drop the rejects with
     `prune-settings --exclude <key>...`, which records them in the summary.
   - **`export_presets.cfg` new keys** in project repositories: keep, the exporter requires them.
   - **`*.import`, `*.uid`, and scene or resource re-saves:** keep. Stage them as their own
     `chore: upgrade project files` commit so the pin bump stays readable.

5. **Review `custom.py`** in project repositories, on the minor route. Every upstream module the
   file does not mention is compiled into the export template. Compare the module lists:

   ```bash
   diff <(gh api "repos/godotengine/godot/contents/modules?ref=<OLD>-stable" -q '.[].name') \
        <(gh api "repos/godotengine/godot/contents/modules?ref=<NEW>-stable" -q '.[].name')
   ```

   New modules default to on and cost binary size; decide each, and record which were disabled so
   the next project repository makes the same call.

6. **Run the repository's gate** from its `AGENTS.md` `## Commands` block: format, lint, tests.
   New warning names, renamed APIs and linter rules surface here. Fix them as `fix:` commits on
   the same branch and record each one; a fix in one repository usually foreshadows the same fix
   in the next.

7. **Guard against the recurring mistakes** before committing. Each one has shipped at least once:

   - every `coffeebeats/godot-infra/...@` reference names `<INFRA_TAG>`'s major, comments
     included (`git grep -n 'godot-infra/[^@ ]*@v' -- .github`). The script keeps each pin's
     shape, so a floating `@v4` becomes `@v5` while Dependabot-managed `@v4.1.2` becomes
     `@<INFRA_TAG>`. A summary warning names any workflow it could not re-pin;
   - the plugin README table gained a top row and demoted the old one, in the
     `- \`main\` / \`godot-v4.7\` (\`v5\`): \`v4.7\`` format;
   - the commit title is the summary's `commit_title`: `chore!:` on the minor route, because
     release-please reads the `!` to cut the major that publishes `godot-v<NEW>`;
   - no `.godot-infra` symlink is staged;
   - `.godot-version` names a patch, not a bare minor, unless the minor has no patch yet.

8. **Commit, push, open the pull request** with `gh pr create`, title from `commit_title`, body
   from the summary's changes and warnings. Bot-free, so CI runs on it. Record the PR number.

9. **Wait for the stage to publish** before starting a dependent. Plugins publish their
   `godot-v<NEW>` branch from `package-addon` on the first release after the bump, which means the
   upgrade PR *and* release-please's release PR both have to merge. Gate on the branch, not on the
   merge.
