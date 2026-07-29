# App Store Connect — Dreft Pro Setup Checklist

Complete these steps **before** submitting Dreft **1.2.0 (build 3)**.

## Prerequisites

- [ ] **Paid Apps Agreement** signed (Agreements, Tax, and Banking)
- [ ] Banking and tax info complete
- [ ] App record exists for `com.aiflowhustle.dreft` (free v1 already approved)

## Subscription group

1. App Store Connect → **Apps** → **Dreft** → **Subscriptions**
2. Create group: **Dreft Pro**
3. Reference name: `Dreft Pro`
4. App name for subscription (localized): **Dreft Pro**

## Product 1 — Yearly (with trial)

| Field | Value |
|-------|-------|
| **Product ID** | `com.aiflowhustle.dreft.pro.yearly` |
| **Reference name** | Dreft Pro Yearly |
| **Duration** | 1 year |
| **Price** | $59.99 USD (Tier 60) |
| **Family Sharing** | On (matches `DreftStore.storekit`) |
| **Introductory offer** | Free trial — **3 days** |
| **Display name** | Dreft Pro Yearly |
| **Description** | Full access to Dreft on Mac and iPad. Create and edit notes, canvases, and vaults. |

## Product 2 — Monthly

| Field | Value |
|-------|-------|
| **Product ID** | `com.aiflowhustle.dreft.pro.monthly` |
| **Reference name** | Dreft Pro Monthly |
| **Duration** | 1 month |
| **Price** | $7.99 USD (Tier 8) |
| **Family Sharing** | On |
| **Introductory offer** | None ✅ (removed Jul 28, 2026 — verify yearly still has 3-day trial only) |
| **Display name** | Dreft Pro Monthly |
| **Description** | Full access to Dreft on Mac and iPad. Billed monthly. |

## Subscription group order

Drag products so **Yearly appears first** (recommended default in paywall).

## App metadata (version 1.2.0)

- [ ] **Privacy Policy URL:** https://lavish-birthday-3cc.notion.site/Dreft-Privacy-Policy-39e2796a245380869bb7f48509695d5e
- [ ] **Terms of Use (EULA):** https://lavish-birthday-3cc.notion.site/Dreft-Terms-of-Service-3ab2796a2453808d905fdf00abb30809
- [ ] Update **description** — see `docs/app-store-metadata.md`
- [ ] **What's New** — see `docs/app-store-metadata.md`
- [ ] **App Privacy** questionnaire: Data Not Collected (subscriptions processed by Apple)

## Review information

Paste from `docs/app-store-metadata.md` → **App Review Information** → **Notes**.

Provide a **sandbox Apple ID** tester account in the notes field.

Optional: attach a screenshot of the paywall showing Restore, Privacy, Terms, and pricing.

## Sandbox testing (before submit)

Use a **Sandbox Apple ID** (Users and Access → Sandbox → Testers):

1. Sign out of Media & Purchases on test device (Settings → Apple ID)
2. Run app from Xcode or TestFlight
3. Purchase with sandbox account when prompted

See `docs/sandbox-qa-checklist.md` for full matrix.

## Submit

1. Archive **1.2.0 (3)** in Xcode (Mac + universal)
2. Upload to App Store Connect
3. Select build on version **1.2.0**
4. Ensure subscriptions show **Ready to Submit** with the build
5. Submit for review

## Grandfathering note for reviewers

Users who installed Dreft **before version 1.2.0** keep full access automatically via `AppTransaction.originalAppVersion`. New installs require Dreft Pro to create or edit.
