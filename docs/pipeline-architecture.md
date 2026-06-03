# Pipeline Architecture

This document describes the CI/CD pipeline for `wings_deployment/` as it stands today. It is a living document — update it when the pipeline changes.

The pipeline is split into **four independent workflows** chained via `workflow_run`. Infra (Terraform) and image (slot deploy) are deliberately separate so that bumping an image version doesn't trigger a Terraform plan, and vice versa.

---

## Overview

```
push to main
     │
     ▼
bootstrap.yml         creates Azure infra for Terraform state (storage account + container)
     │ workflow_run
     ▼
version.yml           PSR version bump → pyproject.toml + CHANGELOG.md + git tag
     │ workflow_run
     ▼
infra.yml             Terraform validate → plan → apply per env (only for envs whose
     │                 terraform files changed)
     │ workflow_run
     ▼
image.yml             Detect deploy mode → set slot image → health check → swap
                      (only for envs whose image.tfvars changed)
```

**On PRs:** only `validate.yml` runs — `terraform fmt + validate + tflint` per affected env. No Azure calls.

**Manual override:** `infra.yml` and `image.yml` both accept `workflow_dispatch`. On manual trigger, all enabled envs run regardless of path filters.

---

## Environments

| Environment | Directory | Pipeline | Purpose |
|---|---|---|---|
| dev | `environments/dev/` | Fully automated | Development |
| qa | `environments/qa/` | Fully automated (no approval gate) | Quality assurance |
| prod | `environments/prod/` | Fully automated (no approval gate) | Production |
| sb | `environments/sb/` | **Excluded from CI** | Local experimentation only |

### Sandbox (sb)

`environments/sb/` is never touched by CI. It exists for running `terraform plan` and `terraform apply` locally:

```bash
cd environments/sb
terraform init -backend-config=../../bootstrap/backend.hcl
terraform plan
terraform apply
```

---

## The infra / image split

The two pipelines triggered by a push to main do fundamentally different work:

| | `infra.yml` | `image.yml` |
|---|---|---|
| What it changes | Azure resources (RG, Postgres, VNet, KV, App Service shell) | Docker image running in the App Service slots |
| How it changes things | `terraform apply` | `az webapp config container set` + `az webapp deployment slot swap` |
| Triggered by | Any change under `environments/<env>/**` (except `image.tfvars`) or under `modules/**` | Any change to `environments/<env>/image.tfvars` |
| Typical rhythm | Rare — weeks/months | Frequent — every app release |

A PR that bumps `image.tfvars` and nothing else will run `image.yml` only. A PR that adds a module will run `infra.yml` only. A PR that does both will run both — `image.yml` chains after `infra.yml` via `workflow_run`.

---

## Path-Based Triggering

`detect-changes` jobs in `infra.yml` and `image.yml` decide which envs need to run.

### `infra.yml` filters

```yaml
modules:  ['modules/**']
dev:      ['environments/dev/**',  '!environments/dev/image.tfvars',  'modules/**']
qa:       ['environments/qa/**',   '!environments/qa/image.tfvars',   'modules/**']
prod:     ['environments/prod/**', '!environments/prod/image.tfvars', 'modules/**']
```

The `!image.tfvars` exclusion is what keeps image-version bumps out of `infra.yml`.

### `image.yml` filters

```yaml
dev:  ['environments/dev/image.tfvars']
qa:   ['environments/qa/image.tfvars']
prod: ['environments/prod/image.tfvars']
```

### Behavior matrix

| What changed | infra-dev | infra-qa | infra-prod | image-dev | image-qa | image-prod |
|---|---|---|---|---|---|---|
| `environments/dev/main.tf` | ✅ | ⏭️ | ⏭️ | ⏭️ | ⏭️ | ⏭️ |
| `environments/dev/image.tfvars` | ⏭️ | ⏭️ | ⏭️ | ✅ | ⏭️ | ⏭️ |
| `modules/web-app/main.tf` | ✅ | ✅ | ✅ | ⏭️ | ⏭️ | ⏭️ |
| `environments/sb/**` | ⏭️ | ⏭️ | ⏭️ | ⏭️ | ⏭️ | ⏭️ |
| `bootstrap/**` or `.github/**` | ⏭️ | ⏭️ | ⏭️ | ⏭️ | ⏭️ | ⏭️ |

### Why modules trigger all envs

A change in `modules/` potentially affects every environment that calls that module. Even if a new module is added but not yet wired into any env, `terraform plan` will return "No changes" for envs that don't use it — safe and expected.

---

## Workflow Files

### Top-level workflows

| File | Trigger | Purpose |
|---|---|---|
| `bootstrap.yml` | push to main | Azure infra for Terraform state (RG, storage, blob container) |
| `version.yml` | `workflow_run: Bootstrap` | PSR version bump + CHANGELOG |
| `infra.yml` | `workflow_run: Version` + `workflow_dispatch` | detect → validate → plan → apply (Terraform only) |
| `image.yml` | `workflow_run: Infra` + `workflow_dispatch` | detect → image deploy (az CLI, slot swap) |
| `validate.yml` | `pull_request` | fmt + validate + tflint (no Azure calls) |
| `destroy-envs.yml` | cron (every 2h) + `workflow_dispatch` | Destroy all envs (cleanup automation) |
| `destroy-sandbox.yml` | `workflow_dispatch` only | Destroy sandbox env on demand |

### Reusable workflows

| File | Called by | Purpose |
|---|---|---|
| `_validate-env.yml` | `validate.yml`, `infra.yml` | fmt + init + validate + tflint for one env |
| `_plan-env.yml` | `validate.yml`, `infra.yml` | init + plan (with `-var-file=image.tfvars`) + upload artifact |
| `_apply-env.yml` | `infra.yml` | init + download plan + apply (terraform only — no image bits) |
| `_image-env.yml` | `image.yml` | init + read outputs + az login + mode detection + slot operations |
| `_destroy-env.yml` | `destroy-envs.yml`, `destroy-sandbox.yml` | init + destroy (with `-var-file=image.tfvars`) |

---

## Stages

### Bootstrap

- Triggers on: push to main
- Runs: always (idempotent)
- Checks if `bootstrap/backend.hcl` exists — creates and commits it if not
- Reads `backend.hcl` and ensures Azure resources exist:
  - Resource group (`rg-iw-wings-bootstrap`)
  - Storage account (`storageiwwings001`)
  - Blob container (`tfstate`)

### Version

- Triggered by Bootstrap completion
- Runs `python-semantic-release` — reads commit history since last tag
- If `feat:` or `fix:` commits found: bumps version, updates `CHANGELOG.md`, commits to main, creates git tag
- If only `chore:` commits: no bump, pipeline continues unchanged

### Infra

- Triggered by Version completion (or manual dispatch)
- `detect-changes` per env (excluding `image.tfvars`)
- `validate-modules` if `modules/**` changed (fmt + tflint — no `terraform validate` since modules need a root caller)
- Per affected env (in parallel):
  1. `_validate-env.yml` — fmt + init `-backend=false` + validate + tflint
  2. `_plan-env.yml` — init + `terraform plan -var-file=image.tfvars -out=<env>.tfplan` + upload artifact
  3. `_apply-env.yml` — init + download plan + `terraform apply <env>.tfplan`

### Image

- Triggered by Infra completion (or manual dispatch)
- `detect-changes` per env (only `image.tfvars`)
- Per affected env (in parallel):
  1. Check enabled flag in `config.toml`
  2. `terraform init` + read outputs (`image_version`, `web_app_name`, `resource_group_name`)
  3. `az login` via service principal
  4. **Detect deploy mode** — query current images on production and staging slots, compare with intended image
  5. Execute mode-specific actions:
     - `bootstrap` (production slot empty) → set production image directly, no swap
     - `bootstrap-staging` (staging slot empty) → set both slots' images directly, no swap
     - `skip` (production already runs intended image) → no-op
     - `swap` (production runs different image) → set staging image → poll `https://<app>-staging.azurewebsites.net/healthz/ready` for HTTP 200 (up to 30 attempts × 10s) → `az webapp deployment slot swap` (~5s)

The mode detection is the safety net. The path filter already ensures `image.yml` only runs when `image.tfvars` changed — `mode=skip` only fires when someone has manually set the image via `az` outside the pipeline.

---

## Backend Configuration

All environments share the same Azure Storage backend. Each env uses its own state file key.

`bootstrap/backend.hcl` (written by Bootstrap, committed to main):
```hcl
resource_group_name  = "rg-iw-wings-bootstrap"
storage_account_name = "storageiwwings001"
container_name       = "tfstate"
```

Per-env `main.tf` declares only the key:
```hcl
backend "azurerm" {
  key = "dev.tfstate"   # qa.tfstate / prod.tfstate / sb.tfstate
}
```

Init command used in all pipeline stages:
```bash
terraform init -backend-config=../../bootstrap/backend.hcl
```

---

## image.tfvars

`image_version` is stored in `environments/<env>/image.tfvars` — a single-purpose file containing just one line:

```hcl
image_version = "0.7.0"
```

The `image_version` variable in `variables.tf` has no default, so `terraform plan` / `apply` / `destroy` must be invoked with `-var-file=image.tfvars` to provide it. CI pipelines do this automatically; for local runs you must pass the flag explicitly.

This separation is what allows `image.yml` to path-filter cleanly on `image.tfvars` while `infra.yml` excludes it via `!environments/<env>/image.tfvars`.

---

## Concurrency

Each per-env apply / image / destroy job uses a concurrency group named `terraform-ops-<env>`. This ensures only one of these jobs is in flight per env at a time, preventing state lock collisions:

- Two `infra-dev` runs from overlapping pushes serialize.
- An `image-dev` waits for any in-flight `apply-dev`.
- A scheduled `destroy-dev` waits for `apply-dev` / `image-dev` to finish.

`cancel-in-progress: false` — queued runs are preserved, not cancelled.

---

## Versioning

`wings_deployment` uses `python-semantic-release` for versioning. The version tracks the maturity of the deployment infrastructure — not how many times environments have been deployed.

| Type of change | Commit prefix | Version bump |
|---|---|---|
| New module, new pipeline feature | `feat:` | minor |
| Bug fix in module or pipeline | `fix:` | patch |
| Deploying to an environment (bumping `image.tfvars`) | `chore:` | none |
| Docs, formatting | `docs:`, `style:` | none |

**Rule:** changes outside `environments/` use `feat:` or `fix:`. Changes only inside `environments/` (including `image.tfvars` bumps) use `chore:`.

---

## Resource Naming Convention

```
<component>-<project>-<env>
```

| Resource | Example |
|---|---|
| Resource group | `rg-iw-wings-dev` |
| App Service | `app-iw-wings-dev` |
| Postgres | `psql-iw-wings-dev` |
| Storage account | `storageiwwings001` (shared, no env suffix) |

Project name (`wings`) is a Terraform variable — change it in one place to rename across all resources.
