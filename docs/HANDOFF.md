# Notify for Chrome — Handoff

<!-- skeleton:
version: 1.1
kind: report
status: active
updated: 2026-11-13
summary: Stage-by-stage handoff for @nolit/dsh-notify at 0.0.1-rc.6 — the shipped Chrome-notification surface, the pending-restart state, and the two recorded follow-ups (host settings, stale prototype doc).
-->

> History lives in [CHANGELOG.md](../CHANGELOG.md). This file is the **forward** view.

## 1. State

| Item | Measured value |
| :--- | :--- |
| Package | `@nolit/dsh-notify@0.0.1-rc.6` |
| Last code commit | `d9d0d47` 2026-11-08 — settings card and peak chip aligned with DSH |
| Tests | `npm test` → **77/77 pass** (re-measured 2026-11-13) |
| Publishable | yes — tarball 39 files (re-measured 2026-11-13), prerelease needs `--tag` |
| Live state | modules loaded — `lib/client.src.js` mtime 11:30:26 is before the 11:53:42 service start; live *visual* check still outstanding |

## 2. Done

- `0.0.1-rc.4` fixed the dead peak chip (`ReferenceError: doc is not defined` on every render);
  rc.3 is superseded and is not a valid install target.
- Chrome/Web Notification first, silent in-app toast as fallback, deduped delivery.
- Seven native DSH settings switches, Korean/English parity, host typography tokens.

## 3. Stages

### S1 — record the 2026-11-08 alignment in CHANGELOG

`d9d0d47` changed `lib/client.js` + `lib/client.src.js` (26 insertions / 22 deletions) but
`CHANGELOG.md` was last written at `79ad144` (2026-11-07). Under RULES §6.1 a change is not
complete until the measured before/after is in the track CHANGELOG.

**Work item:** add a `0.0.1-rc.4` (or the owner-chosen) entry directly under the existing
`### 2026-11-07 — `0.0.1-rc.4` — the chip actually renders` section, describing the settings-card
and peak-chip alignment against the DSH plugin tab surface and naming the two files. The version was
**not** bumped for this change, so a new `rc` is the owner's call — the entry itself is not.

Reported, not fixed.

### S2 — live visual verification

The code is loaded (mtime precedes the service start), so this no longer needs a restart. It needs a
browser check of the settings card and the peak chip in the live profile. Do not restart the service
to force it.

### S3 — decide where notification preferences live

Preferences sit in browser `localStorage` (v2). The Host half is intentionally a no-op and exposes
no settings namespace. Moving them to a Host `Config` + `configForms` namespace adds a Host-side
schema dependency and a new required client service — **owner decision**.

### S4 — retire the stale Windows-prototype follow-up list

[docs/2026-10-20-final-status.md](2026-10-20-final-status.md) §8 still lists client browser audio,
AUMID branding, code signing, log rotation and autostart as candidates. The shipped plugin is
Chrome-only; confirm these are dead rather than pending before anyone starts one.

## 4. Verification

```bash
cd dsh-notify && npm test
```
