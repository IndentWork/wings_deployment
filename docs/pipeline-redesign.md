# Pipeline Redesign — RFC

**Status:** Design phase. No implementation yet.
**Last updated:** 2026-06-03

This document captures the design discussion for separating the current `deploy.yml` into two independent pipelines: **infra** and **image**. It exists so future sessions can resume from where we left off without re-deriving the reasoning.

---

## Motivation

`deploy.yml` today does two unrelated jobs in one apply step:

1. **Infra deployment** — `terraform apply` to create/update Azure resources (Postgres, Key Vault, VNet, App Service plan, the App Service shell, role assignments).
2. **Image deployment** — `az webapp config container set` + slot swap to roll out a new Docker image to the App Service.

These have different triggers, rhythms, and failure modes:

| | Infra | Image |
|---|---|---|
| What changes | Azure resources | Docker image running on App Service |
| When it should run | Terraform code changed | `image_version` changed |
| Rhythm | Rare (weeks/months) | Frequent (daily/hourly) |
| Tool | `terraform apply` | `az webapp …` + slot swap |
| Failure rollback | Revert terraform commit | Swap slots back |

Coupling them means every push runs both, even when only one is relevant. This was visible in runs:

- `26859433630` — image swap path ran on prod and failed even though prod's `image_version` was unchanged.
- `26861225406` — same; prod failed at health check, qa succeeded, dev blocked on state lock.
- `26883046907` — same; dev + qa passed, prod failed at health check.

Two distinct bugs surfaced through this coupling:

1. **`mode=skip` detection is broken** — the sed regex `s|^DOCKER\|||` only strips `DOCKER`, leaving a stray `|` in the image string. So `current_image == intended_image` is always false, and every run goes into `mode=swap` even when there's nothing to deploy.
2. **Prod's staging slot is unhealthy** — returns 503 on `/` while dev and qa return 200 within seconds. Same code, same image. Root cause not yet known; likely missing role assignment or container-level startup failure specific to prod.

Splitting the pipelines wouldn't fix bug #2, but it would make bug #1 irrelevant — the image pipeline wouldn't run at all unless `image_version` actually changed.

---

## Principles

1. **Each pipeline does ONE thing.** Infra changes run infra. Image changes run image.
2. **Per-env independence.** Dev changes don't trigger qa or prod. Each env decides independently.
3. **Skip is the default.** If nothing relevant changed for an env, that env's pipeline doesn't run.
4. **Source of truth is git, not Azure.** Detect "what changed" from the commit diff, not from `az ... show` queries.
5. **Image and infra share data through Terraform outputs — one-way.** Image pipeline *reads* outputs (web_app_name, RG, image_version) but never *mutates* Terraform state.

---

## Design decisions

### Detection — chose **D2** (split `image_version` into its own file)

Three options were considered:

- **D1** — git-diff the `image_version` literal in `variables.tf`. Precise but messy bash.
- **D2** — move `image_version` into `environments/<env>/image.tfvars`, a one-line file. Path filter on `image.tfvars` → image runs; anything else in `environments/<env>/` → infra runs. **Chosen.**
- **D3** — move `image_version` out of `wings_deployment/` entirely into `wings/`. Cleanest separation but biggest restructure.

Why D2: smallest change to file layout, gives crisp path filters, keeps `image_version` discoverable inside the env folder where readers expect it.

### Structure — chose **Structure 1** (two top-level workflows + path filters)

Three options were considered:

- **Structure 1** — `infra.yml` + `image.yml`, each with `detect-changes` and per-env reusable sub-workflows. **Chosen.**
- **Structure 2** — eight per-env top-level workflows (`infra-dev.yml`, `image-dev.yml`, etc.). More UI clarity, more files.
- **Structure 3** — single dispatcher workflow calling per-env reusables. Most flexible, most code.

Why Structure 1: easiest path from where we are, two top-level workflow files instead of eight, reuses the existing reusable-workflow pattern (`_validate-env.yml`, `_plan-env.yml`, etc.).

### Image vs Infra ordering — **Sequential**

`Image` triggers on `workflow_run: Infra` completing successfully. Safer if infra adds something the new image needs (e.g. a new App Service env var). Can drop to parallel later if observed they never depend on each other.

### Tool split — **Terraform for infra, az CLI for image**

Already the de facto split today (the blue-green deploy uses `az`). Making it explicit by putting `az` calls in their own workflow.

**Gotcha to remember:** whatever attribute az manages, Terraform must `ignore_changes` on. Otherwise Terraform reverts on the next apply. Already done for `site_config[0].application_stack` per `app-service-rollout.md`.

### Image deployer state machine — preserve all 4 modes

The image pipeline must handle **two distinct scenarios** end-to-end, not just slot swaps:

1. **First deployment** — the env was just created by Terraform; the slots may have no image set yet.
2. **Subsequent deployments** — the slots already run *some* image; we want to swap in a newer one safely.

To do this cleanly the deployer needs four modes. These already exist in today's `_apply-env.yml` and must be preserved in the new `_image-env.yml`:

| Mode | Trigger condition | Action | Health check? | Swap? |
|---|---|---|---|---|
| `bootstrap` | Production slot has no image (`DOCKER_CUSTOM_IMAGE_NAME` is empty) | Set image directly on production | No (nothing to compare to) | No |
| `bootstrap-staging` | Production has an image but staging slot does not (e.g. slot resource just recreated by Terraform) | Set image on both slots directly | No | No |
| `skip` | Production already runs the intended image | Do nothing | No | No |
| `swap` | Production runs a different image than intended | Set staging → poll `/healthz/ready` → swap | Yes | Yes |

**Why each one matters in the new pipeline:**

- `bootstrap` covers the first-ever apply for a brand-new env.
- `bootstrap-staging` covers the case where Terraform recreates the slot resource (rare but happens — schema change, slot rename).
- `skip` becomes a belt-and-braces fallback. With the new path filter, the pipeline normally skips at the GitHub Actions level when `image.tfvars` didn't change. `skip` still earns its keep when someone manually sets an image via `az` and the next pipeline run finds nothing to do.
- `swap` is the normal day-to-day path: bumped `image.tfvars`, image pipeline runs, blue-green deploy with `/healthz/ready` polling.

**Bug to fix during port:** the current `mode=skip` detection never triggers because the sed regex `s|^DOCKER\|||` in GNU sed ERE mode interprets `\|` as alternation, not a literal pipe — so the `|` after `DOCKER` is left behind and the equality check always fails. Fix when porting to `_image-env.yml`:

```bash
# replace the broken stripper
current_image=$(echo "$current" | sed -E 's#^DOCKER\|##; s#^https?://##')
# or use a character class
current_image=$(echo "$current" | sed -E 's|^DOCKER[|]||; s|^https?://||')
```

**Health check change:** the `swap` mode's health check polls `/` today. Switch to `/healthz/ready` once `wings/` PR #6 is merged and a new image is deployed. `/healthz/ready` is precise — it answers "can this slot take traffic?" instead of "is the entire app fully functional?"

#### Scenario walkthrough — the exact commands per mode

Concrete az calls per scenario, useful when porting the logic to `_image-env.yml`.

**Scenario A — first-ever deployment of a brand-new env (`mode=bootstrap`)**

State before: Terraform just created the App Service and staging slot. Neither has an image. Production URL returns "container hasn't started."

```bash
az webapp config container set \
  --name app-iw-wings-dev \
  --resource-group rg-iw-wings-dev \
  --container-image-name acriwwings01.azurecr.io/wings:0.7.0
```

No health check, no swap. App Service pulls the image via the managed identity's AcrPull role and starts the container on the production slot.

State after: production runs the image, staging is still empty.

**Scenario B — populating staging the first time (`mode=bootstrap-staging`)**

State before: production runs an image; staging is empty (from scenario A, or because Terraform recreated the slot resource).

```bash
# set staging
az webapp config container set \
  --name app-iw-wings-dev --resource-group rg-iw-wings-dev \
  --slot staging \
  --container-image-name acriwwings01.azurecr.io/wings:0.7.0

# set production (same image)
az webapp config container set \
  --name app-iw-wings-dev --resource-group rg-iw-wings-dev \
  --container-image-name acriwwings01.azurecr.io/wings:0.7.0
```

No health check, no swap. Both slots now run the same image; blue-green is available for future deploys.

**Scenario C — normal new-version deployment (`mode=swap`, the daily case)**

State before: production runs 0.7.0, staging runs 0.7.0. PR bumps `environments/dev/image.tfvars` to `image_version = "0.7.1"`.

Step 1 — set the new image on staging only (production keeps serving 0.7.0):
```bash
az webapp config container set \
  --name app-iw-wings-dev --resource-group rg-iw-wings-dev \
  --slot staging \
  --container-image-name acriwwings01.azurecr.io/wings:0.7.1
```

Step 2 — health check the staging URL until ready:
```bash
for i in $(seq 1 30); do
  code=$(curl -sS --max-time 30 -o /dev/null -w "%{http_code}" \
    "https://app-iw-wings-dev-staging.azurewebsites.net/healthz/ready")
  [ "$code" = "200" ] && break
  sleep 10
done
```

If never 200 in 30 attempts (~5 minutes): fail the pipeline. Production is untouched — users still see 0.7.0 safely.

Step 3 — swap (~5 seconds, Azure-native, zero downtime):
```bash
az webapp deployment slot swap \
  --name app-iw-wings-dev --resource-group rg-iw-wings-dev \
  --slot staging --target-slot production
```

State after: production runs 0.7.1, staging now holds the old 0.7.0 (warm, ready for rollback).

**Scenario D — same version pushed (`mode=skip`)**

Pipeline-level: the path filter sees no change to `image.tfvars` → image pipeline doesn't start at all.

Belt-and-braces (if someone uses `workflow_dispatch` to force a run): `current_image == intended` → exit immediately, no az calls.

**Scenario E — rollback (manual, ~5 seconds)**

Not a pipeline mode — just an az command run by hand when a deploy goes bad:
```bash
az webapp deployment slot swap \
  --name app-iw-wings-dev --resource-group rg-iw-wings-dev \
  --slot staging --target-slot production
```

Swaps slots back. Production returns to the previous image. The broken image is now in the staging slot — left there for forensics.

This is the whole point of blue-green: rollback is a one-line operation requiring no code change, no PR, and no pipeline run.

---

## Proposed file layout

```
.github/workflows/
  bootstrap.yml         (unchanged)
  version.yml           (unchanged)
  infra.yml             (NEW — replaces deploy.yml's terraform half)
  image.yml             (NEW — replaces deploy.yml's az half)
  validate.yml          (unchanged — PR-time checks)

  _validate-env.yml     (unchanged — reusable, called by validate.yml + infra.yml)
  _plan-env.yml         (unchanged — reusable)
  _apply-env.yml        (SLIM DOWN — drop image-deploy steps)
  _image-env.yml        (NEW — reusable, set staging → health check → swap)

  destroy-envs.yml      (unchanged — scheduled cleanup)
  _destroy-env.yml      (unchanged)
  destroy-sandbox.yml   (unchanged)
```

`deploy.yml` is removed.

### What goes where

| File | Trigger | What it does |
|---|---|---|
| `infra.yml` | `workflow_run: Version` + `workflow_dispatch` | `detect-changes` for terraform files per env, then `validate → plan → apply` per affected env (terraform only, no image bits). |
| `image.yml` | `workflow_run: Infra` + `workflow_dispatch` | `detect-changes` for `image.tfvars` per env, then `_image-env.yml` per affected env (read tf outputs, set staging, health check, swap). |

### Per-env outcomes

For each env, four possible outcomes per push:

| What changed | Infra runs? | Image runs? |
|---|---|---|
| Only terraform files (e.g. `modules/`, env's `main.tf`, env's `variables.tf`) | ✅ | ⏭️ |
| Only `image.tfvars` (version bump) | ⏭️ | ✅ |
| Both | ✅ → ✅ (sequential) | |
| Neither | ⏭️ | ⏭️ |

### Detection rules

`detect-changes` in `infra.yml`:

```yaml
filters: |
  modules:
    - 'modules/**'
  dev:
    - 'environments/dev/**'
    - '!environments/dev/image.tfvars'
    - 'modules/**'
  qa:
    - 'environments/qa/**'
    - '!environments/qa/image.tfvars'
    - 'modules/**'
  prod:
    - 'environments/prod/**'
    - '!environments/prod/image.tfvars'
    - 'modules/**'
```

`detect-changes` in `image.yml`:

```yaml
filters: |
  dev:
    - 'environments/dev/image.tfvars'
  qa:
    - 'environments/qa/image.tfvars'
  prod:
    - 'environments/prod/image.tfvars'
```

---

## Prerequisites — must land before implementation

### 1. Health endpoints (`wings/`)

PR: https://github.com/IndentWork/wings/pull/6

Adds `/healthz` (liveness) and `/healthz/ready` (DB-ping readiness). The redesigned image pipeline switches the staging health check from `/` to `/healthz/ready`. Without this, even the perfect pipeline keeps failing because `/` is too broad a check (full middleware + template stack).

**Sequence:**
1. Merge `wings/` PR #6.
2. New image tag (say `0.7.1` or `0.8.0`) builds and pushes to ACR.
3. Bump `image_version` in `wings_deployment/environments/<env>/...` to the new tag.
4. Verify a clean baseline run on dev/qa.
5. Then start implementing the redesign.

### 2. Investigate prod staging slot failure

Even with everything else fixed, prod's staging slot has been returning 503 consistently while dev/qa work. Need to inspect via `az webapp log tail --slot staging --name app-iw-wings-prod --resource-group rg-iw-wings-prod` to see what's actually breaking. Candidate causes:

- Slot's managed identity missing AcrPull on ACR
- Slot's managed identity missing Key Vault `Get`/`List` access
- App startup failing on a prod-specific env var

Should be debugged separately, not as part of the pipeline redesign.

---

## Implementation plan (high-level)

Once prerequisites are in:

1. **Restructure `image_version`:**
   - Move `image_version` out of `environments/<env>/variables.tf` defaults.
   - Create `environments/<env>/image.tfvars` containing just `image_version = "..."`.
   - Update `terraform plan` / `apply` calls to use `-var-file=image.tfvars`.
   - Verify dev pipeline still works end-to-end with this layout (test against existing `deploy.yml`).

2. **Build `_image-env.yml` (reusable):**
   - Inputs: `environment`.
   - Steps: az login → terraform init + `terraform output -raw image_version/web_app_name/resource_group_name` → set staging slot image → poll `/healthz/ready` → swap.
   - Use a clean sed (e.g. delimiter `#`) to strip `DOCKER|` prefix, avoiding the ERE-alternation gotcha.

3. **Build `image.yml`:**
   - Trigger on `workflow_run: Infra` + `workflow_dispatch`.
   - `detect-changes` job filtering on `environments/<env>/image.tfvars`.
   - Per-env jobs calling `_image-env.yml`.

4. **Slim down `_apply-env.yml`:**
   - Remove all post-`terraform apply` steps (read outputs, detect mode, slot operations).
   - Leaves: init → download plan → apply.

5. **Build `infra.yml`:**
   - Trigger on `workflow_run: Version` + `workflow_dispatch`.
   - `detect-changes` with the `!image.tfvars` exclusion.
   - Per-env jobs calling `_validate-env.yml`, `_plan-env.yml`, `_apply-env.yml`.

6. **Delete `deploy.yml`.**

7. **Update `docs/pipeline-architecture.md`** to reflect the new structure.

Each step should be its own PR, mergeable independently, with the pipeline verifiable at each step.

---

## Open questions

- **Should `image_version` ultimately live in `wings/` instead?** (D3 from above.) Long-term it would be cleaner — the app would own its own image references and trigger its own deploys. Worth revisiting after Tier-1 work in `remaining-work.md` is done.
- **Promotion model.** Today version is bumped per env via separate PRs. Should there be tooling to auto-bump qa after a successful dev deploy, or stay manual?
- **Manual rollback flow.** With separate pipelines, rollback becomes "revert the `image.tfvars` change and push" or "manually swap slots back." Worth documenting.
- **What to do on the prod staging slot.** Independent from this redesign but blocks any prod deploy until resolved.

---

## Related artifacts

- `wings/` PR #6 — health endpoints (prerequisite).
- `wings_deployment/` PR #27 — `workflow_dispatch` on `deploy.yml` (already merged into the current pipeline; manual-trigger capability carries forward to `infra.yml` and `image.yml`).
- `wings_deployment/docs/pipeline-architecture.md` — current pipeline (will be updated post-implementation).
- `wings_deployment/docs/app-service-rollout.md` — original 4-phase rollout plan; the `ignore_changes` pattern for image-managed attributes is described there.
- `wings_deployment/docs/remaining-work.md` — Tier 1 app-side blockers (migrations, Whitenoise, HTTPS header) that affect what "healthy" means for a slot.
