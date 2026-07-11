# Impulse Mobile App — Specification

**Audience:** a coding agent updating the existing Flutter app (`impulse_app`).
**Status:** the current app is an early prototype; this spec defines both what exists and everything it must additionally do. Where this spec and the current code disagree, **this spec wins** — but preserve working code where it already matches.
**Companion documents (authoritative for firmware behavior & wire formats):** `firmware_spec_v2.md`, `new_prox_engine_spec.md`, `impulse_overview.md` (product/marketing/voice). Read those for anything this doc summarizes.

---

## 0. Spec status, versioning & change log

This spec changes rapidly. Rules for maintaining this section:
- **Bump the version** (1.x → 1.x+1) on any normative change and add a change-log entry (date + bullets) at the same time.
- **Keep the parity table current** as app work lands; stamp the audit date. The table tracks *spec vs. code*, not aspirations.
- Changes that must move in **lockstep with firmware** (wire formats) are flagged here and in `firmware_spec_v2.md` §0.

### 0.1 Spec ↔ app parity

Code home: `impulse_app/lib`. **Last audited: 2026-07-11** (branch `app-spec-v1.2`; re-audit as work lands).

| Spec area | Status | Notes |
|---|---|---|
| Watch BLE connect + WiFi/settings/schedule/IP-table push (§3) | ✅ | The prototype baseline. Settings extended to the v2 6-byte payload (+`settle_window_min`). |
| `ScheduleEncoder` wire format (§7.2) | ✅ | v2 blob: emits the leading `0x02` version byte and per-event `donning_grace_s u16` (lockstep). Covered by `schedule_encoder_test`. |
| Anchor toggle (servo) (§8.2) | ✅ | Keep `AnchorToggleResult` handling. |
| `phoneAway` criteria + docking flow (§4.2, §8.6) | 🟡 | Criteria added (index 4), model/encoder/builder support it; the docking session UI (§8.6) is not built. |
| App modes / template registry (§2A) | 🟡 | Registry + 4 seed templates (expand/reparse, onboarder metadata), `AppMode` in state; the Normal/Advanced UI + Custom cards + detach UX are not built. |
| Goal-first onboarding + onboarder templates (§8.1) | 🟡 | Onboarder registry data (problem statements, quick-forms, required anchor roles) ready; the onboarding screens are not built. |
| Self-binding delay (§8.9) | 🟡 | Full canonical classification + gate + settle floor + pending queue implemented and tested (`SelfBindingPolicy`, `CommitmentPolicyService`); not yet wired into the commitment-edit UI. |
| Emergency passes (§8.10) | 🟡 | Interim drift ledger + rolling budget + allowance gating + audit trail implemented/tested; passes UI not built. Watch `…001B` spend path probed. |
| Pending Changes / Emergency Pass characteristics (§6.1 `…001A`/`…001B`) | 🟡 | Runtime probe + parsers/writers implemented in `watch_service`; pending-queue UI rendering pending. |
| Live status dashboard (§8.7), proximity/calibration (§8.5), time sync (§8.11), seen anchors (§8.12), notifications (§8.6) | 🟡 | Watch Status reparsed to spec §6.1 (u8 battery, `condition_met`, unreachable anchors); Time `…0019` write + probe done. Dashboard/calibration/notification UIs not built. |
| Debug-menu release gating (§2A.4) | 🟡 | `BuildConfig.debugWriteToolsEnabled` compile-time gate provided; no write tools exist in the debug screen yet to gate. |
| Integrity stores (drift) + reactive state (§2) | ✅ | `drift` pending-queue/pass-ledger/audit-trail (`IntegrityStore`, tested) + Provider `AppState`. |

Legend: ✅ implemented · 🟡 partial · ⚠️ diverges from spec · ❌ not started

### 0.2 Change log

**v1.2 — 2026-07-10**
- **Sunrise Lock unblocked:** firmware spec v0.6 §5.4.4 adds the window-start worn check and per-event **`donningGraceS`**; §8.8's parameter set is now final. Event model + blob gain `donningGraceS` (§4.1, §7.2 — same lockstep batch); §10 item 3 and §14 updated.
- Watch Status gains a **`condition_met`** byte (§6.1, §8.7) so the dashboard can show "actively alarming" vs. "in-window, compliant" (lockstep).
- Persistence hardened: **`drift` is mandatory** for the pending-changes queue, emergency-pass ledger, and audit trail (§2, §9, §13); `shared_preferences` remains for simple prefs/device records.

**v1.1 — 2026-07-10**
- §8.9: settle window now **floored at the last settled baseline** — free unsettled editing can never loosen below the last settled state (closes the tighten-to-reset loophole); promotion timing rephrased as "takes effect **no earlier than**."
- §2A.4 / §8.13: debug-menu **write-capable tools are compile-time excluded from release builds**.
- §8.10: emergency passes default **2 per rolling 7 days**; explicitly spendable on active/imminent windows (deliberate early-user decision); spending on an active window re-pushes the schedule; opt-in "pass lockdown" noted as roadmap.
- §7.3 / §8.4: **midnight anchor push removed** (a phone can't run at midnight); replaced by staleness-based foreground push; anchors persist + recompute locally (firmware §4.7).
- §8.1 rewritten: **goal-first onboarding** built on **onboarder-designated registry templates** (§2A.2), with 2–3-question quick-forms, role-driven anchor placement, drafts for unanswerable inputs, skippable and re-enterable.
- **Root-of-trust alignment** with firmware spec v0.5 §9: §8.9/§8.10 app policy defined as interim enforcement + permanent preview mirror; new watch characteristics **Pending Changes** (`…001A`) and **Emergency Pass** (`…001B`) added to §6.1; §7.1 handles END responses `0x03`/`0x04`; §7.2 gains the schedule **format version byte** (lockstep); the firmware diff gate is now §10 item 1.

- Readiness pass (same day): settle window bounded **30–240 min** (§8.9 item 4); criteria/target changes corrected to classify as **loosening** everywhere (§8.9 item 2, matching firmware §9.1); **UUID-stability rule** added (§8.9 item 3 — edits preserve event UUIDs or the diff gate misreads them); Settings payloads extended + Emergency Pass SET_ALLOWANCE added to §6.1/§6.2 (lockstep); iOS Local Network permission added (§9); §14 Sunrise Lock item upgraded from "verify" to a confirmed firmware gap with specifics.

**v1.0** — the spec as first committed; pre-changelog.

---

## 1. Product context (read `impulse_overview.md` for the full framing)

Impulse is a **habit-enforcement / self-binding** system for adults with ADHD (and anyone tired of breaking promises to themselves). Clear-headed "past you" designs the day in the app; the hardware holds present-you to it. Three components:

- **Watch** — wearable that holds the schedule, tracks location/WiFi/phone-proximity, and enforces via vibration/buzzer.
- **Anchors** — fixed ESP32 devices placed around the home (nightstand, desk, door, phone dock). They broadcast identity, beep on watch removal, optionally lock a strap, and serve as the phone dock for phone-distance commitments.
- **Mobile app (this project)** — the calm side: where you design commitments and hand the day to the hardware.

**Cardinal UX rule (self-binding):** you can bind yourself **harder immediately**, but **loosening/escaping must be planned in advance** — easing a commitment takes ~a day to take effect. Tightening edits apply now; loosening edits are delayed (§8.9). This asymmetry — instant to commit, slow to un-commit — is the product's core integrity guarantee, not a limitation.

**Voice:** sell the freedom on the other side of the friction, not the friction. Avoid the word "enforcement" in user-facing copy (use *commitment, follow-through, holds the line*). Never overclaim ("hard to beat on impulse," never "impossible to cheat"). Do **not** mention app-blocking or uninstall-detection (cut features). See `impulse_overview.md` §7–8.

---

## 2. Tech stack & architecture

- **Flutter** (keep it Flutter). Current deps: `flutter_blue_plus` (BLE), `shared_preferences` (local storage), `permission_handler`. Keep these; add as needed (see below).
- Required addition: **`drift`** for the integrity-critical stores — the pending-changes queue, emergency-pass ledger, and audit trail must be transactional, timestamped, and migration-safe (they are the app's trust machinery); `shared_preferences` remains fine for simple prefs and device records. Further additions: `flutter_local_notifications` (pre-session dock reminders, §8.6); `http` (anchor schedule push, §8.4); `multicast_dns` or platform mDNS for anchor IP discovery (§8.4); `network_info_plus` (LAN/SSID awareness). Justify any heavy addition beyond these.
- **Current file layout** (keep the shape, extend it):
  - `models/` — `automation_model.dart` (the Event/Commitment model), `bluetooth_device_model.dart`.
  - `services/` — `bluetooth_service.dart`, `watch_service.dart`, `anchor_service.dart`, `automation_service.dart`, `debug_log_service.dart`.
  - `screens/` — `devices_screen.dart`, `automations_screen.dart`, `settings_screen.dart`, `debug_screen.dart`.
  - `widgets/`, `utils/` (`ble_constants.dart`, `schedule_encoder.dart`), `theme/`.
- **State management:** the prototype is service-based with imperative calls. Introduce a clear reactive state layer (Provider/Riverpod/Bloc — agent's choice, but be consistent) so screens observe device connection state, watch status, and schedule changes rather than polling.

---

## 2A. App modes: Normal & Advanced — the template layer (how the app is structured)

The app has two modes, toggled in **Settings**. **Normal mode is the default.** This split is the central organizing idea of the app's UX and is worth understanding before building anything else.

**The key mental model:** *the firmware only ever deals in "advanced-mode" primitives.* Everything the watch enforces is one of the raw commitment types — `getAway`, `stayNear`, `getOnWifi`, `getOffWifi`, `phoneAway` — each a time-windowed block with a firmness profile and optional beep-anchors (§4.1). There is **no** "Sunrise Lock" or "Study Time" in the firmware.

- **Advanced mode** is the truthful view: the user sees and edits the raw commitment blocks exactly as the watch sees them, and gets the **debug menu**. This is the power-user surface and has the most parity with the hardware.
- **Normal mode** is a friendlier layer on top: named, guided **templates** (Sunrise Lock, Study Time, Gym Time, Phone-Free block, …) that most users interact with instead of raw blocks. A template is just an app-side abstraction that expands into one or more advanced-mode blocks and smooths their rough edges (sensible defaults, guided setup, friendly copy). Switching a template user to Advanced mode reveals that, e.g., **Sunrise Lock is really a `getAway` from the bedroom anchor with a beep configuration on the nightstand anchor** — nothing more.

Normal mode exists purely so the average user never has to reason about proximity primitives; it is a convenience/templating layer, not a separate feature set. Anything doable in Normal mode is doable (more verbosely) in Advanced.

### 2A.1 Block tagging (origin / template type)
Every commitment block carries **app-side-only** metadata (never sent to the firmware; the schedule wire format is unchanged) recording where it came from:

- `origin` / `templateType` — an enum: `manual` (hand-authored in Advanced mode) or a template kind (`sunriseLock`, `studyTime`, `gymTime`, `phoneFree`, …; extensible).
- `templateInstanceId` — nullable id grouping the block(s) that one template expansion produced (null for manual blocks). Supports a template that expands to **multiple** firmware blocks (design for 1‑to‑many even if current templates are 1‑to‑1).
- The friendly template parameters the user entered (`templateParams`, a small map) so Normal mode can re-render and edit the template and regenerate its block(s).

This lets Advanced mode label each block honestly ("made by Sunrise Lock" vs. "manual"), and lets Normal mode group a template's blocks into one friendly card. Persist this metadata locally alongside the commitment; it is orthogonal to the firmware schedule.

### 2A.2 Templates & the template registry (Normal mode)
A **template** is a parameterized generator: friendly inputs → one or more tagged advanced blocks. Each template defines its params schema, defaults, friendly copy, and an `expand(params) → [blocks]` function.

**Build templates as a registry, not hardcoded into the UI.** Define a `TemplateRegistry` where each template is a self-contained entry (a class implementing a common interface: id, display metadata, params schema, `expand()`, and re-parse-from-blocks for editing). The Normal-mode UI is **generated from the registry** — the template gallery, the per-template builder form, and expansion all read from registry entries, so adding a template is an isolated addition, not a UI rewrite. This is deliberately forward-looking: eventually templates could be **community-authored libraries** loaded into the registry.
- **Seeding:** on first run (no saved registry), seed the registry with the hardcoded default templates below. A user's registry (and any future imported templates) persists locally and is loaded on subsequent runs.
- **Onboarder designation:** a registry entry may carry an optional `onboarder` block that surfaces the template in the onboarding flow (§8.1). It contains: a **problem statement** in the user's voice ("I can't get out of bed," "my evenings disappear into my phone"), a hero icon, a **quick-form** — a reduced params schema of **at most 2–3 questions** with everything else defaulted (if a template can't be reduced to 2–3 questions, it isn't an onboarder), and its **required anchor roles** (e.g. Sunrise Lock: bedroom + nightstand) so onboarding can drive hardware placement from the chosen goal. The full params schema still governs later editing. **v1 onboarders: Sunrise Lock, Phone-Free evening, Gym Time, Study Time.**

**Default (v1 seed) templates and their primitive mappings:**
- **Sunrise Lock** → a `getAway` from the **bedroom anchor** over the wake window, with the beep configuration pointed at the **nightstand anchor** (`beepAnchors` + `anchorProfile`) and the grace duration mapped to **`donningGraceS`**. Params: wake time, grace duration after the watch is put on (0–1800 s), escalation firmness, bedroom anchor, nightstand anchor. (Mechanics fully spec'd in `firmware_spec_v2.md` §5.4.4: window-start unworn beeping + donning grace.)
- **Study Time** → `stayNear(<desk anchor>)` over a window, optionally combined with a Phone-Free block.
- **Gym Time** → `getOnWifi(<gym SSID>)` over a window (per `impulse_overview.md`'s example).
- **Phone-Free** → `phoneAway(<docking anchor>)` (the Mode B docking flow, §8.6).

Templates that combine multiple primitives produce multiple blocks sharing one `templateInstanceId` (design for 1-to-many even though most v1 templates are 1-to-1).

### 2A.3 Mode & template behaviors (decided)
- **Editing a template-produced block in Advanced mode → detach to manual.** The block flips `origin`→`manual` and clears `templateInstanceId`, so the Normal-mode template card no longer claims a block the user hand-modified (the card then reflects only its remaining owned blocks, or becomes empty). Surface this ("this block is now custom") when it happens.
- **Manual blocks in Normal mode → show as generic "Custom" cards** (read-only summary with an "edit in Advanced" affordance), so a Normal-mode user still sees everything that's active. Do not hide them.
- **Mode toggle** is a user preference in Settings (default Normal), not per-block. Switching modes never changes what the watch enforces — a manual block authored in Advanced keeps enforcing when the user returns to Normal; it just renders differently.
- Show a light confirmation the first time a user enters Advanced mode ("this shows the raw building blocks — more power, more rope").
- All commitment edits — whether authored directly in Advanced or generated by a Normal template's `expand()` — run through the block-level self-binding delay (§8.9, item 3).

### 2A.4 Debug menu (Advanced mode only)
Fold/upgrade the existing `debug_screen` into an Advanced-only debug menu: raw **Watch Status** packets/decoded fields, live **Prox Score** and **Dock Status** meters, raw BLE log (`debug_log_service`), manual characteristic read/write, force schedule re-push, fingerprint-blob upload stub (§8.5), and any other live device telemetry. This is where "the raw packets from the watch and any other relevant information" live.

**Release-build gating (integrity requirement):** the debug menu must never be an in-the-moment escape hatch from a commitment. All **write-capable** tools — manual characteristic write, force schedule re-push, fingerprint upload, and any time/clock write — are **compile-time excluded from release builds** (dev/debug build flavors only, e.g. gated behind a `--dart-define` / build flavor, not a runtime toggle). Read-only telemetry (decoded Watch Status, Prox Score, Dock Status, BLE log) may ship in release Advanced mode. Without this gate, "write an empty schedule" or "jump the watch clock past the window" is a one-tap bypass of §8.9.

---

## 3. Current capabilities (baseline) vs. target

**Already implemented (verify against firmware, keep working parts):**
- Connect to the watch; push WiFi credentials, settings, schedule (BLE transfer protocol), and the anchor IP table (`watch_service.dart`).
- Anchor toggle (servo lock/unlock) via `anchor_service.dart`.
- `ScheduleEncoder` producing the binary schedule blob + CRC32 — **matches the firmware wire format**; keep it, but see enum gap below.
- Automation (Event) model with `toJson`/`fromJson`, recurrence, `appearsOnDate`.

**Known gaps to close (detailed in §8):**
1. `Criteria` enum is missing **`phoneAway`** (value 4). Add it everywhere (model, UI, encoder just needs the enum value since it serializes `.index`).
2. No **phone-distance / docking** support (Mode B): no Dock Register write, no persistent phone↔anchor link, no pre-session dock flow, no docking monitor.
3. No **proximity / fingerprint** management: no fingerprint upload, no "walk-around" calibration, no live proximity-score observation.
4. No **live status dashboard** (Watch Status characteristic parsing: activity state, worn, battery, unreachable-anchor notifications).
5. No **anchor discovery/naming** from Seen Anchors, no anchor WiFi/settings/identify setup surfaced, no anchor schedule push over WiFi/HTTP, no anchor IP discovery (mDNS).
6. No **time sync** to the watch (firmware-dependency; see §8.11 & §10).
7. No **self-binding delay** enforcement on schedule edits (§8.9).
8. No **emergency pass** system (§8.10).
9. No **Sunrise Lock** first-class experience (§8.8).
10. Anchor GATT UUIDs for proximity/fingerprint/dock are absent from `ble_constants.dart`.

---

## 4. Core concepts & data model

### 4.1 Commitment (the `Automation`/Event model)
The app's `Automation` is the firmware `Event` (see `firmware_spec_v2.md` §3.2). Fields: `id` (UUIDv4), `referenceDate` (UTC), `startTime`/`endTime` (local minutes-since-midnight; must not span midnight; `end > start`), `recurrenceType` (once/daily/weekly/monthly), `dayOfWeek` (1–7 if weekly), `dayOfMonth` (1–31 if monthly), `criteria`, `profile` (EnforcementProfile), `negate`, `donningGraceS` (uint16 seconds of post-donning enforcement grace, 0 = none; firmware §5.4.4 — Sunrise Lock's grace param), `anchorId?`, `wifiSSID?`, `beepAnchors[]`, `anchorProfile?`.

**Validation (enforce in the app before transmit; firmware asserts but won't correct):**
- weekly ⇒ `dayOfWeek` 1–7; monthly ⇒ `dayOfMonth` 1–31; once/daily ⇒ both 0/null.
- Exactly one of `anchorId` / `wifiSSID` non-null **except** `negate==true` (both may be null). For `phoneAway`, `anchorId` = the **docking anchor** (required).
- `beepAnchors` non-empty ⇒ `anchorProfile` required.
- `donningGraceS` clamped to 0–1800 in the UI (the firmware asserts but won't correct).
- `negate==true` one-time event with a UUID matching a recurring event cancels it for that one day.

### 4.2 Criteria (add `phoneAway`)
```
enum Criteria { getAway, stayNear, getOffWifi, getOnWifi, phoneAway }  // indices 0..4
```
- `getAway`/`stayNear` — be away from / near an anchor.
- `getOffWifi`/`getOnWifi` — off/on a WiFi SSID.
- **`phoneAway`** (new, Mode B) — the user's phone is docked at `anchorId`; the user must stay away from it. UI copy: "Phone away" / "Phone-free block." Requires the docking flow (§8.6).

### 4.3 EnforcementProfile / AnchorEnforcementProfile — unchanged (see current model; keep the firmness ladder strict/normal/loose × silent/buzz/both, and anchor beep light/medium/hard).

### 4.4 Anchor record (app-side)
Per anchor: `uuid`, human `name`, `bleRemoteId`/MAC (for directed connects), last-known `ipAddress` (for WiFi schedule push + the watch's anchor-IP table), online/last-seen, role tags the user assigns (e.g., "phone dock," "desk," "nightstand"), and per-anchor settings (`max_beep_minutes`). Persist locally.

### 4.5 Watch record & live status
Paired watch: `uuid`, `bleRemoteId`, saved WiFi creds list, timezone offset, the two dormancy settings, and **live status** (activity state, bt/wifi, worn, battery %, active event id, queued unreachable-anchor notifications) parsed from the Watch Status characteristic (§6).

### 4.6 Fingerprint (proximity)
A per-anchor RF fingerprint lives **on the anchor** (self-trained). The app may optionally (a) trigger/guide a "walk-around" calibration that accelerates training, (b) observe live proximity scores for feedback, and (c) upload a prebuilt fingerprint blob. See §8.5.

---

## 5. Connectivity & transport overview

The app talks to devices over three channels:
1. **BLE (primary)** — to the watch (persistent while configuring / for phone-distance sessions) and to anchors (setup, fingerprint, docking).
2. **WiFi/HTTP (LAN)** — pushing schedules to online anchors (`http://<anchor-ip>/schedule`, §8.4).
3. **mDNS** — resolving `<anchor-uuid>.local` to discover/refresh anchor IPs on the LAN.

The app never talks UDP to anchors (that's watch↔anchor). The app supplies the watch with the **anchor IP table** so the watch can send its own UDP beep commands.

---

## 6. Complete BLE / GATT contract

All UUIDs are `4A0F00XX-F8CE-11EE-8001-020304050607`. **Update `ble_constants.dart` to include every characteristic below.** Multi-byte integers are **little-endian** unless noted. (Cross-check every wire format against `firmware_spec_v2.md`; the tables below are the current firmware truth as of this spec.)

### 6.1 Watch service `…0010`
| Char | UUID | Props | Payload / behavior |
|------|------|-------|--------------------|
| WiFi Credentials | `…0011` | Write No-Resp | JSON `{"ssid","password"}`. |
| Schedule Ctrl | `…0012` | Write w/Resp + Notify | 3-phase transfer control (§7.1). |
| Schedule Data | `…0013` | Write No-Resp | schedule blob chunks (§7.1). |
| Settings | `…0014` | Write w/Resp | `[disconnected_is_dormant u8][away_is_dormant u8][tz_offset_minutes int16][settle_window_min u16 (clamped 30–240)]`. Resp `0x01`; `0x03` = loosening fields quarantined (firmware §9.8); `0x02` = tz change rejected during active window (§9.7). **Payload grew 4→6 bytes in firmware v0.5 — lockstep.** |
| Seen Anchors | `…0015` | Read + Notify | `[count u8]` then per: `[uuid 16][rssi+128 u8][last_seen u32]`. Notifies on new discovery. |
| Watch Status | `…0016` | Read + Notify | `[activity u8 (0 dormant,1 enforcement,2 dormant_sleep)][bt u8][wifi u8][worn u8][battery_pct u8 (0xFF=n/a)][active_event_id 16][condition_met u8 (0 = actively alarming; 1 otherwise — added firmware v0.6, lockstep)]` then `[unreachable_count u8]` and per entry `[uuid 16][name_len u8][name UTF-8][ts u32]`. Notifies on change. |
| Anchor IP Table | `…0017` | Write w/Resp | `[count u8]` then per: `[uuid 16][ipv4 u32 network-order][ts u32]`. |
| LED Config | `…0018` | (present in firmware) | Format TBD — inspect firmware; expose only if used. |
| Time | `…0019` | Write w/Resp | `[utc_epoch int64][tz_offset_minutes int16]`. Sets the watch clock + timezone (firmware `firmware_spec_v2.md` §5.6). Resp `0x01`; resp `0x02` = rejected because the write would end the currently active window (firmware §9.7) — surface honestly, don't retry-loop. See §8.11. |
| **Pending Changes** | `…001A` | Read + Notify | **NEW (firmware §9.5, phase 2).** The watch's authoritative pending-loosening queue: `[count u8]` then per entry `[event uuid 16][change_type u8][seconds_until_apply u32]`. Render pending state from this; also the recovery source after an app reinstall. Probe before use. |
| **Emergency Pass** | `…001B` | Write w/Resp + Read | **NEW (firmware §9.6, phase 3).** Spend: `[0x01][event uuid 16][date u32 YYYYMMDD]` → resp `0x01`+`[remaining u8]` / `0x02` exhausted. Set allowance: `[0x02][allowance u8]` → `0x01` applied (lower) / `0x03` quarantined (raise). Read → `[allowance u8][remaining u8]` + regen countdowns. Probe before use; interim app ledger until it ships (§8.10). |

> **Time sync:** the Time characteristic (`…0019`) is specified in `firmware_spec_v2.md` §5.6 but may not yet be present in a given firmware build — check for the characteristic before writing, and until it's live, still push timezone via Settings and warn that the watch clock isn't set (§8.11, §10). `tz_offset_minutes` here and in Settings (`…0014`) map to the same stored offset; keep them consistent.

### 6.2 Anchor service `…0001`
Anchors advertise as **iBeacon** with Major `0x4A0F` (the Impulse namespace filter) + a scan-response carrying the service UUID and the 16-byte anchor UUID as service data (so the app can identify an anchor without connecting; important on iOS where manufacturer data is stripped).

| Char | UUID | Props | Payload / behavior |
|------|------|-------|--------------------|
| Identify | `…0002` | Write No-Resp | any write → anchor beeps ~800ms (find-which-anchor). |
| WiFi Credentials | `…0003` | Write w/Resp | JSON `{"ssid","password"}`. Resp `0x01` connected / `0x00` failed. |
| Settings | `…0004` | Write w/Resp | `[max_beep_minutes u16][tz_offset_minutes int16]`. Resp `0x01`. tz is required for the anchor's local schedule recalculation (firmware §4.7). **Payload grew 2→4 bytes in firmware v0.5 — lockstep.** |
| Schedule Ctrl | `…0005` | Write w/Resp | 3-phase transfer (same protocol as watch, §7.1). |
| Schedule Data | `…0006` | Write No-Resp | schedule blob chunks. |
| Toggle (servo) | `…0007` | Read + Write w/Resp | write `0x00` close/lock, `0x01` open/unlock. Read → current `0/1`. Resp `0x01` accepted, `0x02` rejected (an active enforcement event involves this anchor — only *open* can be rejected). |
| Prox Vector | `…0008` | Write w/Resp | **watch-only** (submits scan vector). App does not write this. |
| Prox Score | `…0009` | Read + Notify | `[score u8 (0 away…255 here)][flags u8]`. **App may subscribe to observe live proximity** for calibration feedback/debug. flags bit0 fingerprint-active, bit1 low-device-count. |
| Fingerprint Ctrl | `…000A` | Write w/Resp | 3-phase transfer of a fingerprint blob (upload prebuilt fingerprint, §8.5). |
| Fingerprint Data | `…000B` | Write No-Resp | fingerprint blob chunks. |
| **Dock Register** | `…000C` | Write w/Resp | **NEW.** From the phone's own connection, write `0x01` to register this connection as the docking phone, `0x00` to unregister. (§8.6) |
| **Dock Status** | `…000D` | Read + Notify | **NEW.** `[docked u8 (1/0)][rssi+128 u8]`. The app may read/subscribe to show the user whether the phone is docked. (§8.6) |

---

## 7. Transfer protocols & wire formats

### 7.1 Three-phase transfer (schedule & fingerprint, BLE)
Used on the Ctrl/Data characteristic pairs. Phases:
- **BEGIN** → Ctrl: `[0x01][total_len u32]`.
- **DATA** → Data: sequential chunks, each ≤ (negotiated MTU − 3) bytes.
- **END** → Ctrl: `[0x02][crc32 u32]` (CRC of the full blob). On CRC mismatch the device discards and the app must retry from BEGIN (`0x00`). On match, the **watch schedule** END can return (firmware §6.2/§9.3): `0x01` accepted in full; `0x03` accepted with loosening changes quarantined — read Pending Changes (`…001A`) and reflect it in the UI; `0x04` rejected in full (the push would loosen the currently active event; Phase-1 firmware). Handle all three — never render `0x03`/`0x04` as if the edit fully applied.

Negotiate a large MTU (request ~512) before transferring. `ScheduleEncoder.crc32` already implements the correct polynomial — reuse it.

### 7.2 Schedule blob (`firmware_spec_v2.md` §6.2)
`[format_version u8 = 0x02]` then `[event_count u16]` then per event: `[uuid 16][referenceDate int64][startTime u16][endTime u16][recurrenceType u8][dayOfWeek u8][dayOfMonth u8][criteria u8][enforcementProfile u8][anchorProfile u8 (0xFF null)][negate u8][donning_grace_s u16 (0 = none; firmware §5.4.4)][anchorId_present u8][anchorId 16 (zero if absent)][wifiSSID_len u8][wifiSSID UTF-8][beepAnchors_count u8]` then `[uuid 16]×count`. **`ScheduleEncoder` produces the versionless v1 layout — update it to emit the leading version byte.** This is a **lockstep** change with the watch and anchor firmware (a v1 parser misreads the version byte as event-count bits); coordinate the flash. Adding `phoneAway` to the enum makes `criteria` serialize as `4` automatically.

### 7.3 Anchor schedule over WiFi/HTTP
`HTTP POST http://<anchor-ip>/schedule` with the full blob **+ 4-byte CRC** appended (`ScheduleEncoder.encodeWithCrc`). Push to **all known anchor IPs unconditionally** (don't wait/check online) on: schedule change, whenever a new anchor IP is learned, and opportunistically on app foreground when the last successful push to an anchor is stale (older than ~12h). There is deliberately **no midnight push** — a mobile app cannot reliably execute at midnight; the anchor persists the full schedule and recomputes each day locally (`firmware_spec_v2.md` §4.7).

### 7.4 Fingerprint blob (`firmware_spec_v2.md` §6.3.2)
Per-device Welford state. Match the firmware's expected layout exactly before implementing upload (inspect `prox_load_fingerprint`): `[count u16]` then per device `[mac 6][type u8][mu f32][M f32][W f32]`. Fingerprint upload is **advanced/optional** (the primary path is on-anchor self-training); gate it behind a debug/advanced screen.

---

## 8. Feature specifications

### 8.1 Onboarding & pairing (goal-first)
Onboarding's success metric is **time-to-first-armed-commitment**. The flow is built around arming the user's first goal, not around exhaustive device setup — anchor placement happens *after* the goal is chosen, so hardware setup has narrative purpose instead of being abstract admin. Order: **pair watch → pick a goal → place only the anchors that goal needs → quick-form → armed.**

1. **Permissions:** request BLE + (Android) location/nearby-devices + notification permissions up front with rationale copy (`permission_handler`).
2. **Watch pairing:** scan for the watch's service `…0010`; on first successful connection the watch transitions UNPAIRED→DORMANT (it beeps/vibrates). Persist the watch; push time (§8.11), timezone & settings. A friendly "meet your watch" moment.
3. **Goal picker:** "What do you want to stop fighting yourself about?" — a gallery of **onboarder templates** (§2A.2), each rendered as its problem statement in the user's voice. Generated from the registry, not hardcoded UI.
4. **Anchor placement, driven by the goal:** the chosen onboarder declares its required anchor roles; the flow walks the user through pairing exactly those anchors — scan Impulse iBeacons (Major `0x4A0F`) / service `…0001` with UUID in scan-response, **Identify** (beep) to physically locate each, **name** it, assign the role, set WiFi + settings. Placement copy is purposeful ("this one goes on your nightstand — it's what gets you up"). Anchors the goal doesn't need are set up later from Devices.
5. **Quick-form:** the onboarder's 2–3 questions, everything else defaulted. Completable in under a minute.
6. **Armed:** expand the template into its tagged blocks (normal §2A expansion), push the schedule, and confirm: "your first commitment starts <when>." Close with the settle-window teach line: *"you can adjust this freely for the next two hours — after that, it's a commitment"* (§8.9: a new commitment has no settled baseline, so first-time setup is freely fixable by construction).

- **Deferral for unavailable inputs:** an onboarder input the user can't answer on the spot (e.g. Gym Time's SSID while sitting at home) gets an explicit deferral ("I'll grab this at the gym"): the commitment saves as a visible **draft** (not pushed to devices), with a notification nudge to finish it in-situ. Never dead-end the flow on an unanswerable field.
- **Skippable & re-enterable:** a "just exploring" skip path exists; "add another goal" from Home reopens the same onboarder gallery (same registry entries, same quick-forms). Onboarding is the permanent friendly entry into the registry, not a one-shot wizard.

### 8.2 Device management (`devices_screen`)
- **Watch:** connection state, live status (§8.7), battery, worn, saved WiFi list (add/remove), timezone, the two dormancy settings, "sync time" action.
- **Anchors:** per-anchor card with online state (BLE seen + LAN reachable), name/role, Identify button, WiFi setup, `max_beep_minutes`, servo lock/unlock (respect the `0x02` "rejected during active event" response and explain it), IP (auto-discovered), and a "forget" action.
- Keep the existing `anchor_service.sendToggle` and `AnchorToggleResult` handling; surface the rejected case in UI.

### 8.3 Commitment builder (`automations_screen`, `add_automation_modal`, `automation_block`)
A visual weekly schedule of commitments. For each commitment collect: time window, recurrence, **criteria** (now including **Phone-away**), target (anchor / WiFi SSID / docking anchor), firmness (EnforcementProfile), optional beep-anchors + anchor firmness, and the negate/one-off-cancel affordance ("skip this day," "disable in advance").
- **Criteria-specific pickers:**
  - getAway/stayNear → pick an anchor.
  - getOn/getOffWifi → pick/enter an SSID (offer current + saved networks).
  - **phoneAway → pick the docking anchor** (must be a role="phone dock" anchor, or let the user designate one). Explain the docking requirement here (link to §8.6 setup).
- Enforce the §4.1 validation and the §8.9 self-binding delay on edits.
- Keep color-coding (`color` field) for the calendar view.

### 8.4 Schedule distribution
On any schedule change (and when a new anchor IP is learned, and on app foreground when the last push is stale — no midnight push, see §7.3):
1. **To the watch** over BLE via the 3-phase transfer (§7.1) — this is the source of truth for enforcement.
2. **To every known anchor** over WiFi/HTTP (§7.3) — anchors need it only to decide beep-on-removal windows. Fire-and-forget to all known IPs; an offline anchor simply misses it.
3. **Push the anchor IP table to the watch** (`…0017`) so the watch can reach anchors over UDP. Refresh anchor IPs via mDNS (`<uuid>.local`) opportunistically.

### 8.5 Proximity & fingerprinting
The proximity engine self-trains on the anchor, but the app provides setup, feedback, and acceleration:
- **Live score observation:** subscribe to a target anchor's Prox Score (`…0009`) and show a live "how close does the watch look to this anchor" meter + the flags (fingerprint-active / low-device-count). Use during placement/testing.
- **Guided walk-around calibration (ship this):** a first-class flow that has the user move around near the anchor for a set duration while the anchor collects high-confidence training samples (this is what self-supervision does, sped up). **UI: a donut-shaped progress ring** that fills as calibration proceeds, with the **live Prox Score displayed inside/near the ring** so the user sees real-time proof it's working (a climbing score / the fingerprint-active flag) rather than just a countdown. **Progress driver (best-effort, open to refinement):** use the **phone's IMU/accelerometer** to confirm the user is actually moving, accumulating "movement time" toward a target (e.g. ~30–60s of real motion) rather than a plain timer someone could game by standing still. Regardless of the exact completion heuristic, build the donut UI + guidance copy now. (The anchor trains from real watch proximity queries during this window; if a dedicated anchor-side "collect now" trigger proves necessary, flag it as a firmware addition — see §10.)
- **Fingerprint upload (debug-only stub):** a stub in the Advanced debug menu that uploads a prebuilt fingerprint blob via `…000A/000B` (§7.4). Not a user-facing feature this pass.

### 8.6 Phone-distance commitments & docking (Mode B) — **the big new feature**
This is the signature "Phone-Distance Commitments" experience (`impulse_overview.md` §3.2). The phone docks at an anchor; the user must stay away from it.

**Reliability framing (must be in the UX):** enforcement follows link quality — if the phone↔anchor link is solid, enforce; if degraded, the system fails **open** (doesn't alarm). Steer users to the docking setup, and be upfront that the phone must be **docked at the anchor, app left running, and out of low-power mode**. This is the user's responsibility, and the app must make it clear and easy.

**Pre-session flow (starts ~5 min before a phoneAway window):**
1. **Notification** ~5 min before the window: "Time to dock your phone at *<anchor name>*." Tapping opens the dock screen. (Use `flutter_local_notifications`; schedule from the committed schedule.)
2. **Dock screen:** the app connects (BLE) to the docking anchor and shows a live **"Is the phone close enough?"** meter driven by the **Dock Status** characteristic (`…000D`) RSSI (and/or the app's own connection RSSI to the anchor). Guide the user to place the phone on/next to the anchor until it reads **docked**.
3. Once docked, prompt: **disable Low Power Mode** if on (detect where possible; otherwise instruct), and **leave the app open**. Then the user taps **Start**.
4. On Start, the app **writes `0x01` to Dock Register** (`…000C`) on its anchor connection, marking that connection as the docking phone, and **keeps the connection alive** for the whole window.

**During the window:**
- The app maintains the persistent phone↔anchor BLE connection. The **anchor** samples that connection's RSSI and reports docked/undocked; the **watch** reads Dock Status during its proximity checks and fuses `near_phone = undocked OR near-the-anchor`, with a tolerance grace (`PHONE_AWAY_TOLERANCE_S`, default 60s) and fail-open on a bad watch↔anchor link (firmware §5.4.1 / §4.11).
- The app should show a live **session monitor**: docked ✓/✗, time remaining, and a gentle reminder if it detects the connection dropped / app backgrounded / low-power. If the phone undocks, that is (by design) treated as the user having their phone — surface it honestly ("your phone left the dock").
- **iOS/Android background:** the app must keep the BLE connection alive while backgrounded to the extent the platform allows (BLE central background modes on iOS; foreground service on Android). Because reliability is the user's responsibility, prefer keeping the app foregrounded during the session; still, implement platform background-BLE best practices so brief backgrounding doesn't instantly drop the link.

**End of window:** unregister (write `0x00` to Dock Register) and release the connection; notify the user the phone-free block is over.

**Mode C (two-anchor dorm ranging) — deferred, but design the UI to accommodate it.** A future variant (`new_prox_engine_spec.md` §4; firmware not built yet) handles small rooms where the phone can't be strictly docked, using two anchors' RSSI difference. It is **out of scope to implement this pass**, but structure the phone-distance setup UI so a "two-anchor room" option can slot in later without a redesign — e.g. a setup-style selector ("Phone docked at an anchor" vs. "Two-anchor room") where only the docked option is active now, and a calibration step placeholder. Don't wire any Mode C logic; just don't paint the UI into a corner.

### 8.7 Live status dashboard
Subscribe to Watch Status (`…0016`) and render a home dashboard:
- Activity state (dormant / enforcing / asleep), worn ✓/✗, battery %, whether an event is active (map `active_event_id` to a commitment), and whether the watch is currently **alarming vs. compliant** (the `condition_met` byte).
- Which anchors are online (BLE seen + LAN reachable), which is currently relevant.
- **Unreachable-anchor notifications:** when the watch couldn't reach a beep-anchor, it queues `{uuid, name, ts}` entries delivered in Watch Status; surface these ("Couldn't reach *<anchor>* — check it's powered/online").
- Reflect the reliability/fail-open state clearly (e.g., "phone-free block active — phone docked").

### 8.8 Sunrise Lock (Normal-mode flagship template)
Sunrise Lock is a **Normal-mode template** (§2A), not a firmware feature. The wake-up scenario (`impulse_overview.md` §3.1): the watch charges on the nightstand next to its anchor; at wake time the anchor sounds; putting the watch on gives a self-set grace period; if still in bed at grace end, watch + anchor escalate. Under the hood it expands to a **`getAway` from the bedroom anchor** over the wake window with a **beep configuration on the nightstand anchor** (`beepAnchors` + `anchorProfile`) — which is exactly what an Advanced-mode user would see. Build a dedicated, friendly Normal-mode builder ("every parameter is something you set the night before") collecting: wake time, grace duration after the watch is put on (0–1800 s → `donningGraceS`), escalation firmness, bedroom anchor, nightstand anchor. **The mechanics are fully spec'd in `firmware_spec_v2.md` §5.4.4 (v0.6)** — the watch sends WATCH_REMOVED at window start when unworn (so the nightstand anchor sounds at wake time even though no worn *transition* occurred), and donning quiets the room and starts the `donningGraceS` grace; enforcement begins when it expires. The parameter set is final; firmware implementation ships in the same lockstep batch as the v2 blob (firmware §0.1). Tag generated blocks `templateType = sunriseLock`.

### 8.9 Self-binding delay (the integrity guarantee)
The asymmetry: **tightening is immediate; loosening is delayed** — but only after a commitment has "settled."

**Authoritative home (firmware §9):** the end-state enforcement of this policy lives **on the watch** — an on-watch schedule-diff gate quarantines loosenings and promotes them autonomously (`firmware_spec_v2.md` v0.5 §9), because an app-only guarantee dies with an app reinstall. The app implements the **identical rules** (same canonical tighten/loosen classification, firmware §9.1) in two capacities: (a) **interim enforcement** until the firmware gate ships (firmware §9.9 phasing), and (b) permanently, as the **preview layer** — computing what a proposed edit will do ("this will queue until Thursday 9am") *before* pushing, and rendering the watch's authoritative pending queue from the Pending Changes characteristic (`…001A`). Where app preview and watch verdict disagree, the watch wins; surface `0x03`/`0x04` push responses honestly (§7.1).

Precise model (an "active" schedule the devices run vs. "pending" edits that promote later):

1. **Setup window (settle timer) with a settled-state floor:** each commitment tracks its last-edit time. For **120 min** (configurable) after any edit, the commitment is "unsettled": edits apply immediately, and each new edit resets the 120-min timer. This is the build-and-test window. Free editing is bounded by the commitment's **settled baseline** — a snapshot of the commitment's state taken each time it settles (120 min elapse with no edit):
   - A **newly created** commitment has no baseline; during its first setup window *everything* is fair game, including deletion.
   - Once a baseline exists, unsettled edits apply immediately only while the resulting state is **at least as binding as the baseline** (compared per-field with the same tighten/loosen classification as item 2). An edit that would loosen *below the baseline* is never free — it goes through the item-2 delayed-loosening rules even mid-setup-window.
   - **Why the floor exists:** without it, a trivial tightening edit (always immediate) would reset the settle timer and re-open free loosening on a settled commitment — a two-tap in-the-moment escape. With the floor, tightening edits stay immediate and freely revertible *down to the baseline*, never below it.
   (There is no separate short "undo" window — the 120-min setup window is the only grace.)
2. **After it settles** (120 min since the last edit), the asymmetry kicks in:
   - **Tightening edits** (longer window, earlier start / later end, stronger firmness, harder anchor profile, adding beep-anchors, adding a commitment) still apply **immediately** — you can always bind yourself harder.
   - **Loosening edits** (delete a commitment, shorter window, weaker firmness, removing beep-anchors, one-off "skip this day" via `negate`, disabling a future window, **and any criteria or anchor/SSID target change** — non-comparable changes always classify as loosening per the canonical table, firmware §9.1) apply **immediately only if** the affected commitment is **not currently active and won't start within the next 24h** (loosening a far-future commitment grants no in-the-moment escape); **otherwise they are queued and promote after 24h.** Preview this in the retarget UX: changing tomorrow's gym SSID within 24h of the window will queue (or cost a pass).
3. **Block-level, not template-level:** apply this policy to the **resulting commitment-block changes**, never to the Normal-mode template abstraction. When a Normal template edit regenerates its child block(s) (§2A), diff old→new blocks and run each change through this same tightening/loosening logic — so a "template edit" can never sneak a loosening through instantly.
   **UUID stability (required):** an edit to an existing block must **preserve its event UUID** — the watch's diff gate matches events by UUID (firmware §9.3), and a delete+recreate pattern turns one edit into a quarantined deletion *plus* an immediately-active new event, i.e. both versions enforce concurrently for 24h. Template regeneration must reuse the UUIDs of blocks that persist across the edit; only genuinely new blocks get fresh UUIDs.
4. **Configurability:** the 120-min settle window is user-configurable within **30–240 minutes** (clamped; firmware §9.8). **Increasing** it (a longer free-edit window) is a loosening-type change → subject to the 24h rule; decreasing applies immediately. The 24h value is a fixed, documented default (tunable in code).
5. **UX & promotion mechanics:** the device keeps enforcing the **current (pre-edit)** rule until a pending loosening promotes. Promotion is not a background guarantee — it happens at the first moment *after* the 24h delay elapses that the app can actually re-push the schedule (app open, watch in range). A queued loosening can therefore only ever take effect **later** than its nominal time, never earlier; phrase the UI as "takes effect **no earlier than** <when>." Show an unmistakable pending state and a pending-changes view. Never allow an in-the-moment loosening of an active, settled commitment.

### 8.10 Emergency passes
A **rolling budget of emergency passes** that skip **one commitment for one day** when life happens.
- **Default: 2 passes per rolling 7-day window.** The allowance is **configurable**, but **increasing it is a loosening-type change subject to the §8.9 24h delay**; **spending** a pass is immediate.
- **Passes are spendable at any time — including on a currently active or imminently starting commitment.** This is a deliberate product decision: the pass is the designed escape valve, and users still calibrating the product must be able to shut a commitment down when life genuinely intervenes rather than fight the system. A couple of bypassed windows a week is an acceptable cost; a user trapped by their own misconfigured commitment is not. (Roadmap, not this pass: an **opt-in "pass lockdown"** setting letting a user forbid spending on active/imminent windows — once enabled, relaxing it is itself a §8.9 loosening.)
- **Scope: global** across all commitments (for now).
- **Authoritative home:** the ledger ultimately lives **on the watch** (firmware §9.6, Emergency Pass characteristic `…001B`), so clearing app data can't replenish passes, and a pass spend bypasses the firmware diff gate by design (it's the sanctioned escape valve — a plain `negate` push would otherwise be quarantined as a loosening). Until that firmware phase ships, the app ledger is the interim implementation; once it ships, seed the watch ledger from app state on first connect and thereafter spend via the characteristic, keeping the app-side audit trail for display.
- Implement a pass as a one-off `negate` for the chosen commitment on the chosen day (interim: app-enforced push; final: `…001B` spend), decrementing the rolling budget, with an **audit trail** (when spent, which commitment). Show remaining passes and when the next one regenerates. Spending a pass on an *active* window must take effect immediately (interim: re-push the schedule) so enforcement actually stops.

### 8.11 Time sync (dedicated firmware characteristic)
The watch needs correct wall-clock time (schedule windows, phoneAway grace, logging) and today only gets it via NTP (needs WiFi). The app sets the watch clock over BLE via the dedicated **Time characteristic** `…0019` on the watch service, **specified in `firmware_spec_v2.md` §5.6**: write `[utc_epoch int64][tz_offset_minutes int16]`. (The characteristic is spec'd but may not be present in every firmware build yet — probe for it before writing; see §10.)
- Push time **on pairing, on every app-foreground while connected, and after any timezone change.**
- Until firmware ships the characteristic, still push timezone via Settings and surface a "watch clock not set" warning.

### 8.12 Seen anchors / discovery
- Read/subscribe Watch Status-adjacent **Seen Anchors** (`…0015`): the watch reports Impulse anchors it has seen (uuid, rssi, last_seen). Use this to (a) help the user discover/name anchors the watch can see, and (b) confirm the watch is in range of the anchors a commitment depends on. Surface "the watch can/can't currently see *<anchor>*."

### 8.13 Debug tools (`debug_screen`, `debug_log_service`)
This is the **Advanced-mode debug menu** described in §2A.4 — it exists only in Advanced mode. Keep and expand the current tools: raw BLE log, manual characteristic read/write, live **Prox Score** meter, live **Dock Status**, decoded **Watch Status** dump/raw packets, force schedule re-push, and the fingerprint-upload stub (§8.5). This is the "raw packets from the watch and any other relevant information" surface. Per §2A.4, the **write-capable tools** here (manual write, force re-push, fingerprint upload, time writes) exist **only in dev/debug builds**; release builds ship the read-only telemetry surface.

---

## 9. Platform & non-functional requirements

- **BLE (flutter_blue_plus):** robust connect/reconnect with backoff; handle iOS's opaque device identifiers (persist `remoteId`, re-discover by service UUID) vs Android MAC; MTU negotiation before transfers; subscribe/notify management; graceful handling of multiple concurrent connections (e.g., during a phoneAway session the app holds the anchor while the watch also connects to it — the anchor's connection budget is limited, so keep app connections lean).
- **Permissions:** Android 12+ `BLUETOOTH_SCAN`/`CONNECT` (+ location if targeting older), notifications; iOS Bluetooth + background modes; iOS **Local Network** permission (required for mDNS and the HTTP anchor push — the prompt fires on first LAN access; handle denial gracefully with an honest "can't reach anchors over WiFi" state). Explain each with rationale.
- **Background execution:** implement platform background-BLE (iOS central background mode; Android foreground service for active phoneAway sessions) so a docked session survives brief backgrounding. Be honest in-UX that keeping the app open is the reliable path.
- **Persistence:** watch + anchors + schedule + pending-changes + emergency-pass ledger + audit trail survive restarts. The **pending-changes queue, pass ledger, and audit trail live in `drift`** (transactional, timestamped, migration-safe — they are the app's trust machinery, §2); simple prefs and device records may stay in `shared_preferences`. The schedule the devices hold is the source of truth for enforcement; the app keeps the authoring copy.
- **Reliability / fail-open:** everywhere phone-distance is involved, prefer *not* alarming on a degraded link and communicate link health, matching firmware behavior.
- **Error handling & offline:** anchors may be offline (LAN push is best-effort); the watch may be out of range; show honest, non-alarming states and retry sensibly.
- **Accessibility & theme:** keep `app_theme`; support light/dark; large tap targets; the emotional tone is calm/relief, not punitive.

---

## 10. Firmware dependencies / cross-cutting gaps (call these out to the human)

The app can't fully deliver these without matching firmware work — flag each; don't fake them:
0. **Commitment-integrity diff gate (the big one — firmware spec v0.5 §9):** on-watch tighten/loosen gating with pending queue + autonomous promotion, Pending Changes (`…001A`) and Emergency Pass (`…001B`) characteristics, active-event push protection (`0x04`), time-write rejection (`0x02`), settings gating, and the schedule **format version byte** (lockstep, §7.2). Build the app against the §9 wire formats and **probe for the characteristics at runtime**; until each firmware phase ships, the corresponding §8.9/§8.10 app-side policy is the only enforcement.
1. **Watch Time characteristic (specified; firmware code may lag):** watch-service characteristic `…0019`, Write w/Resp, payload `[utc_epoch int64][tz_offset_minutes int16]`, to set the watch clock over BLE (no NTP-free path today). **Specified in `firmware_spec_v2.md` §5.6** — build the app against that layout, but probe for the characteristic at runtime since a given firmware build may not implement it yet (§8.11).
2. **Watch LED config (`…0018`)** — payload format undocumented here; inspect firmware before exposing.
3. **Sunrise Lock mechanics — spec'd, implementation pending:** the window-start worn check + per-event `donningGraceS` (`firmware_spec_v2.md` §5.4.4, v0.6) ship in the lockstep batch; the template builder can be built now against the final parameter set (§8.8).
4. **Optional "collect fingerprint now" trigger** — if guided calibration needs an explicit anchor-side collect command rather than relying on organic watch queries (§8.5). Only add if the organic path proves insufficient.
5. Confirm **anchor connection budget** (NimBLE max connections) supports phone (persistent) + watch (transient) + app concurrently during phoneAway sessions (§8.6).

---

## 11. Screen inventory & navigation (target)

- **Onboarding** — goal-first first-run flow (§8.1); re-entered later as "add another goal."
- **Home / Dashboard** — live watch + anchors status, today's timeline, active commitment, phone-free session banner.
- **Commitments** — weekly calendar builder (`automations_screen`), add/edit modal, pending-changes/self-binding view.
- **Devices** — watch card + anchor cards (setup, identify, WiFi, settings, servo, roles).
- **Phone-dock session** — pre-session dock screen + in-session monitor (§8.6).
- **Sunrise Lock** — dedicated setup (§8.8).
- **Settings** — account/app prefs, emergency-pass allowance, self-binding delay policy, timezone, permissions.
- **Debug** — advanced tools (§8.13).

---

## 12. Acceptance criteria (high level)

The updated app can: pair a watch and anchors; name/identify/configure anchors (WiFi, settings, servo, role); author commitments for **all five criteria including phoneAway**; push schedules to the watch (BLE) and anchors (HTTP) with the self-binding delay applied; supply the watch's anchor-IP table; run a full **phone-distance docking session** (pre-session notification → dock confirmation via Dock Status → register → maintain link → monitor → end); show **live watch status** (state/worn/battery/unreachable notifications); observe **live proximity scores** and run guided calibration; sync the watch clock (once firmware supports it); and expose emergency passes and Sunrise Lock. All user-facing copy follows the `impulse_overview.md` voice guide.

---

## 13. Locked decisions (quick reference)

These are settled and already reflected in the cited sections; this is a fast index. Anything not listed here follows the recommended default noted in-section.

- **Self-binding (§8.9):** 120-min (configurable 30–240, clamped) setup window after any edit, **floored at the last settled baseline** — free editing never loosens a commitment below its last settled state (closes the tighten-to-reset loophole); brand-new commitments are fully free until first settle. Once settled: tightening = **immediate**, loosening = **immediate only if the commitment isn't active and won't start within 24h, else queued 24h**. Applied at the block level (a template edit can't sneak a loosening through). Devices run the pre-edit rule until a pending loosen promotes at the first push opportunity after the delay; UI shows "takes effect **no earlier than** <when>."
- **Emergency passes (§8.10):** rolling budget, **default 2 per rolling 7 days**, configurable — increasing the allowance is delay-gated 24h, **spending** is immediate and **allowed even on active/imminent windows** (deliberate; opt-in "pass lockdown" is roadmap); **global** scope; a pass skips **one commitment for one day**; keep an audit trail.
- **Time sync (§8.11, §10):** new dedicated watch **Time characteristic** `…0019`, `[utc_epoch int64][tz_offset_minutes int16]`; the matching firmware change is written into `firmware_spec_v2.md`. Push on pairing / app-foreground-while-connected / timezone change.
- **App modes (§2A):** Normal (default) = friendly templates from a **template registry** (seeded with hardcoded defaults: Sunrise Lock, Study Time, Gym Time, Phone-Free; forward-designed for community template libraries); Advanced = raw blocks + debug menu. Editing a template block in Advanced **detaches** it to manual; manual blocks show as **"Custom"** cards in Normal. Sunrise Lock expands to `getAway(bedroom anchor)` + beep on the nightstand anchor. Debug-menu **write tools are compile-time dev-only** (§2A.4); release builds get read-only telemetry.
- **Onboarding (§8.1):** goal-first flow — pair watch → pick a goal → place only that goal's anchors → 2–3-question quick-form → armed. Built on **onboarder-designated registry templates** (§2A.2) with required-anchor-role metadata; unanswerable inputs become visible **drafts** with a follow-up nudge; skippable and re-enterable ("add another goal" = the same gallery). v1 onboarders: Sunrise Lock, Phone-Free evening, Gym Time, Study Time.
- **Root of trust (firmware §9):** the watch authoritatively enforces the self-binding asymmetry — diff gate, pending queue with autonomous promotion, on-watch pass ledger. The app's §8.9/§8.10 logic is interim enforcement + permanent preview mirror of the **same canonical classification** (firmware §9.1); handle push responses `0x03`/`0x04` and render pending state from `…001A`. Schedule blob gains a leading **format version byte** (`0x02`); the same lockstep batch extends the watch Settings payload (+`settle_window_min u16`), the anchor Settings payload (+`tz_offset int16`), the schedule blob (+`donning_grace_s u16` per event), the Watch Status payload (+`condition_met u8`), and adds the Emergency Pass SET_ALLOWANCE opcode. Edits must **preserve event UUIDs** (§8.9 item 3).
- **Calibration (§8.5):** ship the guided walk-around flow with a **donut progress ring** (live Prox Score shown inside), driven best-effort by **phone-IMU movement time**.
- **Scope this pass:** fingerprint upload = debug-only stub; **Mode C deferred** but design the phone-distance UI to accommodate it later; guided calibration shipped.
- **Tech (§2, §9):** state management = agent's choice (be consistent); persistence = **`drift` (mandatory) for the pending-changes queue, pass ledger, and audit trail**, `shared_preferences` for simple prefs/device records; notifications = `flutter_local_notifications`, local-only; minimum platform versions unpinned (use the APIs you need — revisit later).

## 14. Remaining items to verify (not blockers)

- **Sunrise Lock mechanics — resolved in firmware spec v0.6 (§5.4.4):** window-start unworn beeping + per-event `donningGraceS`. The template builder's parameter set is final (§8.8); firmware *implementation* is pending, tracked in firmware §0.1 as part of the lockstep batch.
- The precise **completion heuristic** for guided calibration (IMU movement-time target + duration) — the UI ships regardless; tune the threshold during testing (§8.5).


