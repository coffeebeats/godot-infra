# Changelog

## 0.3.6 (2024-05-14)

## What's Changed
* chore(ci): migrate `release-please` to new repository by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/218
* chore(ci): move `release-please` configuration into directory by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/220


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.3.5...v0.3.6

## 0.3.5 (2024-05-13)

## What's Changed
* fix(ci): prefix addon branches with `godot-` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/211
* fix(ci): commit changes even if change set is empty by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/213
* fix(ci): correctly handle committing a subdirectory by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/214
* chore(thirdparty): update `godot-steam` to latest by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/215
* chore: remove unnecessary branch property in `.gitmodules` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/216
* chore(thirdparty): update `gut` and `phantom-camera` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/217


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.3.4...v0.3.5

## 0.3.4 (2024-05-10)

## What's Changed
* chore(ci): standardize action and workflow names by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/200
* feat(ci): log in to `itch.io` prior to pushing a build by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/202
* fix(ci): pass correct `itch.io` project input by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/203
* fix(ci): correct syntax error in `setup-butler` action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/204
* fix(ci): set correct default version `LATEST` for `setup-butler` action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/205
* fix(ci): redirect `butler` version output to `stdout` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/206
* fix(ci): correct order of `butler` args by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/207
* fix(export): rename web HTML file to `index.html` for GH pages/`itchio` support by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/208
* fix(export): correctly rename HTML file to `index.html` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/209
* fix(ci): set `butler` API key for `push` step by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/210


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.3.3...v0.3.4

## 0.3.3 (2024-05-10)

## What's Changed
* fix(compile): reduce `web` image size; correctly set `emscripten` version by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/195
* fix(compile): add a linker flag to potentially solve compilation error on `web` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/197
* fix(compile): correctly generate `web` export template by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/198
* fix(export): fix upload path; don't use an environment variable by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/199


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.3.2...v0.3.3

## 0.3.2 (2024-05-08)

## What's Changed
* chore(compile): remove redundant platform argument by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/191
* fix(ci): pin the `emscripten` SDK version to match the official Godot builds by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/193
* fix(ci): install missing dependency for `web` compile image by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/194


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.3.1...v0.3.2

## 0.3.1 (2024-05-08)

## What's Changed
* fix(compile): correctly handle `web` export template filename by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/187
* fix(export): always upload the entire `dist/` directory by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/189
* fix(compile): use correct `web` image for compile action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/190


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.3.0...v0.3.1

## 0.3.0 (2024-05-08)

## What's Changed
* feat(compile): create an image and action for compiling `web` builds by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/182
* feat(export): add an action for `web` exports by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/184
* feat!: document supported platforms and usage by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/185
* fix(ci): ensure scheduled image builds can run without changes by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/186


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.12...v0.3.0

## 0.2.12 (2024-05-08)

## What's Changed
* fix(export): correctly pass `--export-pack` flag by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/178
* fix(export): use correct PCK export flag by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/180
* feat(export): set `pck-only` based on extension of exported file by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/181


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.11...v0.2.12

## 0.2.11 (2024-05-07)

## What's Changed
* chore(ci): move `publish-project-itchio` action to public directory by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/175
* feat(export): publish an output `root` for locating the root of exported files by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/177


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.10...v0.2.11

## 0.2.10 (2024-05-06)

## What's Changed
* fix(ci): enable glob-related options in `check-code-formatting` action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/172
* fix(ci): enable `globstar` and `extglob` during linting by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/174


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.9...v0.2.10

## 0.2.9 (2024-05-06)

## What's Changed
* fix(ci): use correct action name `check-code-formatting` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/157
* fix: update how `check-godot-project` invokes its command by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/159
* feat: allow customizing the published artifact name by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/160
* fix(export): remove `preset-output-name` input; gather from `export_presets.cfg` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/161
* fix(ci): correct output syntax for `inspect-godot-export-presets` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/162
* fix: use correct path to script in `inspect-godot-export-presets` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/163
* fix(ci): check for correct length of set arguments by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/164
* fix(inspect): skip CLI version output by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/165
* fix(ci): add missing `esac` to run step by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/166
* fix(ci): correct form export path by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/167
* fix(ci): refactor export presets script; ensure changes are saved by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/168
* chore(ci): add debug logging to `inspect-godot-export-presets` action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/169
* chore: delete unused input in platform-specific export actions by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/170
* fix(export): pass correct project path to export presets inspect action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/171


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.8...v0.2.9

## 0.2.8 (2024-05-04)

## What's Changed
* feat: create an action for checking a Godot project by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/153
* chore(ci): create action to archive Vulkan SDK by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/155
* feat: add action to commit changes by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/156


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.7...v0.2.8

## 0.2.7 (2024-05-04)

## What's Changed
* fix(ci): clean up Godot source code after compile action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/148
* fix: use `sudo` to move folder generated by `root` Docker user by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/150
* fix(ci): use `sudo` to remove the Godot source code by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/151
* fix(ci): check build-related directories; rename `dist` to `build` to avoid interference by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/152


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.6...v0.2.7

## 0.2.6 (2024-05-03)

## What's Changed
* fix(ci): don't store editor binary in `.godot` directory by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/144
* fix(ci): run all Godot scripts from within project directory by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/146
* fix(ci): remove unnecessary path component by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/147


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.5...v0.2.6

## 0.2.5 (2024-05-01)

## What's Changed
* feat(ci): cache compiled export template immediately after success by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/133
* fix(export): copy project source into unique temporary directory by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/135
* fix(ci): update export action to require a path to the export template by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/136
* chore(ci): remove now-unused workflow `publish-image-compile-godot-export-template-windows.yaml` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/137
* fix(ci): check out export scripts from `godot-infra` repository by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/138
* refactor(export): simplify godot scripts for manipulating `export_presets.cfg` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/139
* chore(thirdparty): add support for `phantom-camera` fork management by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/140
* feat(ci): add support for syncing with a custom addon revision by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/141
* fix(ci): only allow checking out a commit in `publish-addon-update.yaml` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/142
* fix(ci): ensure addons don't publish Git-related files by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/143


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.4...v0.2.5

## 0.2.4 (2024-04-30)

## What's Changed
* fix(action): reference docker images with protocol by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/127
* fix(ci): eliminate unnecessary wildcard when comparing Godot versions by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/129
* fix(ci): remove redundant source code relocate step by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/130
* fix(ci): only set encryption key if one is passed by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/131
* fix(ci): correctly parse Godot CLI version string by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/132


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.3...v0.2.4

## 0.2.3 (2024-04-30)

## What's Changed
* fix(ci): correct syntax error in `parse-godot-version` action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/124
* fix(ci): pin workflows to `main` until such time that `v4.3` becomes primary by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/126


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.2...v0.2.3

## 0.2.2 (2024-04-30)

## What's Changed
* fix(ci): update export action to correctly accept editor version by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/120
* feat(ci): update `parse-godot-version` to handle `gdenv` pin files by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/122
* feat(ci): make publish step optional; fix outputs by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/123


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.1...v0.2.2

## 0.2.1 (2024-04-29)

## What's Changed
* chore(ci): reset test workflow by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/117
* fix(ci): fix syntax error in `compile-godot-export-template` action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/119


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.2.0...v0.2.1

## 0.2.0 (2024-04-29)

## What's Changed
* feat: migrate public workflows to versioned actions by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/112
* chore: remove `example` project by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/114
* refactor(ci)!: replace `compile-` and `export-` workflows with existing actions by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/115
* refactor(ci): merge platform-specific image publish workflows by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/116


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.1.5...v0.2.0

## 0.1.5 (2024-04-29)

## What's Changed
* fix(ci): ensure repository is checked out before creating tags by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/110


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.1.4...v0.1.5

## 0.1.4 (2024-04-29)

## What's Changed
* feat(ci): maintain major tags during release by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/108


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.1.3...v0.1.4

## 0.1.3 (2024-04-29)

## What's Changed
* fix(ci): correctly upload directory exports for `macos` by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/102
* fix(ci): use sudo for moving a file generated by root user in container by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/104
* fix(ci): include `arch` in export template cache key by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/105
* fix(ci): correctly delete all intermediate `macos` compilation artifacts by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/106
* chore(example): change icon to be more different from default by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/107


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.1.2...v0.1.3

## 0.1.2 (2024-04-29)

## What's Changed
* feat(ci): build images if missing by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/99
* feat(ci): set minimum Godot version for export action by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/101


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.1.1...v0.1.2

## 0.1.1 (2024-04-28)

## What's Changed
* chore: unpin release version; switch to `github` changelog by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/96
* fix(ci): skip `godot-major-minor-version` job if no changes found by @coffeebeats in https://github.com/coffeebeats/godot-infra/pull/98


**Full Changelog**: https://github.com/coffeebeats/godot-infra/compare/v0.1.0...v0.1.1

## [0.1.0](https://github.com/coffeebeats/godot-infra/compare/v0.1.0...v0.1.0) (2024-04-28)


### Features

* **ci,containers:** create a `godot-infra` build container; define a workflow to build image ([#11](https://github.com/coffeebeats/godot-infra/issues/11)) ([f961717](https://github.com/coffeebeats/godot-infra/commit/f961717c5f6545de329eddaf31f9a8a4117db9e4))
* **ci:** add action to compile a `Godot` export template ([#19](https://github.com/coffeebeats/godot-infra/issues/19)) ([bc6030b](https://github.com/coffeebeats/godot-infra/commit/bc6030b0e0d7007b27c9099c39ea1dc5a73ebf46))
* **ci:** add actions for setting up `butler` and publishing to `itch.io` ([#13](https://github.com/coffeebeats/godot-infra/issues/13)) ([5beb4ff](https://github.com/coffeebeats/godot-infra/commit/5beb4ffe268f03bf89104840f8bc4083b8fc5a88))
* **ci:** add Dependabot support and PR/Issue templates ([#1](https://github.com/coffeebeats/godot-infra/issues/1)) ([6447afb](https://github.com/coffeebeats/godot-infra/commit/6447afb0687407e87e4fcc40c02fbd33f2571f30))
* **ci:** add support for using `main` as current stable branch ([b059448](https://github.com/coffeebeats/godot-infra/commit/b05944831023b1a56048e83294844c84fb413681))
* **ci:** add workflow to export targets ([#30](https://github.com/coffeebeats/godot-infra/issues/30)) ([4d7aa8c](https://github.com/coffeebeats/godot-infra/commit/4d7aa8c96062b2edc55c2488f21f0418cba8e925))
* **ci:** build `MoltenVK` from source using `Xcode` 14+ ([#14](https://github.com/coffeebeats/godot-infra/issues/14)) ([72a3a94](https://github.com/coffeebeats/godot-infra/commit/72a3a944890186727c313371ed5d11d1aa163997))
* **ci:** correctly publish images after a release ([#88](https://github.com/coffeebeats/godot-infra/issues/88)) ([f1871f9](https://github.com/coffeebeats/godot-infra/commit/f1871f9b97b71b91fb17426e412743f82a2fb154))
* **ci:** create a placeholder workflow ([#20](https://github.com/coffeebeats/godot-infra/issues/20)) ([8807449](https://github.com/coffeebeats/godot-infra/commit/8807449a9d41379854175b29e3726a3b74d6eaf8))
* **ci:** create actions and workflows for export Godot project presets ([#59](https://github.com/coffeebeats/godot-infra/issues/59)) ([3b30836](https://github.com/coffeebeats/godot-infra/commit/3b308360b8f563d8dfed39c7fbfa3e75563ad233))
* **ci:** create export images ([#57](https://github.com/coffeebeats/godot-infra/issues/57)) ([d80a3b1](https://github.com/coffeebeats/godot-infra/commit/d80a3b1ee8b18561b1ee0171ac7855b5b0f7d5b6))
* **ci:** create new container actions for building Godot export templates ([#46](https://github.com/coffeebeats/godot-infra/issues/46)) ([3064568](https://github.com/coffeebeats/godot-infra/commit/3064568f230e317b54197daaedec6a29aff472d7))
* **ci:** create new streamlined action for compiling Godot export templates ([#52](https://github.com/coffeebeats/godot-infra/issues/52)) ([90ae547](https://github.com/coffeebeats/godot-infra/commit/90ae547972bd35184714d4d7bd6e310f775f8d66))
* **ci:** define a `MoltenVK` packaging workflow ([#3](https://github.com/coffeebeats/godot-infra/issues/3)) ([c556525](https://github.com/coffeebeats/godot-infra/commit/c5565257fa97d5f5dca920ae2deb2ead4fac986c))
* **ci:** define a workflow to compile `Godot` export templates ([#21](https://github.com/coffeebeats/godot-infra/issues/21)) ([ee21433](https://github.com/coffeebeats/godot-infra/commit/ee214333616baad18aeb0ec089fd14d163556492))
* **ci:** define an action and workflow for packaging the macOS SDK ([#6](https://github.com/coffeebeats/godot-infra/issues/6)) ([1d3dfc9](https://github.com/coffeebeats/godot-infra/commit/1d3dfc92e71716b2ff98915f7e14c349b3dccdbe))
* **ci:** implement improved compilation workflow ([#54](https://github.com/coffeebeats/godot-infra/issues/54)) ([15db79d](https://github.com/coffeebeats/godot-infra/commit/15db79d575d95fd66da6a62d559e676bf0399adb))
* **ci:** implement releases for `godot-v*`-versioned branches ([#87](https://github.com/coffeebeats/godot-infra/issues/87)) ([9b14f4e](https://github.com/coffeebeats/godot-infra/commit/9b14f4efccc6bdd8e462ddb439a948b35205adce))
* **ci:** install `gdenv` in `compile-godot-export-template` images ([#48](https://github.com/coffeebeats/godot-infra/issues/48)) ([f2a96cb](https://github.com/coffeebeats/godot-infra/commit/f2a96cb2bf4276e78e1a0d90904be9479d156074))
* **container:** add support for Linux export templates ([#22](https://github.com/coffeebeats/godot-infra/issues/22)) ([451cf6b](https://github.com/coffeebeats/godot-infra/commit/451cf6bfdadcc4777c388ba10ef29634393dc616))
* create export images ([d80a3b1](https://github.com/coffeebeats/godot-infra/commit/d80a3b1ee8b18561b1ee0171ac7855b5b0f7d5b6))
* **deps:** create workflow for managing addon dependencies ([#43](https://github.com/coffeebeats/godot-infra/issues/43)) ([d353de0](https://github.com/coffeebeats/godot-infra/commit/d353de022c8b149fc27ab6a787cdb2432a7192a8))
* **thirdparty:** add `GodotSteam` addon as submodule dependency ([#51](https://github.com/coffeebeats/godot-infra/issues/51)) ([0e797d7](https://github.com/coffeebeats/godot-infra/commit/0e797d754e44ddfb5389711eb20deebd557c0ecb))
* **thirdparty:** add `tpoechtrager/osxcross` as a submodule ([#7](https://github.com/coffeebeats/godot-infra/issues/7)) ([53c7824](https://github.com/coffeebeats/godot-infra/commit/53c7824152699550c4e2117d7be29669cf01ed4e))


### Bug Fixes

* **ci:** address issues with target exports ([#31](https://github.com/coffeebeats/godot-infra/issues/31)) ([cb1acf2](https://github.com/coffeebeats/godot-infra/commit/cb1acf2b8d8e50e59a36e279fea8be98054b527b))
* **ci:** always run `gdbuild template` commands in a container ([#38](https://github.com/coffeebeats/godot-infra/issues/38)) ([176af68](https://github.com/coffeebeats/godot-infra/commit/176af6831d8e3b6f3a223cce0d615fad871b1038))
* **ci:** correct compile commands for `windows` and `macos` ([#67](https://github.com/coffeebeats/godot-infra/issues/67)) ([a19029a](https://github.com/coffeebeats/godot-infra/commit/a19029aa4cf5ee332901abb5995fce02b0f816ec))
* **ci:** correct handling of multiple commands in `macos` compiles ([#73](https://github.com/coffeebeats/godot-infra/issues/73)) ([8c396b1](https://github.com/coffeebeats/godot-infra/commit/8c396b1e6e6d0b9fc1aeb4737afe3951a9c0b6c2))
* **ci:** correct syntax and implementation errors for export workflow ([#63](https://github.com/coffeebeats/godot-infra/issues/63)) ([36ed17c](https://github.com/coffeebeats/godot-infra/commit/36ed17ca31add6d6792f2864504f27838564410d))
* **ci:** correct syntax errors in actions ([#60](https://github.com/coffeebeats/godot-infra/issues/60)) ([91667b2](https://github.com/coffeebeats/godot-infra/commit/91667b253fffde3f9b98b0013e65881a0aebba54))
* **ci:** correctly capture multiline command in `macos` compile action ([#72](https://github.com/coffeebeats/godot-infra/issues/72)) ([acdddb4](https://github.com/coffeebeats/godot-infra/commit/acdddb4e97334282cc90ee9e1fed9ab85a9de163))
* **ci:** correctly check `force` input and set remote during push ([#44](https://github.com/coffeebeats/godot-infra/issues/44)) ([6356ba2](https://github.com/coffeebeats/godot-infra/commit/6356ba2cc2325cb50eb68dedcec65630a608b62e))
* **ci:** correctly check out Godot source code revision ([#68](https://github.com/coffeebeats/godot-infra/issues/68)) ([fbcb3d4](https://github.com/coffeebeats/godot-infra/commit/fbcb3d4d00fcd6f4fad147d91cb7f02bf356fba3))
* **ci:** correctly generate app bundle for MacOS export templates ([#81](https://github.com/coffeebeats/godot-infra/issues/81)) ([4207978](https://github.com/coffeebeats/godot-infra/commit/4207978b1e4de317978122b6d8ef6599c664ab9c))
* **ci:** correctly handle 'else' branch setting failing exit code ([#61](https://github.com/coffeebeats/godot-infra/issues/61)) ([19267cf](https://github.com/coffeebeats/godot-infra/commit/19267cf384838ee898f05091276890c45bd7e581))
* **ci:** correctly parse number inputs in workflows ([#16](https://github.com/coffeebeats/godot-infra/issues/16)) ([abb88f1](https://github.com/coffeebeats/godot-infra/commit/abb88f1d83124b3584551f4d04e2b3acd8a75846))
* **ci:** correctly prefix output path for `macos.zip` ([#77](https://github.com/coffeebeats/godot-infra/issues/77)) ([f1b36fb](https://github.com/coffeebeats/godot-infra/commit/f1b36fb35bccf37cbaa170e3d13646a663060ad0))
* **ci:** correctly wire up encryption keys ([#35](https://github.com/coffeebeats/godot-infra/issues/35)) ([e490ee7](https://github.com/coffeebeats/godot-infra/commit/e490ee7c5ba870b7c0ffe3ed9ed9acd20a498f84))
* **ci:** create app bundle archive without incorrect path prefix `godot/bin/` ([#86](https://github.com/coffeebeats/godot-infra/issues/86)) ([e8b1819](https://github.com/coffeebeats/godot-infra/commit/e8b18198aae48e160b573c837d41656dade6fc27))
* **ci:** create app bundle even if `macos` build arch is non-`universal` ([#70](https://github.com/coffeebeats/godot-infra/issues/70)) ([420d035](https://github.com/coffeebeats/godot-infra/commit/420d035b7d3f53555e64e1c18b3e5b2018a472dd))
* **ci:** don't cache entire home directory when installing Godot editor ([#83](https://github.com/coffeebeats/godot-infra/issues/83)) ([95d60ad](https://github.com/coffeebeats/godot-infra/commit/95d60ad29ce7d65a26a354855c8b623a26e3c62d))
* **ci:** enable layer compression to save on disk space ([#25](https://github.com/coffeebeats/godot-infra/issues/25)) ([b29d2d5](https://github.com/coffeebeats/godot-infra/commit/b29d2d5e18219bc5f8004be02f58f2ad09d1ba2d))
* **ci:** ensure Windows icon background is transparent ([#65](https://github.com/coffeebeats/godot-infra/issues/65)) ([ca9d5a0](https://github.com/coffeebeats/godot-infra/commit/ca9d5a0295f7c55d3bc52d67f10941c4c9db071c))
* **ci:** execute `target` in a container ([#41](https://github.com/coffeebeats/godot-infra/issues/41)) ([a933861](https://github.com/coffeebeats/godot-infra/commit/a933861b47654450f8ed252163125be3211c71a8))
* **ci:** extract export template archive directly to specified directory ([#32](https://github.com/coffeebeats/godot-infra/issues/32)) ([486750e](https://github.com/coffeebeats/godot-infra/commit/486750ee50fdf3553a14d9fc32a289b5c058ff79))
* **ci:** free up additional runner disk space during `godot-infra` image builds ([#18](https://github.com/coffeebeats/godot-infra/issues/18)) ([aba57b0](https://github.com/coffeebeats/godot-infra/commit/aba57b03aed79536c8be708d3a13855350ff9098))
* **ci:** import project before exporting on `macos` ([#90](https://github.com/coffeebeats/godot-infra/issues/90)) ([7943675](https://github.com/coffeebeats/godot-infra/commit/794367563e686628e9eef6ed600266cb68964f99))
* **ci:** pass required arguments to `MoltenVK` action; remove redundant caching ([#15](https://github.com/coffeebeats/godot-infra/issues/15)) ([089cb09](https://github.com/coffeebeats/godot-infra/commit/089cb09af6155a2f3013641c21caf2c0b3241af5))
* **ci:** pin to latest working `buildah` version ([#24](https://github.com/coffeebeats/godot-infra/issues/24)) ([1336df0](https://github.com/coffeebeats/godot-infra/commit/1336df0c2978baa784103bba156d045855389ad3))
* **ci:** properly authenticate the `gh` cli ([#5](https://github.com/coffeebeats/godot-infra/issues/5)) ([36a939b](https://github.com/coffeebeats/godot-infra/commit/36a939b91ac7b3502a7b1e9249ec168182a6bbb9))
* **ci:** remove non-determinism from Godot source code clones ([#62](https://github.com/coffeebeats/godot-infra/issues/62)) ([55b9a00](https://github.com/coffeebeats/godot-infra/commit/55b9a0019e0485b5fd6ca100286b6aad6ef4d9d0))
* **ci:** remove outdated runner OS check ([#4](https://github.com/coffeebeats/godot-infra/issues/4)) ([c283eda](https://github.com/coffeebeats/godot-infra/commit/c283edafce03f2c08d61ecc87b93890e22444d36))
* **ci:** remove redundant path element from downloaded artifact ([#33](https://github.com/coffeebeats/godot-infra/issues/33)) ([7bb9677](https://github.com/coffeebeats/godot-infra/commit/7bb96773a0c837ba2cbe9f4e84c167c9d83edbaa))
* **ci:** remove trailing `"` character accidentally removed ([#27](https://github.com/coffeebeats/godot-infra/issues/27)) ([c642759](https://github.com/coffeebeats/godot-infra/commit/c6427595afbcd87b179269e3e7cff94fad7e598f))
* **ci:** set encryption key via GitHub secret ([#34](https://github.com/coffeebeats/godot-infra/issues/34)) ([6e2a735](https://github.com/coffeebeats/godot-infra/commit/6e2a735ab0e08ef7e8f5d0aedd871dc43a8f53a7))
* **ci:** skip install step of `gdenv` and `gdpack` setup ([#12](https://github.com/coffeebeats/godot-infra/issues/12)) ([3b51870](https://github.com/coffeebeats/godot-infra/commit/3b51870aa8a6911ea95b43cac2c92717a2b8bcfa))
* **ci:** switch `buildah` channels to one that's OS version-specific ([1336df0](https://github.com/coffeebeats/godot-infra/commit/1336df0c2978baa784103bba156d045855389ad3))
* **ci:** temporarily set exit code for Godot export commands ([#84](https://github.com/coffeebeats/godot-infra/issues/84)) ([e8c980f](https://github.com/coffeebeats/godot-infra/commit/e8c980f5d6ab253d4f4437d3db7f98b1d6840d38))
* **ci:** temporarily use `default` changelog type for releases ([#94](https://github.com/coffeebeats/godot-infra/issues/94)) ([43a6070](https://github.com/coffeebeats/godot-infra/commit/43a6070a7cb1bff46781ef759ae4ae09c0bbdfa0))
* **ci:** update macOS SDK packaging workflow to initialize `osxcross` submodule ([#8](https://github.com/coffeebeats/godot-infra/issues/8)) ([bbcc679](https://github.com/coffeebeats/godot-infra/commit/bbcc67983765ab6d34b07f875ff4b72f117aff8c))
* **ci:** use correct cache key for templates; remove now-unnecessary intermediate `dist` directory ([#26](https://github.com/coffeebeats/godot-infra/issues/26)) ([d6bd0c4](https://github.com/coffeebeats/godot-infra/commit/d6bd0c4a381d4c1e9302e7d28f7fd69ef17d2d1d))
* **ci:** use correct export action for `macos` project exports ([#79](https://github.com/coffeebeats/godot-infra/issues/79)) ([092315e](https://github.com/coffeebeats/godot-infra/commit/092315e3db8594305950e89d3aa988237c3d784c))
* **ci:** use correct image to compile `macos` builds ([#69](https://github.com/coffeebeats/godot-infra/issues/69)) ([76becd9](https://github.com/coffeebeats/godot-infra/commit/76becd9d7d6a77b4bb03619d671492e9c5f93dfa))
* **ci:** use correct path to action `Dockerfile` and context ([#53](https://github.com/coffeebeats/godot-infra/issues/53)) ([fe6a128](https://github.com/coffeebeats/godot-infra/commit/fe6a128326703627a01de80b51e70cda73bfb333))
* **ci:** use correct path to action Dockerfile and context ([fe6a128](https://github.com/coffeebeats/godot-infra/commit/fe6a128326703627a01de80b51e70cda73bfb333))
* **ci:** use correct paths when running `lipo` and assembling an app bundle ([#76](https://github.com/coffeebeats/godot-infra/issues/76)) ([ffa6d95](https://github.com/coffeebeats/godot-infra/commit/ffa6d95cc730098968e44bf7fea8112d83802304))
* **ci:** use correct variable name for scons cache size ([db49a11](https://github.com/coffeebeats/godot-infra/commit/db49a1147a2c5f33c3f876a8f05c546a9f89f4b5))
* **ci:** use correct variable name for SCons cache size ([#75](https://github.com/coffeebeats/godot-infra/issues/75)) ([db49a11](https://github.com/coffeebeats/godot-infra/commit/db49a1147a2c5f33c3f876a8f05c546a9f89f4b5))
* **ci:** use PAT for authenticating addon update workflow ([#45](https://github.com/coffeebeats/godot-infra/issues/45)) ([8d84ff5](https://github.com/coffeebeats/godot-infra/commit/8d84ff51a03811b4fcd5351b0c5715fc106a3286))
* **example:** don't export '.import' files ([bd3ec4e](https://github.com/coffeebeats/godot-infra/commit/bd3ec4e08d6faf4572eaad6ccf9b5c87d0036bef))
* **example:** don't export `.import` files ([#37](https://github.com/coffeebeats/godot-infra/issues/37)) ([bd3ec4e](https://github.com/coffeebeats/godot-infra/commit/bd3ec4e08d6faf4572eaad6ccf9b5c87d0036bef))
* **example:** update `osxcross` root ([#39](https://github.com/coffeebeats/godot-infra/issues/39)) ([96bdcfc](https://github.com/coffeebeats/godot-infra/commit/96bdcfc8823e4e109fc212bc107645a221da8e5a))
* **example:** update `osxcross` root path ([96bdcfc](https://github.com/coffeebeats/godot-infra/commit/96bdcfc8823e4e109fc212bc107645a221da8e5a))
* **example:** update sample `export_presets.cfg` and remove unnecessary `imagemagick` install  ([#64](https://github.com/coffeebeats/godot-infra/issues/64)) ([5f4a26e](https://github.com/coffeebeats/godot-infra/commit/5f4a26e6e269237229cd71ff1c64f8115159dbaa))
