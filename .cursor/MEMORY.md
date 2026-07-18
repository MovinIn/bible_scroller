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

## Active context

### 2026-07-16 — Auth accounts + review fixes

- Implemented Phase 2 auth end-to-end under `scroller/` (server + Flutter client).
- Code-review remediation landed: squatting/Google merge, session restore via `/users/me`, rate limits, SMTP wiring, client error UX.
- App lives in `scroller/client`; API in `scroller/server`.
- Workspace root `bible_scroller` may not be a git repo — check `scroller/` if committing.

## Recent completions

- 2026-07-16: Google + email/password auth, 6-digit verify, login-gated likes/comments (TDD).
- 2026-07-16: Auth security/UX review fixes (linking, restore, JWT/SMTP/rate-limit, tests).

## Archive

- (empty)
