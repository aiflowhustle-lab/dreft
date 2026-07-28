# Dreft 1.2.0 — Sandbox QA Checklist

Run on **physical Mac + iPad** with a **Sandbox Apple ID** before App Store submission.

Mark each: ✅ Pass · ❌ Fail · ⏭ Skipped

---

## P0 — Must pass

| # | Scenario | Steps | Expected | Result |
|---|----------|-------|----------|--------|
| 1 | Fresh install, locked browse | Delete app → install → complete onboarding → dismiss paywall (✕) | Seeded note + canvas open; read/pan works; no paywall spam | |
| 2 | Create blocked | Tap New note / Create canvas while locked | Paywall appears | |
| 3 | Export while locked | Export canvas PNG + note PDF | Works without paywall | |
| 4 | Yearly trial purchase | Select yearly → Start free trial → sandbox purchase | Full write access; paywall dismisses | |
| 5 | Write after trial | Create note, edit canvas | All mutations work | |
| 6 | Restore purchases | Delete app → reinstall → Restore Purchases | Pro access restored (same sandbox Apple ID) | |
| 7 | Grandfather upgrade | Install **old App Store build** (pre-1.2.0) → update to 1.2.0 | Full access; Vault manager shows Legacy | |
| 8 | Fresh 1.2.0 install | New sandbox Apple ID, never had v1 | Locked after onboarding; read OK | |
| 9 | Monthly plan | Purchase monthly (no trial) | CTA says "Subscribe"; full access | |
| 10 | Lapsed subscription | Subscribe → cancel in sandbox → advance time / wait for expiry | Read-only banner; export works; create blocked | |

---

## P1 — Should pass

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| 11 | Paywall disclosures | Restore, Privacy, Terms links work; auto-renew text visible | |
| 12 | Note reading mode | Locked user opens note | Reading view; edit button shows paywall | |
| 13 | Canvas undo when locked | Cmd+Z on canvas while locked | No mutation (silent or paywall on explicit write) | |
| 14 | Version restore when locked | Canvas → Version history → Restore | Paywall | |
| 15 | Bookmark add when locked | Add bookmark from sidebar | Paywall | |
| 16 | Vault create when locked | Manage vaults → Create vault | Paywall | |
| 17 | Open existing vault when locked | Manage vaults → Open folder | Works (read access) | |
| 18 | Offline subscribed | Enable airplane mode (<7 days since last verify) | Write still works (fail-open) | |
| 19 | Mac + iPad same Apple ID | Subscribe on Mac, open on iPad | Universal entitlement | |
| 20 | StoreKit local (Debug) | Run from Xcode with Dreft.storekit | Products load; prices show | |

---

## P2 — Nice to have

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| 21 | Family Sharing | Family member installs | Access per ASC config | |
| 22 | Ask to Buy / pending | Pending purchase flow | Graceful error message | |
| 23 | Ineligible for trial | Sandbox ID that used trial before | Yearly shows price without trial text | |

---

## Sign-off

| | Name | Date |
|---|------|------|
| Mac tested | | |
| iPad tested | | |
| Ready to submit | | |
