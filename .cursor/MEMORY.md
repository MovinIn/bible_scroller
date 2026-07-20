# Project memory

> Curated by /close. Keep ≤ 200 lines. Stale entries move to Archive.

## Standing decisions

- **Auth stack:** FastAPI JWTs (no Firebase). Google Sign-In + email/password.
- **Email verification:** 6-digit code (hashed at rest); register does not issue JWT until verified.
- **Browse freely:** Feed + comment reads are public; likes/comments require verified JWT.
- **Account linking:** Unverified squat can be overwritten by re-register or Google (password cleared). Verified password + Google email keeps both methods. Google requires `email_verified: true` claim.
- **Mailer:** SMTP when `SMTP_HOST` set; `ALLOW_CONSOLE_MAILER=true` for local/dev only (forbidden in production).
- **JWT:** `JWT_SECRET` ≥ 32 chars; production must not use default `dev-change-me`.
- **Client state:** Provider + ChangeNotifier (`AuthController`, `ReelsController`).
- **TDD:** Prefer outcome-named tests (`[outcome] when [condition]`) for non-trivial features.
- **Web cold start:** Slow load was OCI origin egress for CanvasKit `.wasm` (`CF-Cache-Status: DYNAMIC`), not the ~2 GB reel library. Keep CanvasKit for production until skwasm is validated.
- **Cloudflare cache:** Zone Cache Rules required for `/canvaskit/*` (and `/assets/*`, `/icons/*`) on `bscroller.navedu.uk` + `www`. Browser Cache TTL=0 is **zone-wide** for `navedu.uk`. Purge Flutter static after web deploys (31-day edge TTL).
- **CF deploy scripts:** Shared helpers in `cloudflare-cache-common.ps1` — normalize null rules, force JSON arrays (PS 5.1), parse 404 from messages, shared `Invoke-CfApi`. Verify warms with GET. Run `cloudflare-cache-common.tests.ps1` after script edits.

## Active context

### 2026-07-18 — Cloudflare cold-start + script review fixes

- Live apex cache OK (`HIT`); `www.bscroller.navedu.uk` has no DNS (www in scripts is forward-looking).
- Code-review fixes landed in deploy scripts (null rules, JSON arrays, 404 parse, GET warm, deduped API, DEPLOY §1b polish).
- **Uncommitted** on `main`: `DEPLOY.md`, five deploy scripts, `.cursor/` memory/session logs.
- Next: commit deploy tooling when ready; optional skwasm later; fresh token only if re-applying rules.

## Recent completions

- 2026-07-18: CDN script review fixes (Normalize-CfRulesetRules, ConvertTo-CfApiJsonBody, Get-CfHttpStatusCode, verify GET warm, Invoke-CfApi common).
- 2026-07-18: Diagnosed cold start; Cloudflare Cache Rules + Browser Cache TTL; deploy apply/verify/purge scripts + §1b.
- 2026-07-16: Google + email/password auth, 6-digit verify, login-gated likes/comments (TDD).
- 2026-07-16: Auth security/UX review fixes (linking, restore, JWT/SMTP/rate-limit, tests).

## Archive

- 2026-07-16 auth implementation notes — session log `2026-07-16-2127-auth-accounts.md`.
- 2026-07-18 initial cold-start session — `2026-07-18-1926-cloudflare-cold-start.md`.
