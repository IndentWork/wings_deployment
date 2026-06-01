# CHANGELOG


## v0.6.0 (2026-06-01)

### Features

- Add web-app module and wire into dev environment
  ([#20](https://github.com/IndentWork/wings_deployment/pull/20),
  [`61ec64e`](https://github.com/IndentWork/wings_deployment/commit/61ec64e0f256ea86df0ce67511f985e562c2133d))


## v0.5.5 (2026-06-01)

### Refactoring

- Add iw org prefix to bootstrap and all module resource names
  ([#19](https://github.com/IndentWork/wings_deployment/pull/19),
  [`1f954da`](https://github.com/IndentWork/wings_deployment/commit/1f954dae003937d9802a19637169a6ea5a8bcdb7))


## v0.5.4 (2026-06-01)

### Bug Fixes

- Use azurerm provider key_vault features to handle soft-delete automatically
  ([#18](https://github.com/IndentWork/wings_deployment/pull/18),
  [`22de342`](https://github.com/IndentWork/wings_deployment/commit/22de342b0619b9520556a5d6741bfd5903702e10))


## v0.5.3 (2026-06-01)

### Bug Fixes

- Purge soft-deleted Key Vault before apply for non-prod environments
  ([#17](https://github.com/IndentWork/wings_deployment/pull/17),
  [`48a38d4`](https://github.com/IndentWork/wings_deployment/commit/48a38d4520f860891fe69733597bc4634b919b0c))


## v0.5.2 (2026-05-31)

### Bug Fixes

- Key Vault soft-delete + environment enable switch
  ([#16](https://github.com/IndentWork/wings_deployment/pull/16),
  [`b8613f0`](https://github.com/IndentWork/wings_deployment/commit/b8613f0a964e42c0cb81193002c4593ab1f6c3c4))

* fix: per-env Key Vault soft-delete, environment enable switch via config.toml, bring qa/prod to
  full module parity

* fix: terraform fmt on key-vault module


## v0.5.1 (2026-05-30)

### Bug Fixes

- Use per-environment concurrency groups instead of global terraform-ops
  ([#15](https://github.com/IndentWork/wings_deployment/pull/15),
  [`368f050`](https://github.com/IndentWork/wings_deployment/commit/368f0508f78ca4402e16fb794f01e2c1a0f6cf68))


## v0.5.0 (2026-05-30)

### Features

- Add postgres flexible server with private VNet access
  ([#14](https://github.com/IndentWork/wings_deployment/pull/14),
  [`3726328`](https://github.com/IndentWork/wings_deployment/commit/3726328fc7405f0d38e7c3e1213f25d3111c4dae))

* feat: add network, key-vault and postgres-flexible modules for dev, qa and sb

* fix: add missing required_version to sb environment


## v0.4.0 (2026-05-29)

### Chores

- Remove Co-Authored-By trailers from CHANGELOG and add CLAUDE.md guard
  ([#12](https://github.com/IndentWork/wings_deployment/pull/12),
  [`5f07ff5`](https://github.com/IndentWork/wings_deployment/commit/5f07ff504b341cdc2cb70c36dee42660b05d9345))

* chore: remove Co-Authored-By Claude trailers from CHANGELOG

PSR generates CHANGELOG from commit messages — the Co-Authored-By trailers were leaking into the
  changelog body on every entry.

* chore: add CLAUDE.md — instruct Claude not to add Co-Authored-By trailers

### Features

- Add app service plan module and wire into dev and sb
  ([#13](https://github.com/IndentWork/wings_deployment/pull/13),
  [`d1c7d64`](https://github.com/IndentWork/wings_deployment/commit/d1c7d649adb09b2d646038a0dc814e4fa0e4c954))

* feat: add app service plan module and wire into dev and sb

* fix: restore versions.tf in modules to satisfy tflint required_providers rule


## v0.3.0 (2026-05-29)

### Features

- Add destroy pipelines for envs and sandbox with shared concurrency
  ([#11](https://github.com/IndentWork/wings_deployment/pull/11),
  [`23b521c`](https://github.com/IndentWork/wings_deployment/commit/23b521cacfb782a9ee27face569aed2f2d64ac2f))

- _destroy-env.yml: reusable workflow running terraform destroy -auto-approve for a given
  environment - destroy-envs.yml: destroys dev, qa, prod in parallel; runs every 2 hours via
  schedule and on workflow_dispatch - destroy-sandbox.yml: destroys sb on workflow_dispatch only -
  deploy.yml: change concurrency group from deploy-main to terraform-ops

All terraform workflows now share the terraform-ops concurrency group with cancel-in-progress: false
  — any new run waits for the existing one to complete, preventing state lock conflicts.


## v0.2.0 (2026-05-29)

### Bug Fixes

- Add approval gates for qa/prod and plan stage on PR
  ([#4](https://github.com/IndentWork/wings_deployment/pull/4),
  [`c4b2577`](https://github.com/IndentWork/wings_deployment/commit/c4b2577383cf3543e3e76628ddfa5dd3584ae32c))

- bootstrap: set required reviewers on qa and prod GitHub Environments using REQUIRED_REVIEWER org
  variable; dev remains auto-deploy - validate: add plan-dev, plan-qa, plan-prod jobs after validate
  so PRs show a full terraform plan before merge (informational; deploy re-plans on main after
  merge)

Co-authored-by: Claude Sonnet 4.6 <noreply@anthropic.com>

- Add environments:write permission to bootstrap workflow
  ([#6](https://github.com/IndentWork/wings_deployment/pull/6),
  [`d71b4e1`](https://github.com/IndentWork/wings_deployment/commit/d71b4e11835c9fce1a212a28c944f69f05e605e4))

GITHUB_TOKEN needs environments:write to call the GitHub Environments API — without it every PUT
  /environments call returns 403.

Co-authored-by: Claude Sonnet 4.6 <noreply@anthropic.com>

- Use PAT for GitHub Environments API in bootstrap
  ([#7](https://github.com/IndentWork/wings_deployment/pull/7),
  [`73dca08`](https://github.com/IndentWork/wings_deployment/commit/73dca083d0a97e562c2f6029a2c5fc240d103dd8))

* fix: use PAT for GitHub Environments API in bootstrap

- Remove invalid environments:write permission (not a valid GITHUB_TOKEN scope — causes workflow to
  fail before any job starts) - Switch Ensure GitHub Environments step to GH_ADMIN_TOKEN (classic
  PAT with repo scope); GITHUB_TOKEN cannot call the Environments REST API

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

* chore: update tags variable description in resource-group module

---------

Co-authored-by: Claude Sonnet 4.6 <noreply@anthropic.com>

### Features

- Add managed_by=terraform tag to resource group
  ([#5](https://github.com/IndentWork/wings_deployment/pull/5),
  [`6463c88`](https://github.com/IndentWork/wings_deployment/commit/6463c889cfaac15ffaf8ab7619cb594cdbc38503))

Co-authored-by: Claude Sonnet 4.6 <noreply@anthropic.com>

### Refactoring

- Auto-apply all envs sequentially, drop approval gates
  ([#10](https://github.com/IndentWork/wings_deployment/pull/10),
  [`9b92aec`](https://github.com/IndentWork/wings_deployment/commit/9b92aec2f691dfd82503f22f3cbf6f88b8b80e5d))

* refactor: auto-apply all envs sequentially, drop approval gates

- _apply-env.yml: remove environment: input — apply jobs no longer pause for approval. The existing
  needs/if chain in deploy.yml already enforces sequential ordering: apply-dev -> apply-qa ->
  apply-prod, with failure in one stage blocking the next. - bootstrap.yml: drop Ensure GitHub
  Environments step — no longer needed now that we're not using GitHub Environments for approval.
  Bootstrap is back to pure Azure infra (RG + storage + container).

* feat: add owner=indentwork tag to resource group


## v0.1.0 (2026-05-29)

### Bug Fixes

- Add required_version to all environment main.tf files
  ([`5d63402`](https://github.com/IndentWork/wings_deployment/commit/5d6340269597881fd2efe9dd9d723deff0a34fdf))

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Add versions.tf to resource-group module — required_providers and required_version
  ([`4203ad2`](https://github.com/IndentWork/wings_deployment/commit/4203ad296075b921b1c4b078ec56d4cecb7d09a2))

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Trigger bootstrap on push to main only, remove workflow_dispatch
  ([`c4ba0f9`](https://github.com/IndentWork/wings_deployment/commit/c4ba0f97b6a1ed9fb179e789877fb4dc2cc7bd34))

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

### Chores

- Initial scaffold — directory structure, PSR config
  ([`a88cc0d`](https://github.com/IndentWork/wings_deployment/commit/a88cc0db50124eb652b1b6ad11f8be5d0144f01b))

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

### Features

- Add bootstrap workflow — create TF state storage and write backend.hcl
  ([`6965b39`](https://github.com/IndentWork/wings_deployment/commit/6965b391726c6ac0fd3de6cd7a793d5b5fe6d02e))

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Add pipeline architecture documentation
  ([`c00519f`](https://github.com/IndentWork/wings_deployment/commit/c00519f763a9aaf7414698ea2a0f20705e9f64b5))

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Add resource-group Terraform module with naming convention
  ([`ac0fad3`](https://github.com/IndentWork/wings_deployment/commit/ac0fad3a5d5914ef2231f35ad79f42e6808772df))

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Add sample backend.hcl — overwritten by bootstrap workflow on run
  ([`63f15ef`](https://github.com/IndentWork/wings_deployment/commit/63f15ef0963af5e9edb7009579d084b714450c27))

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Add validate and deploy pipelines with path-based env detection
  ([`aa61da0`](https://github.com/IndentWork/wings_deployment/commit/aa61da04f6a9da5b0897cfb2600b2fb15028688c))

- validate.yml: runs on PR, fmt/validate/tflint per affected env (parallel) - deploy.yml: triggered
  by bootstrap, version (PSR) → detect-changes → validate → plan (parallel) → apply dev (auto) → qa
  (approval) → prod (approval) - .tflint.hcl: azurerm ruleset config - sb excluded from all pipeline
  triggers - concurrency group prevents parallel deploy runs

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Extract reusable workflows to eliminate repetition
  ([`fa8b5d0`](https://github.com/IndentWork/wings_deployment/commit/fa8b5d04da9bd18cdd6e4569bdab0b692ed673a4))

- _validate-env.yml: reusable validate steps (fmt, init, validate, tflint) - _plan-env.yml: reusable
  plan steps (init, plan, upload artifact) - _apply-env.yml: reusable apply steps (init, download
  artifact, apply) - deploy.yml: now calls reusable workflows, steps defined in one place -
  validate.yml: same, calls _validate-env.yml per affected env

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Scaffold all environments and update resource-group module
  ([`ac62f5f`](https://github.com/IndentWork/wings_deployment/commit/ac62f5fbecc8f9422133b01892fe78611cd0df89))

- Add dev/qa/prod/sb environment configs (main.tf + variables.tf) - Update resource-group module
  naming to use hyphens: rg-wings-dev - Add sb env validation to resource-group module - Remove
  gitkeeps from environments and workflows dirs

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Split version into own workflow, add module validation, bootstrap creates GitHub Environments
  ([`cea2e56`](https://github.com/IndentWork/wings_deployment/commit/cea2e56edcfb13b6c7918969529ed15f37f2904b))

- bootstrap.yml: add GitHub Environments creation (dev/qa/prod) - version.yml: new workflow,
  triggered by bootstrap, runs PSR standalone - deploy.yml: triggered by version, remove version
  job, add validate-modules - validate.yml: add validate-modules job for PR checks - docs: update
  pipeline architecture to reflect 4-workflow chain

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

- Update bootstrap — read backend.hcl, provision resources in sequence
  ([`1ca1748`](https://github.com/IndentWork/wings_deployment/commit/1ca1748c9cb8ffd0de8059db9b8d7efb51370cf0))

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
