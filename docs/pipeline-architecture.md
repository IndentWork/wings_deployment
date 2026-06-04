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
| Trigger gate | Always runs (for all enabled envs) when Version completes or manually dispatched | Path filter on `environments/<env>/image.tfvars` — only the changed envs run |
| Typical rhythm | Idempotent — usually a no-op since terraform code rarely changes | Frequent — every app release |

### Why infra runs unconditionally

`terraform plan` + `apply` is idempotent. If no terraform code changed, plan finds no diff and apply is a fast no-op. If the env's infrastructure has been destroyed (e.g., by the `destroy-envs` cron), plan finds the gap and apply recreates it.

Gating infra on path filters would skip envs that need to be recreated after a destroy. Running it unconditionally is the simpler, self-healing choice.

### Why image is path-filtered

Image deployment is not idempotent in the same way — it sets the slot image, polls health, and swaps. We only want to do that when `image.tfvars` actually changed. A PR that doesn't bump `image_version` shouldn't restart slots or trigger health checks.

---

## Path-Based Triggering

Only `image.yml` uses path filters. `infra.yml` has no `detect-changes` job — it runs validate → plan → apply for all enabled envs every time it's triggered.

### `image.yml` filters

```yaml
dev:  ['environments/dev/image.tfvars']
qa:   ['environments/qa/image.tfvars']
prod: ['environments/prod/image.tfvars']
```

### Behavior matrix

| What changed | infra-dev | infra-qa | infra-prod | image-dev | image-qa | image-prod |
|---|---|---|---|---|---|---|
| `environments/dev/main.tf` | ✅ (no-op or applies the change) | ✅ (no-op) | ✅ (no-op) | ⏭️ | ⏭️ | ⏭️ |
| `environments/dev/image.tfvars` | ✅ (no-op) | ✅ (no-op) | ✅ (no-op) | ✅ | ⏭️ | ⏭️ |
| `modules/web-app/main.tf` | ✅ | ✅ | ✅ | ⏭️ | ⏭️ | ⏭️ |
| `environments/sb/**` | ✅ (no-op for dev/qa/prod) | ✅ (no-op) | ✅ (no-op) | ⏭️ | ⏭️ | ⏭️ |
| `bootstrap/**` or `.github/**` | ✅ (no-op) | ✅ (no-op) | ✅ (no-op) | ⏭️ | ⏭️ | ⏭️ |
| Nothing on env / module side (e.g. README) | ✅ (no-op) | ✅ (no-op) | ✅ (no-op) | ⏭️ | ⏭️ | ⏭️ |

"No-op" means terraform plan reports no changes and apply does nothing — fast and safe. The cost is one terraform init + plan per env per push.

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
| `_image-env.yml` | `image.yml` | init + read outputs + az login + `az webapp config container set` on production |
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

- Triggered by Version completion or manual dispatch
- `validate-modules` runs in parallel as a static quality check (fmt + tflint on `modules/`) — does **not** gate the per-env chain
- Per env (in parallel), unconditionally:
  1. `_validate-env.yml` — fmt + init `-backend=false` + validate + tflint
  2. `_plan-env.yml` — init + `terraform plan -var-file=image.tfvars -out=<env>.tfplan` + upload artifact
  3. `_apply-env.yml` — init + download plan + `terraform apply <env>.tfplan`
- The only env-level gate is `config.toml`'s `enabled` list, checked inside each reusable workflow. An env not in the list skips its validate/plan/apply steps cleanly.

### Image

- Triggered by Infra completion (or manual dispatch)
- `detect-changes` per env (only `image.tfvars`)
- Per affected env (in parallel):
  1. Check enabled flag in `config.toml`
  2. `terraform init` + read outputs (`image_version`, `web_app_name`, `resource_group_name`)
  3. `az login` via service principal
  4. `az webapp config container set --name <app> --resource-group <rg> --container-image-name acriwwings01.azurecr.io/wings:<version>`
  5. App Service automatically restarts the container with the new image.

No staging slot, no blue-green swap, no health-check loop. This matches the canonical Microsoft reference template ([Azure-Samples/azure-django-postgres-flexible-appservice](https://github.com/Azure-Samples/azure-django-postgres-flexible-appservice)) which also deploys to a single production web app.

Trade-off: ~30s of downtime per deploy while the container restarts. Acceptable for a learning project; slot swap can be re-introduced as a focused PR once the baseline is stable.

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
