# Pipeline Architecture

This document describes the CI/CD pipeline for `wings_deployment/`. It is a living document — steps and tooling will evolve as implementation progresses.

---

## Overview

The pipeline has four stages — **Bootstrap**, **Validate**, **Plan**, and **Apply** — running in sequence. Validate and Plan run in parallel per environment. Apply runs sequentially across environments with approval gates.

```
push to main
     │
     ▼
Bootstrap
     │
     ▼
detect-changes
     │
     ├── Validate dev ──┐
     ├── Validate qa  ──┤ (parallel, per env)
     └── Validate prod──┘
     │
     ├── Plan dev ──────┐
     ├── Plan qa  ──────┤ (parallel, per env)
     └── Plan prod──────┘
     │
     ▼
Apply dev   (auto)
     │
     ▼
Apply qa    (manual approval)
     │
     ▼
Apply prod  (manual approval)
```

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

## Stages

### Bootstrap

- Triggers on: push to main
- Runs: always (idempotent)
- Checks if `bootstrap/backend.hcl` exists — creates and commits it if not
- Reads `backend.hcl` and ensures Azure resources exist:
  - Resource group (`rg-wings-bootstrap`)
  - Storage account (`storagewings001`)
  - Blob container (`tfstate`)

### Validate

- Runs per env (parallel), only for affected envs
- Steps:
  1. `terraform fmt -check` — formatting check
  2. `terraform validate` — syntax and consistency check
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
resource_group_name  = "rg-wings-bootstrap"
storage_account_name = "storagewings001"
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
| Resource group | `rg-wings-dev` |
| App Service | `app-wings-dev` |
| Postgres | `psql-wings-dev` |
| Storage account | `storagewings001` (shared, no env suffix) |

Project name (`wings`) is a Terraform variable — change it in one place to rename across all resources.
