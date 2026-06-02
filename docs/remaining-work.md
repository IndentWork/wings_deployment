# Remaining Work — Path to "App Dev Only" Mode

The goal of this doc is to list everything between *here* and *"DevOps is done, I only touch app code now."*

Estimates assume working with AI assistance, one focused session per task. If you're learning a new piece (e.g. App Insights), add some buffer.

---

## Tier 1 — Blockers for any real feature work

These will bite you the moment you add a Django model, login flow, or admin page. Knock these out first.

### 1.1 — Run migrations on container start
**Why:** The Postgres DB exists but has no Django tables yet. Any DB query fails.
**Where:** `wings/` repo
**What:**
- Add an entrypoint script that runs `python manage.py migrate --noinput` before `gunicorn`
- Or add to the Dockerfile `CMD`
- Verify on dev that admin tables are created
**Estimate:** 30–60 min

### 1.2 — Serve static files via Whitenoise
**Why:** Django admin will load HTML but no CSS (looks broken). Static files (admin CSS, your own CSS/JS) won't be served by gunicorn alone.
**Where:** `wings/` repo
**What:**
- `uv add whitenoise`
- Add `WhiteNoiseMiddleware` to `MIDDLEWARE` (right after `SecurityMiddleware`)
- Set `STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"` in `settings_azure.py`
- Already have `collectstatic` in Dockerfile, no change needed
**Estimate:** 20–30 min

### 1.3 — HTTPS proxy header
**Why:** App Service terminates TLS at the front door and forwards plain HTTP to your container. Django doesn't know the original request was HTTPS, so `request.is_secure()` returns False and any `SECURE_SSL_REDIRECT` logic misbehaves.
**Where:** `wings/` repo, `settings_azure.py`
**What:**
- Add `SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")`
- Optionally `SECURE_SSL_REDIRECT = True` if you want to force HTTPS at Django layer
**Estimate:** 10–15 min

**Tier 1 total: ~1.5 hours**

---

## Tier 2 — Complete the original 4-phase rollout

### 2.1 — Phase 4: Deployment slot (blue-green)
**Why:** Today every deploy goes straight to production. A broken image = downtime. Blue-green = deploy to staging slot first, health-check, then swap. Instant rollback if something's wrong.
**Where:** `wings_deployment/` repo
**What:** Full plan already documented in `docs/app-service-rollout.md` under "Pending — Phase 4 (next session)".
- Add `azurerm_linux_web_app_slot` for staging
- `lifecycle { ignore_changes }` on image so CI/CD controls it
- 3 new pipeline steps: set staging image → health check → swap
**Estimate:** 2–3 hours including testing

### 2.2 — Local dev setup (`wings_local_dev/`)
**Why:** You currently can only test code by deploying to dev on Azure. A local replica with docker-compose + Postgres gives you a fast iteration loop without burning Azure credit.
**Where:** `wings_local_dev/` repo
**What:**
- `docker-compose.yml` with two services: `wings` (the Django container) + `db` (Postgres)
- `.env.example` showing required variables (DATABASE_URL, SECRET_KEY, WINGS_SETTINGS=local)
- `Makefile` with common commands: `make up`, `make down`, `make migrate`, `make shell`, `make logs`
- `settings_local.py` in `wings/wings/` (the local SIM card)
- README explaining how to start
**Estimate:** 2–3 hours

**Tier 2 total: ~5 hours**

---

## Tier 3 — Production readiness (nice-to-have, do over time)

These don't block shipping features. You can ship from dev to prod without them. But you'll want them eventually.

### 3.1 — Monitoring (Application Insights)
**Why:** Right now if the app errors, you find out by visiting the URL and seeing 500. With App Insights you get: error notifications, request traces, performance metrics, dependency graph (Django → Postgres calls), live metrics dashboard.
**Where:** `wings_deployment/` (infra) + `wings/` (instrumentation)
**What:**
- New Terraform module `modules/app-insights`
- Wire into web-app module — set `APPLICATIONINSIGHTS_CONNECTION_STRING` env var
- In `wings/`: add `opentelemetry-distro[azure-monitor-opentelemetry]` (or the older `applicationinsights` SDK)
- Initialize in `settings_azure.py` or `wsgi.py`
- Configure 1–2 basic alerts: error rate spike, response time degradation
**Estimate:** 3–4 hours

### 3.2 — Custom domain + managed SSL
**Why:** `https://app-iw-wings-dev.azurewebsites.net` is fine for dev. For prod you want `wings.indentwork.com` (or whatever).
**Where:** `wings_deployment/` repo
**What:**
- Buy a domain (if not already done) — outside this checklist
- Add `azurerm_app_service_custom_hostname_binding`
- Add `azurerm_app_service_managed_certificate` (free Azure-managed cert)
- Add CNAME records at your DNS provider (Cloudflare/Namecheap/etc.)
- Update `ALLOWED_HOSTS` to include the new domain
**Estimate:** 1–2 hours (once domain is in hand)

### 3.3 — Postgres backup retention + geo-redundancy
**Why:** Default backup retention is short. For prod you want more.
**Where:** `wings_deployment/modules/postgres-flexible/`
**What:**
- Add `backup_retention_days` variable (set 7 for dev, 30 for prod)
- Add `geo_redundant_backup_enabled` variable (false for dev, true for prod)
**Estimate:** 30 min

### 3.4 — Secret rotation
**Why:** Postgres admin password is a one-shot `random_password`. Long-term it should rotate.
**Where:** `wings_deployment/`
**What:** Honestly, this is a hard problem. Real rotation requires:
- New password generated
- Updated in Postgres (`ALTER USER ... PASSWORD ...`)
- Updated in Key Vault
- App Service restarted to pick up new connection string
**For now:** Document that "rotate = destroy + recreate the env". That's good enough for non-regulated apps.
**Estimate:** 30 min for the doc; days if you actually automate it

### 3.5 — Logging beyond stdout
**Why:** Container stdout works but is hard to search across instances/time. App Insights covers some of this (3.1). For full log aggregation you'd add Log Analytics Workspace.
**When:** Only when you actually feel the pain of grep'ing through `az webapp log tail` for the 10th time.
**Estimate:** 2–3 hours

**Tier 3 total: ~7–10 hours, spread over weeks as needs arise**

---

## Summary

| Tier | What | Total Effort |
|---|---|---|
| 1 | Migrations + Whitenoise + HTTPS header | ~1.5 hours |
| 2 | Phase 4 slot + Local dev setup | ~5 hours |
| 3 | Monitoring + Custom domain + Backups + Rotation doc | ~7–10 hours (over time) |

**To get to "app-dev-only mode":** Tier 1 + Tier 2 = **~6–7 hours of focused work**.

Tier 3 is the long tail — pick those up as the project grows. None of them block you from building features.

---

## After all of this

What "DevOps is done" actually means:

- Write a feature in `wings/` → local test in `wings_local_dev` → push → image built and pushed to ACR
- Open PR in `wings_deployment/` bumping `image_version` → review → merge
- Pipeline deploys to dev staging slot → health check → swap → live on dev
- (Optional) Promote to qa/prod by updating their `image_version` in another PR
- Monitoring catches errors before users do
- Rollback = swap slots back (one command, ~5 seconds)

That's the loop. From then on, every working session is `wings/` code.
