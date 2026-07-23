---
name: deploy
description: >-
  Plans and commits dirty work via commit-files, then builds the Flutter web
  bundle, Docker-pushes the ARM64 bscroller image, and rolls it out on the VM.
  Use when the user says /deploy, deploy, deploy to vm, ship to production, or
  build and deploy.
disable-model-invocation: true
---

# Deploy (commit-files + Docker VM)

Orchestrates **git commits** then **production deploy** for Bible Scroller
(`bscroller` on the navedu.uk VM). Never skip approval gates.

## Preconditions

- Work from the **git repository root**.
- Read and follow **commit-files** first: `~/.cursor/skills/commit-files/SKILL.md`
  (same secret-scan defaults / opt-out phrases).
- Deploy command details: [reference.md](reference.md) and
  [`scroller/deploy/DEPLOY.md`](../../../scroller/deploy/DEPLOY.md).
- **Never** commit TLS keys, SSH keys, `~/.env`, or API keys.
- **Never** `git push` or deploy without explicit user approval (see gates).

## Progress checklist

Copy and track:

```
Deploy:
- [ ] 1. Secret scan (unless opted out)
- [ ] 2. Commit plan (Phase A)
- [ ] 3. Commits executed (Phase B — after approval)
- [ ] 4. Push (only if user approved push)
- [ ] 5. Deploy plan written
- [ ] 6. Deploy executed (after approval)
- [ ] 7. Smoke tests
- [ ] 8. Cloudflare: purge Flutter static + verify edge HIT (§1b)
```

## Phase A — Plan only (default)

When the user invokes `/deploy` (or equivalent) **without** clear execute words:

1. Run **commit-files Phase A** (secret scan + `.cursor/commit-plan.md`).
2. Append a **`## Deploy`** section to `.cursor/commit-plan.md` (see template below).
   Do **not** create a second plan file.
3. Stop. Tell the user the plan is ready and which approval phrases unlock which steps.

### Deploy section template (append to commit-plan)

```markdown
## Deploy
**Target:** bscroller @ 192.9.142.147 (bscroller.navedu.uk)
**Steps:**
1. flutter build web --release --no-tree-shake-icons --dart-define=API_BASE_URL=
2. Sync build/web → scroller/server/static/web
3. docker buildx build --platform linux/arm64 -t movinin/apps:bscroller_backend --push ./scroller/server
4. ssh opc@192.9.142.147 → docker compose pull/up bscroller → alembic upgrade head
5. Smoke: /health, /reels?limit=1, /
6. Cloudflare purge Flutter static + verify wasm HIT (DEPLOY.md §1b; needs CLOUDFLARE_API_TOKEN in env — never paste token in chat)
**Fallback:** If local Docker Desktop unavailable, use VM build (§2b in DEPLOY.md).
**One-time:** Cache Rules + Browser Cache TTL — see DEPLOY.md §1b if wasm is DYNAMIC.
```

## Approval gates

| User says (examples) | Agent does |
|----------------------|------------|
| *(plan only / just `/deploy`)* | Phase A only |
| **build**, **go**, **commit it**, **execute the plan** | commit-files Phase B (+ cleanup); **stop before deploy** unless deploy words also present |
| **push** (after commits) | `git push` per commit-files |
| **deploy**, **ship**, **roll out**, **deploy to vm** | Deploy steps only (commits already done, or nothing to commit) |
| **build and deploy**, **commit and deploy**, **build then deploy** | Phase B commits, then deploy (**still** ask before push unless push was included) |
| **build, push, and deploy** | Commits → push → deploy |

If the working tree is clean, skip commit Phase B and go straight to the deploy plan / deploy execution based on approval.

## Phase B — Commits

Follow **commit-files Phase B** exactly (add/commit order, PowerShell `-m` messages, cleanup of `.cursor/commit-plan.md` only after **all** commits succeed).

**Exception for this skill:** If the user approved **deploy in the same message** as build, **keep** `.cursor/commit-plan.md` until deploy finishes (or rewrite a short `.cursor/deploy-status.md` with the Deploy section before deleting the commit plan). Prefer keeping the commit plan until smoke tests pass, then delete both `.cursor/commit-plan.md` and `.cursor/deploy-status.md` if created.

Push rules remain those of **commit-files** (never silent push).

## Phase C — Deploy execute

Only after clear deploy approval. Follow [reference.md](reference.md) in order:

1. **Web build** (CanvasKit default; do not use `--wasm` unless user asked).
2. **Sync** `scroller/client/build/web` → `scroller/server/static/web`.
3. **Image build + push** (`linux/arm64` → `movinin/apps:bscroller_backend`).
4. **VM roll-out** over SSH: `docker compose pull bscroller` (or skip if VM-built), `up -d`, `alembic upgrade head`.
5. **Smoke tests** from reference.md; report pass/fail URLs.
6. **Cloudflare edge (required after web static changes):** purge + verify per [reference.md](reference.md) §5 and [`DEPLOY.md` §1b](../../../scroller/deploy/DEPLOY.md).
   - Require `CLOUDFLARE_API_TOKEN` in the **local shell env** (never paste into chat). If unset after a web-bundle change → **fail the deploy** (do not report success).
   - Skip CDN only when the user explicitly opted out (`skip-cdn`, `no-cdn`, or `cdn:false`) **or** the web bundle was unchanged this deploy.
   - After purge, verify must pass (`wasm` follow-up `HIT`).

### Shell notes (Windows)

- PowerShell: chain with `;` not `&&`.
- Prefer explicit `working_directory` / `cd` to repo paths.
- SSH identity: use the key the user’s environment already uses for `opc@192.9.142.147` (often `prequests_private.key`); do not invent paths. If SSH fails, stop and ask.

### Failure handling

- Commit fails → stop; do not deploy; keep commit plan.
- Docker build/push fails → try documenting §2b VM build; ask before uploading tar.
- Smoke test fails → report logs (`docker logs bscroller`); do not claim success.
- Web bundle changed and `CLOUDFLARE_API_TOKEN` missing (without CDN opt-out) → fail deploy; tell user to set the token in the local shell and re-run purge/verify.

## Phase D — Done

Report:

- Commits created (hashes/subjects) or “clean tree”
- Push status (pushed / not pushed / no upstream)
- Deploy status (image tag, container up, smoke results)
- Live URL: `https://bscroller.navedu.uk/`

## Opt-outs

- **commit-files** secret-scan opt-out phrases still apply.
- **`deploy:false`**, **`skip-deploy`**, **`no-deploy`**: run commit-files only.
- **`commit:false`**, **`skip-commit`**, **`no-commit`**: skip git commits; deploy plan/execute only.
- **`skip-cdn`**, **`no-cdn`**, **`cdn:false`**: skip Cloudflare purge/verify after web deploy (report as skipped; do not claim CDN success).
