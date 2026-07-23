# Codemagic setup (one-time)

iOS simulator and production releases use root [`codemagic.yaml`](codemagic.yaml) workflows **`flutter_ios_simulator`** and **`ios_production`**. Flutter app path: **`scroller/client`**. Configure secrets in the **Codemagic UI** before the first automated deploy.

## App settings

1. Create or open the Codemagic app linked to this GitHub repo.
2. Under **Build**, set configuration source to **codemagic.yaml** (file at repository root).

## Variable group: `mobile_release`

Create a team or app variable group named **`mobile_release`** (secret where noted). The `ios_production` workflow references this group.

| Variable | Secret? | Purpose |
|----------|---------|---------|
| `APP_STORE_CONNECT_PRIVATE_KEY` | Yes | Contents of the `.p8` App Store Connect API key |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | No | Key ID from App Store Connect → Users and Access → Keys |
| `APP_STORE_CONNECT_ISSUER_ID` | No | Issuer ID from the same page |

## iOS code signing

Under **Team settings → codemagic.yaml settings → Code signing identities**:

1. **Certificates** — upload or fetch an **Apple Distribution** certificate.
2. **Provisioning profiles** — App Store profile for bundle ID **`com.biblescroller.bibleScroller`**.

The yaml uses automatic fetch by distribution type:

```yaml
ios_signing:
  distribution_type: app_store
  bundle_identifier: com.biblescroller.bibleScroller
```

If your uploaded profiles use custom reference names instead, switch to explicit `certificates` / `provisioning_profiles` references in `codemagic.yaml`.

## Per-build environment variables

Start `ios_production` manually (or via API) with:

| Variable | Example value |
|----------|-----------------|
| `BUILD_NAME` | `1.0.0` |
| `BUILD_NUMBER` | `1` |
| `RELEASE_NOTES` | `Smoke test — do not submit for review` |

For smoke tests, temporarily set `submit_to_app_store: false` in `codemagic.yaml`, or cancel the build after the artifact step.

## Local agent token (optional)

Add to repo-root `.env` (gitignored) if you use API triggers from an agent:

```
CODEMAGIC_TOKEN=your_codemagic_personal_api_token
```

## Discovered project values

| Item | Value |
|------|--------|
| Flutter app | `scroller/client` |
| Xcode workspace | `scroller/client/ios/Runner.xcworkspace` |
| Scheme | `Runner` |
| iOS bundle ID | `com.biblescroller.bibleScroller` |
| Android applicationId | `com.biblescroller.bible_scroller` (differs from iOS) |
| Default branch | `main` |
| Apple Development Team | *not set in Xcode project yet* |
