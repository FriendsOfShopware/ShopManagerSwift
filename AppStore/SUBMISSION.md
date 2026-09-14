# App Store Connect submission guide

Everything needed to create the listing for **Shopware**
(`de.shyim.shopware`), a **Free**, **Business** app for **iOS, iPadOS, and macOS**.

The text metadata lives under `AppStore/metadata/` in the fastlane `deliver`
layout — you can paste it into App Store Connect by hand, or run
`fastlane deliver` later. Screenshots go under `AppStore/screenshots/`.

---

## 1. Create the app record (App Store Connect → Apps → +)

- **Platforms:** iOS + macOS (one record; add macOS under the same app).
- **Name:** Shopware  (`metadata/en-US/name.txt`)
- **Primary language:** English (U.S.)
- **Bundle ID:** de.shyim.shopware
- **SKU:** shopware-shop-manager
- **User access:** Full

## 2. App information

- **Subtitle:** `metadata/en-US/subtitle.txt`
- **Category:** Primary **Business**, Secondary **Productivity**
- **Content rights:** Does not use third-party content.
- **Age rating:** 4+ (no objectionable content). Answer all questionnaire items "None".

## 3. Pricing and availability

- **Price:** Free (Tier 0)
- **Availability:** All territories (adjust if you want to limit).

## 4. Version metadata (per platform)

- **Description:** `metadata/en-US/description.txt`
- **Keywords:** `metadata/en-US/keywords.txt`
- **Promotional text:** `metadata/en-US/promotional_text.txt`
- **What's New:** `metadata/en-US/release_notes.txt`
- **Support URL:** `metadata/support_url.txt`  ← update to a real page you control
- **Marketing URL:** `metadata/marketing_url.txt` (optional)
- **Copyright:** `metadata/copyright.txt`
- **Version:** `MARKETING_VERSION` is **0.2.1** for the app and widget.
  `CURRENT_PROJECT_VERSION` is **2** for local builds. The `beta` and `ci_beta`
  fastlane lanes query App Store Connect for the platform's latest uploaded build
  across all versions and choose a higher build number (at least 2). The archive
  override applies to both the app and widget without editing the checkout.

## 5. App Privacy (Data collection "nutrition label")

Answer: **"Data Not Collected."** The app has no developer backend, no analytics,
and no tracking. Rationale (keep for your records):

- Credentials + shop data are stored **only on device** (encrypted, Keychain) and
  sent **only** to the user's own Shopware store — not to the developer.
- The bundled Firebase Messaging component is used **solely** to obtain an APNs
  push token; configure it as **not** linked to the user and **not** used for
  tracking. If App Store Connect flags Firebase, declare "Device ID" as collected
  **only** for App Functionality (push delivery), not linked to identity, no tracking.
- Set **Privacy Policy URL** to `metadata/privacy_url.txt` (points at PRIVACY.md —
  host it somewhere public, e.g. the repo or a site you own).

## 6. Export compliance

- Uses encryption? **Yes**, but only standard HTTPS/TLS and Apple-provided crypto
  (Keychain, CryptoKit AES-GCM). Qualifies for the exemption.
- Add to the app's Info.plist to skip the per-submission prompt:
  `ITSAppUsesNonExemptEncryption = NO`.

## 7. App Review Information

- **Sign-in required:** Yes — provide a demo Shopware store + admin login in
  `metadata/review_information/notes.txt` (fill in the URL/username/password).
- **Notes:** already drafted in that file (how to connect and what to test).

## 8. Screenshots (required per platform)

Put PNG/JPG files in these folders (fastlane picks them up in filename order):

- `AppStore/screenshots/iPhone/`  — 6.9" (1290×2796) and/or 6.5" (1242×2688)
- `AppStore/screenshots/iPad/`    — 13" (2064×2752) or 12.9" (2048×2732)
- `AppStore/screenshots/macOS/`   — 2880×1800 or 2560×1600

Suggested shots (up to 10 each): Dashboard, Orders list, Order detail,
Reports, Products, Reviews. Capture on device/simulator or via Xcode
(Debug → View Debugging, or a simulator screenshot).

## 9. Icon

The 1024 marketing icon is generated from `shopware/AppIcon.icon` at build time;
App Store Connect reads it from the uploaded build (no separate upload needed for
recent Xcode).

## 10. Build → upload

### TestFlight

Run the **TestFlight** GitHub workflow on the intended commit, or push a matching
version tag such as `v0.2.1`. The tag triggers the workflow; `MARKETING_VERSION`
still controls the version inside the archive. The workflow runs full and minimum
compatibility checks, then builds and uploads both platforms (or the platform
chosen for a manual run). Release workflows queue to avoid allocating duplicate
build numbers. For local uploads, use `fastlane ios beta` or `fastlane mac beta`;
avoid running a local upload concurrently with CI for the same platform.

### Public App Store release

1. Set the intended version and a new build number (see step 4).
2. Archive: `xcodebuild -scheme shopware -configuration Release archive` (or
   Xcode → Product → Archive), then Distribute App → App Store Connect → Upload.
   Requires clean automatic signing (one Apple Development / Distribution cert).
3. In App Store Connect, attach the processed build to the version, then
   **Add for Review** → **Submit**.

---

## Automate with fastlane (configured)

fastlane is set up at the repo root (`fastlane/Appfile`, `fastlane/Fastfile`),
reading metadata from `AppStore/metadata` and screenshots from
`AppStore/screenshots`. Auth is interactive Apple ID login (prompts for password
+ 2FA on first run; session is cached).

Fastlane is already installed (Homebrew). Run lanes directly from the repo root:

```
# Push text + screenshots only, no binary (safe to iterate):
fastlane metadata

# iOS: build + upload to TestFlight / submit for review:
fastlane ios beta
fastlane ios release

# macOS: same for the Mac App Store:
fastlane mac beta
fastlane mac release
```

(A `Gemfile` is included if you prefer `bundle exec fastlane …` with a
project-local fastlane; that needs a newer Ruby/bundler than the system 2.6.)

## CI: GitHub Actions on Namespace macOS runners

`.github/workflows/testflight.yml` builds on a Namespace macOS 26 (Tahoe) runner
(`nscloud-macos-tahoe-latest-arm64-12x28`) and uploads to TestFlight via
`fastlane ios ci_beta` / `mac ci_beta`. Trigger: manual (`workflow_dispatch`,
pick platform) or pushing a `v*` tag.

### One-time setup

1. **Create the Namespace macOS runner** (or profile) so the `runs-on` label
   resolves. The workflow uses `nscloud-macos-tahoe-latest-arm64-12x28`; adjust
   the shape/label to whatever your Namespace account exposes.

2. **App Store Connect API key** — App Store Connect → Users and Access →
   Integrations → App Store Connect API → generate a key (Admin or App Manager).
   Add these GitHub repo secrets (Settings → Secrets and variables → Actions):
   - `ASC_KEY_ID`     — the key's Key ID
   - `ASC_ISSUER_ID`  — the Issuer ID (top of the Keys page)
   - `ASC_KEY_P8`     — the .p8 file contents, **base64-encoded**:
     `base64 -i AuthKey_XXXX.p8 | pbcopy`
   (The workflow sets `ASC_KEY_P8_BASE64=true`.)

3. **Signing** — the CI lanes build with automatic signing +
   `-allowProvisioningUpdates`; the API key has authority to create the App Store
   distribution certificate and provisioning profiles on first run. If your org
   prefers pinned certs, switch the lanes to fastlane `match` with a private
   certs repo instead.

### Run it

- Manually: GitHub → Actions → **TestFlight** → Run workflow → choose platform.
- Or: `git tag v1.0.0 && git push origin v1.0.0`.

The build lands in App Store Connect → TestFlight; from there attach it to the
1.0 App Store version and submit.

Notes:
- `release` builds via `build_app` / `build_mac_app`, which requires working
  code signing (a single, unambiguous signing cert — see the signing note above).
- Character limits are already within ASC bounds (name ≤30, subtitle ≤30,
  keywords ≤100, promo ≤170, description ≤4000).
- The URL files (`support_url`, `marketing_url`, `privacy_url`) live under
  `AppStore/metadata/en-US/` per deliver's layout.
