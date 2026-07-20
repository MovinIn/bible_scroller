# Session log — 2026-07-18 19:26

**Repo:** `c:\Users\Joseph\Documents\workspaces\flutter\bible_scroller`
**Branch:** main
**Trigger:** /close

## Summary

Investigated multi-minute loads on `bscroller.navedu.uk`: cold start downloads the Flutter CanvasKit shell (~8–10 MB), not the ~2 GB reel image library. Root cause was Cloudflare not edge-caching `.wasm` (`DYNAMIC`). Applied Cache Rules + Browser Cache TTL=0, verified HIT, then hardened scripts/docs from a code review (www hosts, purge helper, 404-only create, verify retries, zone-wide TTL warning).

## Accomplished

- Diagnosed cold-start payload and CF cache headers.
- Applied live Cloudflare Cache Rules for `/canvaskit/*`, `/assets/*`, `/icons/*`; set zone Browser Cache TTL to Respect Existing Headers.
- Verified wasm `MISS`→`HIT` and `main.dart.js` `no-cache, must-revalidate`.
- Added deploy scripts + §1b docs; implemented code-review fixes and helper unit tests.

## Decisions

- **Keep CanvasKit** for production (skwasm deferred until validated).
- **CDN/Cache Rules first** over renderer switch or nginx static rewrite.
- **Browser Cache TTL=0 is zone-wide** for `navedu.uk` — document + optional skip env; do not Cache Everything on `/`.
- **Purge after Flutter web deploys** because edge TTL override is 31 days on stable paths.

## Open tasks

- [ ] Re-run `apply-cloudflare-cache-rules.ps1` with a **new** token so `www` host rules from review fixes are live (priority: high)
- [ ] Commit uncommitted deploy docs/scripts when ready (priority: medium)
- [ ] Optional later: evaluate `flutter build web --wasm` for smaller shell (priority: low)

## Blockers

- Prior Cloudflare API token was pasted in chat — must stay revoked; need a new token to re-apply www rules.

## Files touched

- `scroller/deploy/DEPLOY.md` — §1b Cloudflare cache + purge + checklist
- `scroller/deploy/apply-cloudflare-cache-rules.ps1` — apply Cache Rules
- `scroller/deploy/verify-cloudflare-cache.ps1` — HIT / entry-cache checks
- `scroller/deploy/purge-cloudflare-flutter-static.ps1` — post-deploy purge
- `scroller/deploy/cloudflare-cache-common.ps1` — shared helpers
- `scroller/deploy/cloudflare-cache-common.tests.ps1` — helper assertions

## Git state

- **Before close:** 1 modified (`DEPLOY.md`), 5 untracked deploy scripts
- **Commits this session:** none
- **Handoff commit:** pending — user did not request commit (`/close` only)

## Memory updates

- `.cursor/MEMORY.md`: updated sections: Standing decisions (web/CF), Active context (2026-07-18), Recent completions, Archive note for auth
- `~/.cursor/MEMORY.md`: skipped

## Next session

1. Read `.cursor/MEMORY.md` and this log.
2. Create a fresh Cloudflare API token; re-run apply so www rules match the hardened script.
3. Optionally commit deploy tooling via commit-files.
