# CHANGELOG


## v0.15.0 (2026-06-04)

### Features

- Align with canonical Microsoft Azure Django reference pattern
  ([#32](https://github.com/IndentWork/wings_deployment/pull/32),
  [`ffa07ba`](https://github.com/IndentWork/wings_deployment/commit/ffa07ba5839d36804b604f43ff4bc465d8bec104))

* feat: align with canonical Microsoft Azure Django reference pattern

Drop the staging slot, the blue-green swap pipeline, and the 2-managed-identity setup. Align app
  settings and KV reference syntax with the official Microsoft reference template
  (Azure-Samples/azure-django-postgres-flexible-appservice).

Why now: the staging slot + slot swap was the source of nearly every deploy failure we have hit. The
  slot's managed identity got AcrPull right after creation and lost the RBAC propagation race
  against the container pull, returning ACRTokenRetrievalFailure. Health-check loops amplified each
  failure. The mode-detection script accumulated bugs. None of this complexity is present in
  Microsoft's reference template.

Changes in this commit follow the reference exactly:

- modules/web-app: remove azurerm_linux_web_app_slot.staging and the staging-only KV access policy
  and AcrPull role assignment. Remove sticky_settings (nothing to be sticky to without slots).

- modules/web-app app_settings: rename DB_HOST/DB_USER/DB_NAME/ DB_PASSWORD to
  POSTGRES_HOST/POSTGRES_USERNAME/POSTGRES_DATABASE/ POSTGRES_PASSWORD matching the reference; add
  POSTGRES_PORT and POSTGRES_SSL.

- modules/web-app KV references: switch from SecretUri=https://... to VaultName=...;SecretName=... —
  the form Microsoft uses. No URI construction needed.

- modules/web-app/variables.tf: replace key_vault_uri input with key_vault_name; modules/key-vault
  outputs vault_name accordingly.

- _image-env.yml: collapse from 177 lines to 90. No mode detection, no staging image set, no
  health-check loop, no swap. Single az webapp config container set call against the production web
  app. App Service restarts the container with the new image.

- environments/dev/image.tfvars: bump to 0.11.0 (the companion wings PR renamed env vars to
  POSTGRES_*).

- docs/pipeline-architecture.md: describe the new no-slot Image stage.

Trade-off: ~30s of downtime per deploy while the container restarts. Acceptable for a learning
  project at this stage. Slot swap can be re-introduced cleanly as a focused PR once the baseline
  works — with a single shared user-assigned identity created before any slot, so the RBAC race goes
  away.

* fix: remove web-app outputs that referenced the dropped staging slot

The previous commit removed the azurerm_linux_web_app_slot.staging resource but left two outputs
  (staging_hostname, staging_url) that still referenced it, causing terraform validate to fail. No
  environment consumes these outputs — safe to delete.


## v0.14.0 (2026-06-03)

### Features

- Pass DB credentials via Key Vault references
  ([#31](https://github.com/IndentWork/wings_deployment/pull/31),
  [`62a0bea`](https://github.com/IndentWork/wings_deployment/commit/62a0bea15af79d83da33815102d51c7a6cb1edeb))

* feat: pass DB credentials via Key Vault references

Replace DATABASE_URL app setting (which embedded the raw Postgres password in a URL, causing
  dj_database_url.ParseError on special chars) with four separate app settings:

- DB_HOST — plain Postgres FQDN - DB_USER — plain admin login - DB_PASSWORD — Key Vault reference
  (secret fetched at runtime by the slot's managed identity, raw value never in app settings) -
  DB_NAME — plain database name

Also switch SECRET_KEY to a Key Vault reference instead of injecting the raw value directly as an
  app setting.

Add key_vault_uri variable to web-app module — needed to build the
  @Microsoft.KeyVault(SecretUri=...) reference strings.

Remove postgres_admin_password from web-app module — no longer needed since the password is read
  from KV at runtime, not embedded by Terraform.

Bump dev image to 0.10.0 which reads the new DB_* env vars.

* style: terraform fmt fixes


## v0.13.0 (2026-06-03)

### Features

- Deploy wings 0.9.0 to dev ([#30](https://github.com/IndentWork/wings_deployment/pull/30),
  [`7882ab2`](https://github.com/IndentWork/wings_deployment/commit/7882ab2eb0cd6cdb518162ea689f4d98c45cb16f))

* chore: deploy wings 0.9.0 to dev

Bumps image_version to 0.9.0 which adds migrate --noinput on container startup, fixing the
  Application Error on fresh Azure Postgres.

* chore: dev-only config and stage infra.yml pipeline

- Restrict enabled envs to dev only while debugging app startup. - Stage infra.yml: validate-modules
  gates all per-env work, then validate/plan/apply chain per env mirrors validate.yml structure.


## v0.12.0 (2026-06-03)

### Documentation

- Add pipeline redesign RFC ([#28](https://github.com/IndentWork/wings_deployment/pull/28),
  [`9d681f4`](https://github.com/IndentWork/wings_deployment/commit/9d681f4776669dde72e5976db6357cbcd157aaf6))

Capture the design discussion for separating deploy.yml into two independent pipelines: infra
  (Terraform) and image (az CLI / slot swap).

Includes motivation backed by recent failed runs, the principles guiding the split, design decisions
  made (D2 + Structure 1 + sequential ordering), the 4-mode image deployer state machine with
  concrete az commands per scenario, prerequisites that must land first (the wings/ health
  endpoints, the prod staging slot investigation), and a step-by-step implementation plan.

No code changes yet — RFC only.

### Features

- Redesign pipeline — split deploy.yml into infra.yml + image.yml
  ([#29](https://github.com/IndentWork/wings_deployment/pull/29),
  [`75190d0`](https://github.com/IndentWork/wings_deployment/commit/75190d03a11865ee1c3f176571c452cff51eaa18))

* feat: split image_version into image.tfvars per env

Step 1 of the pipeline redesign (see docs/pipeline-redesign.md). Move the image_version variable
  from a default in variables.tf to a dedicated image.tfvars file per env, so the upcoming image.yml
  pipeline can path-filter on image.tfvars to detect image-version changes independently from infra
  changes.

- Add environments/{dev,qa,prod}/image.tfvars containing only image_version. - Remove the default
  value from each env's image_version variable declaration; the variable is now required and sourced
  from image.tfvars. - Update _plan-env.yml and _destroy-env.yml to pass -var-file=image.tfvars to
  terraform.

No behavior change — pipeline still deploys the same image_version.

sb is left unchanged for now; it will be removed in a separate change.

Local note: running terraform plan/destroy by hand in environments/ now requires
  -var-file=image.tfvars since the variable has no default.

* feat: split deploy.yml into infra.yml + image.yml

Complete the pipeline redesign described in docs/pipeline-redesign.md. Infrastructure deployment
  (terraform) and image deployment (slot swap) are now two independent workflows triggered by
  different file changes.

- Add infra.yml — top-level workflow replacing the terraform half of deploy.yml. Same validate →
  plan → apply chain per env in parallel, but path filters exclude image.tfvars so version bumps
  don't drag terraform along. workflow_dispatch forces all envs.

- Add image.yml — top-level workflow that runs only when an env's image.tfvars changes. Chains
  downstream of Infra via workflow_run. workflow_dispatch forces all envs.

- Add _image-env.yml reusable workflow holding the 4-mode deploy logic (bootstrap,
  bootstrap-staging, skip, swap) that previously lived in _apply-env.yml. Two fixes vs the original:
  - sed uses '#' as delimiter so the DOCKER prefix is now correctly stripped — the previous form was
  interpreted by GNU sed in ERE mode as alternation, leaving the pipe behind and breaking the
  mode=skip detection. - Health check polls /healthz/ready (introduced in wings 0.8.0) instead of
  the home page, so it asks 'can this slot take traffic?' instead of 'is the entire app fully
  functional?'.

- Slim _apply-env.yml to terraform-only; the image-deploy steps moved to _image-env.yml.

- Bump image.tfvars in all three envs from 0.7.0 to 0.8.0 so the new pipeline rolls out the wings
  image that includes the /healthz/ready endpoint required by the new health check.

- Delete deploy.yml — superseded by infra.yml + image.yml chained via workflow_run: Bootstrap →
  Version → Infra → Image.

- Rewrite docs/pipeline-architecture.md to describe the new structure, the infra/image split, and
  the updated path-filter behavior.

* refactor: simplify infra.yml gating to config.toml-only

Drop detect-changes from infra.yml. Terraform plan/apply is idempotent — running it unconditionally
  is a no-op when there are no infra changes, and recreates the infra when destroy-envs has wiped
  it. Path-filtering broke that self-healing.

Also drop the validate-modules dependency from the per-env validate chain. validate-modules is now
  an independent static-quality job that does not block per-env validate/plan/apply.

The only env-level gate is config.toml's enabled list, checked inside each reusable workflow. An env
  removed from the enabled list skips its steps cleanly without any change to infra.yml.

Update docs/pipeline-architecture.md to match.

* refactor: apply same simplification to validate.yml

validate.yml had the same detect-changes path filter as infra.yml, so PRs that only changed
  image.tfvars (or unrelated files) skipped validate-modules and plan-{env} entirely. That meant a
  PR could merge without any terraform plan validating it.

Drop detect-changes here too. validate-modules runs in parallel as a quality check; each env's
  validate → plan chain runs unconditionally. Mirrors the structure of infra.yml.

* refactor: stage validate.yml — modules first, then envs

Make validate-modules a gating step for validate.yml: PRs first lint the shared modules, then once
  that passes the three env-level validate jobs run in parallel, each feeding its own plan job.

This is fine for PR-time validation because we want module issues to short-circuit the whole
  pipeline before spending Azure plan calls. The post-merge infra.yml keeps validate-modules
  un-gated so a transient module issue can't block self-healing terraform applies.

* fix: removing qa


## v0.11.0 (2026-06-03)

### Features

- Allow deploy workflow to be triggered manually
  ([#27](https://github.com/IndentWork/wings_deployment/pull/27),
  [`cb851d1`](https://github.com/IndentWork/wings_deployment/commit/cb851d13d143b619b9b362b8e4e6cf1b694542df))

Add workflow_dispatch trigger to deploy.yml so the validate -> plan -> apply chain can be re-run
  manually without pushing a commit. The existing workflow_run trigger from Version is unchanged.

- Widen detect-changes if: condition to also pass on workflow_dispatch, since
  github.event.workflow_run is absent in that case. - Fall back run-name to 'manual by <actor>' when
  no upstream commit message is available.


## v0.10.0 (2026-06-03)

### Features

- Deploy wings 0.7.0 to all environments
  ([#26](https://github.com/IndentWork/wings_deployment/pull/26),
  [`2cc0258`](https://github.com/IndentWork/wings_deployment/commit/2cc02586d761cfc4971cc2198150e13c8682f63a))

* feat: deploy wings 0.7.0 to all environments

* feat: run apply-dev, apply-qa and apply-prod in parallel

* feat: add deploy-image.sh script for local image deployment

* feat: add auth-azure.sh to scripts and source it in deploy-image.sh

* fix: lock deploy-image.sh to sandbox only

* fix: strip DOCKER| prefix from container image when detecting deploy mode

Azure returns container images as 'DOCKER|<image>' but the sed only stripped 'https?://'. This made
  bootstrap-staging never trigger on fresh slots and caused fresh deploys to fall through to swap
  mode and fail at the health check while RBAC was still propagating for the brand-new managed
  identity.

Applied the same fix in scripts/deploy-image.sh.


## v0.9.0 (2026-06-03)

### Features

- Bring sb, qa and prod to dev parity
  ([#25](https://github.com/IndentWork/wings_deployment/pull/25),
  [`8aee773`](https://github.com/IndentWork/wings_deployment/commit/8aee773f8b44ea67282019ac086b5b04570c6b37))

* feat: bring sb, qa and prod to dev parity

- Add web_app module and ACR data source to sb, qa, prod - Add outputs.tf (image_version,
  web_app_name, resource_group_name) - Add image_version, acr_name, acr_resource_group_name
  variables - Add kv_soft_delete_retention_days and kv_purge_protection_enabled to qa and prod - Set
  prod kv_soft_delete_retention_days=90 and purge_protection_enabled=true

* fix: set prod kv soft delete and purge protection same as dev for testing

* feat: enable qa and prod environments in pipeline


## v0.8.0 (2026-06-02)

### Features

- Deploy wings 0.6.0 to dev ([#24](https://github.com/IndentWork/wings_deployment/pull/24),
  [`eae5b23`](https://github.com/IndentWork/wings_deployment/commit/eae5b238da9eecc7471ef399b1c5cc83f4fc5979))


## v0.7.1 (2026-06-02)

### Bug Fixes

- Correct dev image version and harden blue-green deploy
  ([#23](https://github.com/IndentWork/wings_deployment/pull/23),
  [`cdcaea3`](https://github.com/IndentWork/wings_deployment/commit/cdcaea33f67438e58a24c3d3bfb20df5dfda754b))

- Set image_version to 0.5.0 (0.6.1 does not exist in ACR) - Add bootstrap-staging mode: when
  staging slot has no image yet, set image on both slots directly and skip health check, avoiding
  RBAC propagation failures on first boot of a new slot - Add --max-time 30 to curl in health check
  so 504 responses do not block each attempt for several minutes


## v0.7.0 (2026-06-02)

### Features

- Add deployment slot with blue-green CI/CD
  ([#22](https://github.com/IndentWork/wings_deployment/pull/22),
  [`505585d`](https://github.com/IndentWork/wings_deployment/commit/505585d77ef08ad835df621c2d2446eece1d8e87))


## v0.6.1 (2026-06-02)

### Bug Fixes

- Enable container_registry_use_managed_identity so App Service can pull from ACR
  ([#21](https://github.com/IndentWork/wings_deployment/pull/21),
  [`e4fa38c`](https://github.com/IndentWork/wings_deployment/commit/e4fa38c9001256b3766eabf248406e5f666349fe))


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
