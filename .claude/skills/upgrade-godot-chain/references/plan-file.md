# The plan file

`.claude/upgrade-godot-chain.md`. Everything above the horizontal rule is derived and rebuilt on
every run; everything below it is recorded and exists nowhere else.

## At approval time

```markdown
# Godot 4.7 upgrade

target: v4.7.2-stable (4.7)   infra: v5.0.0   planned: 2026-09-01
status: awaiting approval

| # | repository       | path                   | kind    | now            | waits on | godot-v4.7 |
|---|------------------|------------------------|---------|----------------|----------|------------|
| 1 | gut              | ~/src/gut              | fork    | godot-v4.6 @v4 | –        | no         |
| 2 | godot-plugin-std | ~/src/godot-plugin-std | project | v4.6.3 @v4.1.2 | gut      | no         |

Notes for approval:
- gut has 41 upstream commits since the last merge; expect conflicts.

---

## 1. gut (fork)
- [ ] merge upstream/main
- [ ] fork route: publish.yaml → godot-v4.7, v4.7-stable, package-addon@v5
- [ ] import with v4.7.2-stable; fix what it reports
- [ ] commit; push main; confirm origin/godot-v4.7

## 2. godot-plugin-std (project, minor route)
- [ ] gate: gut publishes godot-v4.7
- [ ] minor route; read warnings
- [ ] submodule update; import; triage project.godot churn
- [ ] gdformat, gdlint, gut headless
- [ ] recurring-mistakes checklist
- [ ] PR; merge; release-please release PR; confirm origin/godot-v4.7
```

`status` moves through `awaiting approval`, `in progress`, and `complete <date>`.

## Recording progress

A ticked line keeps its text and gains what happened, on the same line:

```markdown
- [x] merge upstream/main — 2026-09-02, conflict in plugin.cfg, took upstream; 1.0.3 → 1.1.0
- [x] minor route; read warnings — warning: README.md mentions godot-v4.6 in the changelog, left as is
- [x] submodule update; import; triage churn — kept [steam] initialization/app_id;
      pruned animation/compatibility/use_legacy_blend, matching the 4.6 decision
- [x] gdformat, gdlint, gut headless — 3 new unused-argument findings, fixed in
      `fix: silence unused-argument warnings under 4.7`
- [x] PR; merge — #212 merged 2026-09-03; release v5.0.0 merged; origin/godot-v4.7 confirmed
```

A stage whose branch turns out to be published already is ticked `— done elsewhere` on every open
line, so the next run does not re-enter it.

## Checklist templates

**Fork** (the `fork` route):

```markdown
- [ ] merge upstream/<branch>          (<default>, or upstream's version branch for the target)
- [ ] fork route: publish.yaml → godot-v<NEW>, v<NEW>-stable, package-addon@<INFRA major>
- [ ] import with <NEW_TAG>; fix what it reports          (only when the fork has a project.godot)
- [ ] commit; push <default>; confirm origin/godot-v<NEW>
```

**Project, minor route** (the previous pin is an older minor):

```markdown
- [ ] gate: <each fork or plugin it submodules> publishes godot-v<NEW>
- [ ] minor route; read warnings
- [ ] submodule update; import; triage project.godot churn
- [ ] custom.py: diff upstream modules <OLD>-stable → <NEW>-stable   (project repositories only)
- [ ] <gate commands from AGENTS.md>
- [ ] recurring-mistakes checklist
- [ ] PR; merge; release-please release PR; confirm origin/godot-v<NEW>   (plugins)
- [ ] PR; merge                                                          (projects)
```

**Project, patch route** (the previous pin is the same minor):

```markdown
- [ ] patch route
- [ ] import; keep the re-saves
- [ ] <gate commands from AGENTS.md>
- [ ] PR; merge
```

## Completion

```markdown
status: complete 2026-09-04

## Follow-ups
- [ ] phantom-camera 1.1.0 renamed follow_target → target: audit the template for the same call
- [ ] next patch release: /upgrade-godot-chain with no arguments after /upgrade-godot moves main
```
