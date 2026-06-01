# Pipeline Architecture

This document describes the CI/CD pipeline for `wings_deployment/`. It is a living document — steps and tooling will evolve as implementation progresses.

---

## Overview

The pipeline is split into four workflow files chained via `workflow_run`. Validate and Plan run in parallel per environment. Apply runs sequentially with approval gates.

```
push to main
     │
     ▼
bootstrap.yml         creates Azure infra + GitHub Environments (dev/qa/prod)
     │ workflow_run
     ▼
version.yml           PSR version bump → pyproject.toml + CHANGELOG.md + git tag
     │ workflow_run
     ▼
deploy.yml
  detect-changes      which envs + modules are affected?
     │
     ├── validate-modules  (if modules/** changed)
     ├── validate-dev  ────┐
     ├── validate-qa   ────┤ fmt + validate + tflint (parallel)
     └── validate-prod─────┘
     │
     ├── plan-dev  ────────┐
     ├── plan-qa   ────────┤ terraform plan, artifact saved (parallel)
     └── plan-prod─────────┘
     │
     ▼
apply-dev   (auto)
     ▼
apply-qa    (manual approval — GitHub Environment gate)
     ▼
apply-prod  (manual approval — GitHub Environment gate)
```

**On PRs:** only `validate.yml` runs — fmt + validate + tflint per affected env. No Azure calls.

---

## Environments

| Environment | Directory | Pipeline | Purpose |
|---|---|---|---|
| dev | `environments/dev/` | Fully automated | Development |
| qa | `environments/qa/` | Approval gate | Quality assurance |
| prod | `environments/prod/` | Approval gate | Production |
| sb | `environments/sb/` | **Excluded** | Local experimentation only |

### Sandbox (sb)

`environments/sb/` is never touched by CI. It exists for running `terraform plan` and `terraform apply` locally:

```bash
cd environments/sb
terraform init -backend-config=../../bootstrap/backend.hcl
terraform plan
terraform apply
```

---

## Path-Based Triggering

The `detect-changes` job determines which environments need to run based on what changed. Only affected environments are validated, planned, and applied.

| What changed | dev | qa | prod | sb |
|---|---|---|---|---|
| `environments/dev/**` only | ✅ | ⏭️ | ⏭️ | ⏭️ |
| `environments/qa/**` only | ⏭️ | ✅ | ⏭️ | ⏭️ |
| `environments/prod/**` only | ⏭️ | ⏭️ | ✅ | ⏭️ |
| `modules/**` only | ✅ | ✅ | ✅ | ⏭️ |
| `modules/**` + `environments/qa/**` | ✅ | ✅ | ✅ | ⏭️ |
| `environments/sb/**` | ⏭️ | ⏭️ | ⏭️ | ⏭️ |
| `bootstrap/**` or `.github/**` | ⏭️ | ⏭️ | ⏭️ | ⏭️ |

### Why modules trigger all envs

A change in `modules/` potentially affects every environment that calls that module. Even if a new module is added but not yet wired into any env, `terraform plan` will return "No changes" for all envs — safe and expected.

---

## Workflow Files

| File | Trigger | Purpose |
|---|---|---|
| `bootstrap.yml` | push to main | Azure infra + GitHub Environments |
| `version.yml` | bootstrap completes | PSR version bump + CHANGELOG |
| `deploy.yml` | version completes | detect → validate → plan → apply |
| `validate.yml` | pull_request | fmt + validate + tflint (no Azure) |

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

- Triggered by bootstrap completion
- Runs `python-semantic-release` — reads commit history since last tag
- If `feat:` or `fix:` commits found: bumps version, updates `CHANGELOG.md`, commits to main, creates git tag
- If only `chore:` commits: no bump, pipeline continues unchanged

### Validate

- Runs per env (parallel), only for affected envs
- Also runs `validate-modules` if `modules/**` changed (fmt + tflint — no `terraform validate` since modules need a root caller)
- Steps per env:
  1. `terraform fmt -check` — formatting check
  2. `terraform validate` — syntax and consistency (uses `-backend=false`, no Azure calls)
  3. `tflint` — deeper static analysis

### Plan

- Runs per env (parallel), only for affected envs
- Steps:
  1. `terraform init -backend-config=../../bootstrap/backend.hcl`
  2. `terraform plan -out=<env>.tfplan`
  3. Plan output saved as artifact for Apply to consume

### Apply

- Runs sequentially: dev → qa → prod
- Only runs for affected envs
- dev: auto-applies on merge to main
- qa: requires manual approval (GitHub Environment protection)
- prod: requires manual approval (GitHub Environment protection)
- Steps:
  1. Download plan artifact
  2. `terraform apply <env>.tfplan`

---

## Backend Configuration

All environments share the same Azure Storage backend. Each env uses its own state file key.

`bootstrap/backend.hcl` (written by bootstrap, committed to main):
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

## Versioning

`wings_deployment` uses `python-semantic-release` for versioning. The version tracks the maturity of the deployment infrastructure — not how many times environments have been deployed.

| Type of change | Commit prefix | Version bump |
|---|---|---|
| New module, new pipeline feature | `feat:` | minor |
| Bug fix in module or pipeline | `fix:` | patch |
| Deploying to an environment | `chore:` | none |
| Docs, formatting | `docs:`, `style:` | none |

**Rule:** changes outside `environments/` use `feat:` or `fix:`. Changes only inside `environments/` use `chore:`.

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
