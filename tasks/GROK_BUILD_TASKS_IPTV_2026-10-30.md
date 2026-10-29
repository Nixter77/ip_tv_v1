# GROK_BUILD_TASKS — IPTV cut 2026-10-30 (binding)

**Decision needed:** ~~approve | reject OUT items | pick unlock order.~~

**Status: APPROVED** — nixter «делай сам» 2026-10-30 (Asia/Jerusalem). Eng via Grok Bot (no Cloud Agents). Do not wake CodeReviewer/Nightly.

**Product:** ip_tv_v1 (macOS SPM: library `IPTVPlayer` + executable `IPTVPlayerApp`).  
**SoT path:** `/Users/nikolay/gemini_projekts/ip_tv_v1/tasks/GROK_BUILD_TASKS_IPTV_2026-10-30.md`  
**Baseline HEAD (at cut draft):** `a834724` (on `main`; prior security: `477b44f` SSRF/CWE-918).  
**Outcome (user-visible):** after Space pause/play, HUD icon matches state; ♥ from HUD saves the real channel name; clicking the playing channel again retries playback; fullscreen targets the player window.

**Replaces:** none (first dated binding cut for this product).  
**Change control:** mid-PR scope adds require a new dated cut — no chat creep.

---

## Context (why this slice)

Primary IN chosen from candidates: **(2) remaining UX bugs** — not (1) `.app`, (3) SPM multi-target, (4) CI.

Repo facts (Mac): `main` clean @ `a834724`; prior SSRF `477b44f`. `tasks/todo.md` Review 2026-10-29: playlist byte-cap streaming, HTML reject, iptv-org schema, store split claimed shipped — **do not re-open A1/A2/security**. Live check: SecurityTests **23/23 PASS**. `improvement-plan.md` A3–A13 still lists UX/arch; this cut takes only A3/A4/A8.

auval N/A. Acceptance = full `swift test` + Mac smoke of `IPTVPlayerApp`.

---

## IN (this cut)

1. **S1 — HUD play/pause icon** (A3): icon driven by published player pause / time-control state, not raw `player.rate` that SwiftUI does not observe.
2. **S2 — Favorite from HUD** (A4): `toggleFavorite` takes / resolves a real `Channel` so name is never the placeholder «Канал» when the row is filtered out.
3. **S3 — Reselect = retry** (A8 part): selecting the already-selected playing channel restarts/retries the stream (stable `Channel.ID` path).
4. **S4 — Fullscreen window** (A8 part): fullscreen uses the window that hosts the player view (`WindowAccessor`), not `NSApp.keyWindow`.

Each stage = separate commit; message prefix `IPTV-2026-10-30-S{n}: …`. Keep Swift 6 settings; do not weaken `RemoteURLPolicy` / `SafeHTTPClient`.

---

## OUT (explicit)

- Further SSRF / CWE-918 hardening beyond current `main`
- `.app` bundle / icon / Info.plist / ATS / CI
- iptv-org schema expansion beyond what already decodes (logos/feeds already fixture-backed)
- Sidebar “only languages/countries with channels” (A5) — next cut
- AppViewModel split / multi-SPM targets (Phase 2)
- EPG, M3U sources, PiP, AirPlay, Settings scene (Phase 4+)
- Merge to main / force-push / new repo (human gates)
- Waking CodeReviewer or Nightly from this cut author
- Cloud Agents (not in plan) — Eng handoff via nixter / Grok Bot only

---

## Acceptance criteria

**AC-1** `swift test` green on this branch after all IN stages.  
Proof: `fixture id` = XCTest summary line (expect ≥78 tests, 0 failures; paste count).  
QA: pass if 0 failures; soft-pass forbidden.

**AC-2** `swift build --product IPTVPlayerApp` succeeds with no new warnings vs baseline.  
Proof: `SHA` of build log tail containing `BUILD` / product path.  
QA: pass if build ok and warning count does not rise.

**AC-3** Space toggles pause; HUD play/pause glyph flips within ~1s without channel change.  
Proof: `screenshot` of HUD paused vs playing.  
QA: pass if icons differ correctly in both states.

**AC-4** Favorite from HUD while search/filter hides the channel: persisted favorite shows real channel name (not «Канал»).  
Proof: `screenshot` of favorites (or library row) after ♥ from HUD under an active filter.  
QA: pass if name matches catalog channel name.

**AC-5** Click same playing channel again → visible retry (brief loading / stream restart), not a no-op.  
Proof: `screenshot` or short note + timestamp of status/loading UI after reselect.  
QA: pass if retry observed.

**AC-6** With a second window focused (or detached player), fullscreen from player controls still fullscreens the **player** window.  
Proof: `screenshot` before/after.  
QA: pass if player window enters fullscreen, not an unrelated key window.

**AC-7** No regression of RemoteURLPolicy public API / SecurityTests.  
Proof: `fixture id` = SecurityTests result in `swift test` output.  
QA: pass if SecurityTests all pass.

---

## Unlock order

1. AC-1 + AC-7 (tests / security) must PASS before claiming S1–S4 done.  
2. AC-2 before Mac smoke pack.  
3. AC-3 → AC-4 → AC-5 → AC-6 (UX proofs).  
4. Docs / polish only after AC-1…AC-6 PASS.

---

## Eng handoff (role: Eng = Grok Build; optional Gemini 3.8 / Antigravity)

```
Cut: GROK_BUILD_TASKS_IPTV_2026-10-30
Path: /Users/nikolay/gemini_projekts/ip_tv_v1/tasks/GROK_BUILD_TASKS_IPTV_2026-10-30.md
Date: 2026-10-30
Status: APPROVED — Eng may start (Grok Bot handoff; no Cloud Agent)

Do in unlock order: S1 → S2 → S3 → S4
AC ids: AC-1 … AC-7 (proof map in cut)
Baseline: a834724 on main — branch off; do not merge to main without nixter

Do not start a Cloud Agent (not in Cursor plan).
Do not wake CodeReviewer or Nightly unless nixter asks.
Do not push to a foreign/new repo; no force-push; ask before merge to main.
When stages green locally: report commit SHAs + which ACs you believe ready for QA.
```

---

## QA handoff (role: QA = QA bot)

```
Cut: GROK_BUILD_TASKS_IPTV_2026-10-30 only — rewrite checks to this cut; soft-pass forbidden.
Proof map: AC-1 fixture id | AC-2 SHA | AC-3..AC-6 screenshot | AC-7 fixture id
Commands: `swift test`; `swift build --product IPTVPlayerApp`; Mac smoke of IPTVPlayerApp
auval: N/A
Do not commit/push to main. Ask nixter before merge/main/force-push/new repo.
Pass/fail each AC; attach proofs. No reinterpretation of failing ACs.
```

---

## Owner gate

After APPROVED («делай сам»): Eng implements; QA runs pack; nixter merge gate.  
Cut APPROVED. Eng implements S1→S4; QA after AC proofs ready. Merge still nixter gate. PM bot does not push.
