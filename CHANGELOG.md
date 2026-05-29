# CHANGELOG


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
