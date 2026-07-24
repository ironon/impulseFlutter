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

Code home: `impulse_app/lib`. **Last audited: 2026-07-11** (branch `app-spec-v1.2`; re-audit as work lands). **Partial re-audit 2026-07-21** covering anchor WiFi provisioning only — see the last three rows.

| Spec area | Status | Notes |
|---|---|---|
| Watch BLE connect + WiFi/settings/schedule/IP-table push (§3) | ✅ | The prototype baseline. Settings extended to the v2 6-byte payload (+`settle_window_min`). |
| `ScheduleEncoder` wire format (§7.2) | ✅ | v2 blob: emits the leading `0x02` version byte and per-event `donning_grace_s u16` (lockstep). Covered by `schedule_encoder_test`. |
| Anchor toggle (servo) (§8.2) | ✅ | Keep `AnchorToggleResult` handling. |
| `phoneAway` criteria + docking flow (§4.2, §8.6) | ✅ | Criteria (index 4) end-to-end; DockSessionService (persistent anchor link, Dock Register 0x01/0x00 lifecycle, fail-open on drops) + DockSessionScreen (setup chooser with the Mode C slot stubbed, live closeness meter from Dock Status RSSI, low-power/app-open guidance, in-session monitor, honest link-lost state) + Home dock prompt for imminent/active windows. Pre-session notification pending (notifications milestone). Audited 2026-07-12. |
| App modes / template registry (§2A) | ✅ | Registry + 4 seed templates; Settings mode toggle (Normal default, first-entry Advanced confirmation); Normal mode = registry-generated gallery + templateInstanceId-grouped cards + read-only Custom cards + drafts; Advanced = raw-block day view with origin labels, detach-to-manual on edit, Debug tab. Audited 2026-07-11. |
| Goal-first onboarding + onboarder templates (§8.1) | ✅ | First-run flow: permissions → watch pairing (time push probe) → registry goal picker (problem statements) → role-driven anchor placement (Identify beep, name, role) → quick-form → armed with settle-window teach line. SSID deferral saves a visible draft; skippable ("just exploring"); re-enterable from Commitments ("add another goal"). Audited 2026-07-11. |
| Self-binding delay (§8.9) | ✅ | Canonical classification + gate + settle floor tested; all edit paths route through AppState with preview verdicts ("applies now" / "no earlier than"), pending-changes screen + per-block badges, promotion at push opportunities, settle-window setting gated. Audited 2026-07-11. |
| Emergency passes (§8.10) | ✅ | PassesScreen: remaining + regeneration, spend flow (allowed on active windows, immediate re-push), allowance setting (raise 24h-gated), audit-trail history. Interim drift ledger; watch `…001B` used when probed present. Audited 2026-07-11. |
| Pending Changes / Emergency Pass characteristics (§6.1 `…001A`/`…001B`) | ✅ | Runtime probe + parsers/writers in `watch_service`; PendingChangesScreen renders the watch queue when present (with the app queue as fallback); pass spends prefer `…001B`. Audited 2026-07-11. |
| Live status dashboard (§8.7) + seen anchors (§8.12) | ✅ | Day-first Home tab: today's timeline with the active commitment highlighted, alarming-vs-on-track from `condition_met`, watch vitals (worn/activity/battery/WiFi), unreachable-anchor notices, anchor reachability from Seen Anchors + phone scans. Audited 2026-07-11. |
| Proximity/calibration (§8.5) | ✅ | Guided walk-around CalibrationScreen: donut progress ring driven by accelerometer movement-time (falls back to elapsed time without a sensor), live Prox Score + fingerprint-active flag inside the ring, entry from each anchor card. Fingerprint upload remains a debug stub by design. Audited 2026-07-12. |
| Time sync (§8.11) + notifications (§8.6 step 1, §8.9 item 5) | ✅ | Time pushed on pairing, on every app-foreground while connected, and with tz via Settings (0x02 rejection phrased honestly); NotificationService (flutter_local_notifications): dock reminders ~5 min before phoneAway windows, window-start notices, pending-promotion notices — OS-scheduled 48 h ahead, rescheduled on schedule change/foreground (no midnight dependency). Audited 2026-07-12. |
| Debug menu + release gating (§2A.4, §8.13) | ✅ | Advanced-only tabbed debug menu: decoded Watch Status + characteristic probes, live Prox Score / Dock Status meters (short anchor telemetry sessions), raw BLE log; write tools (manual characteristic write, force re-push, time write, fingerprint-upload stub) compile-time gated behind `BuildConfig.debugWriteToolsEnabled` (dev builds only). Audited 2026-07-11. |
| Anchor HTTP schedule push + mDNS IP discovery (§7.3/§8.4) | ✅ | AnchorDistributionService: POST blob+CRC to every known anchor IP on schedule change (fire-and-forget), staleness (~12h) re-push on app foreground, `<uuid>.local` mDNS refresh (new IP ⇒ full push + watch IP-table update). No midnight push by design. Time also re-pushed on foreground (§8.11). Audited 2026-07-12. |
| Integrity stores (drift) + reactive state (§2) | ✅ | `drift` pending-queue/pass-ledger/audit-trail (`IntegrityStore`, tested) + Provider `AppState`. |
| Anchor WiFi credential write (§6.2 `…0003`) | ❌ | **Regression vs. the parity claims above.** `anchorWifiCredCharUuid` is declared in `ble_constants.dart` but unused anywhere in `lib/`; `AnchorService` has only `identify()`/`sendToggle()`. The §8.1/§8.2 rows claiming anchor "WiFi setup" are **overstated**. Audited 2026-07-21. |
| Anchor WiFi re-provisioning + WiFi Status (§8.14, `…000E`) | ❌ | **New in v1.3.** Check-then-offer sweep, 4-slot non-destructive offers, distress notification, BLE IP fallback. Lockstep with firmware v0.8 §4.4/§4.5.1. |
| Network settings / saved networks (§8.15) | ❌ | **New in v1.3.** Settings currently has a non-persisting "Push WiFi Credentials to Watch" form (`settings_screen.dart:265`); replace with the Network section (max 4, secure-storage passwords, empty-state startup warning). Prerequisite for §8.14. Audited 2026-07-21. |
| Sync state / "stale" marker (§8.16) | ❌ | **New in v1.3.** Per-payload revision vs. per-device acked revision; auto-sync-on-change (push if connected, else scan+connect+push, else yellow); reactive convergence; kept distinct from liveness (§8.7) and pending changes (§8.9). Audited 2026-07-21. |

Legend: ✅ implemented · 🟡 partial · ⚠️ diverges from spec · ❌ not started

### 0.2 Change log

**v1.3 — 2026-07-21** (**lockstep with firmware v0.8** — anchor GATT)
- **New §8.14 "Anchor WiFi re-provisioning."** Closes the hole where an anchor that loses WiFi has no recovery path. A stranded anchor is *silently inert* — no WiFi ⇒ no SNTP ⇒ no valid time ⇒ fail-open with no beeps (firmware §4.7) — so a Sunrise Lock whose nightstand anchor is stranded simply never fires. Design is **check-then-offer**: a cheap BLE read of the new WiFi Status characteristic decides whether a write is warranted, never a blind periodic overwrite.
- **§6.2: new anchor characteristic WiFi Status `…000E`** (Read + Notify) with `state`/`ssid`/`ipv4`/`rssi`/`slots_used`. Previously the app had *no* way to ask an anchor about its network state. Also serves as a BLE fallback for learning anchor IPs when mDNS is blocked.
- **§6.2: anchor WiFi Credentials `…0003` semantics changed (lockstep).** The anchor now holds **4** credential slots (dedup by SSID, LRU eviction) and the write responds `0x01` = *accepted*, immediately, with the outcome delivered via a `…000E` notify. **`0x01` no longer means "connected"** — subscribe before writing.
- **Offers to healthy anchors are now allowed**, purely because 4 slots + most-recently-successful-first ordering make them non-destructive. On older single-slot firmware they are not safe; probe `…000E` and fall back (§10 item 6).
- **Distress notification added.** An anchor in auth-failed / AP-not-found state that we can't fix from saved credentials prompts the user for the password, rate-limited per distress episode. Justified because the failure is invisible and costs the user their alarm.
- **The watch now repairs anchors too** (firmware §5.5.3): battery-gated (>4000 mV, i.e. on the charger), ~20 min interval, **schedule-referenced anchors only**. Repairs are **silent** — no Watch Status change — so the app must re-read `…000E` rather than trust cached state, and must keep the watch's saved-network list current since the watch can only offer what it holds.
- **§4.4:** anchor record gains `lastWifiState`/`lastWifiSsid`/`lastWifiCheckAt`/`slotsUsed`/`offeredSsids[]`; app-level saved-networks list made explicit.
- **§3 item 11 / §0.1: honest correction** — anchor WiFi credential writing was never implemented (`anchorWifiCredCharUuid` has zero usages in `lib/`), so prior ✅ rows claiming anchor "WiFi setup" were overstated.
- **Documented platform constraint:** the app cannot read OS-saved WiFi passwords, so offers only ever carry credentials the user typed into the app. Rotated router passwords can be *detected* but not silently healed — copy must not imply otherwise.
- **New §8.15 "Network settings."** Settings' **"Push WiFi Credentials to Watch"** form is **removed** and replaced by a **Network** section owning a persistent saved-networks list (**max 4**, matching `ANCHOR_WIFI_MAX_CRED_SLOTS`): rows per network, tap for detail with masked password + eye reveal, add/edit/delete. The old form persisted nothing — it typed credentials straight at the watch and forgot them — which is precisely why §8.14 had no credential source. Editing a saved password is now the user-facing fix path for the rotated-router-password case.
- **Empty-list startup warning (§8.15):** with no networks saved, warn on **every** launch with **Ignore** (this launch only) / **Fix** (opens add-network). Deliberately un-suppressible, because an empty list means anchors never reach SNTP and therefore never beep at all (firmware §4.7).
- **§2: `flutter_secure_storage` added** for saved WiFi passwords — credential material shouldn't sit in plaintext `shared_preferences`.
- **New §8.16 "Sync state & the stale marker."** Per-payload **revision counters** vs. per-device **acknowledged** revisions; staleness is *derived*, never a stored flag, and is pessimistic (unconfirmed = stale, self-heals on reinstall). **Auto-sync on any authoring change:** push if the watch is connected, else scan → connect → push, else mark the device **yellow** in Devices; anchors go yellow when an HTTP push isn't `200`-acked. Convergence is reactive — a device coming into range clears its own yellow. Explicitly reconciled with §8.9 (a withheld loosening is *not* stale) and kept visually distinct from liveness (§8.7).
- **Schedule sync is now confirmed, not just inferred (lockstep, firmware v0.8).** Watch Status `…0016` gains a `schedule_crc u32`; anchors answer `GET /schedule` and mirror the CRC in WiFi Status `…000E`. The app cross-checks against `ScheduleEncoder`'s CRC to catch a device that reverted to a stale persisted schedule after a reset — the failure pure inference can't see.

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

### 0.3 v1.3 implementation handoff (build order & notes)

The v1.3 / firmware-v0.8 batch is large and tightly coupled. **Do not attempt it all at once** — build in this order, where each step depends on the previous. Firmware and app steps interleave; the firmware-only ordering is mirrored in `firmware_spec_v2.md` §10.2.

1. **Firmware: anchor WiFi refactor + WiFi Status `…000E` (firmware §4.4, §4.5.1, §6.2).** Event-driven WiFi (distinguishes auth-fail `0x03` / no-AP `0x04`), 4-slot non-destructive credential store, non-blocking write response, WiFi Status characteristic incl. `schedule_crc`, `GET /schedule` CRC readback, and the `schedule_crc` byte in Watch Status. **Everything else waits on this.** Flash watch + anchor + app status-parsers together (lockstep).
2. **App: implement the missing anchor WiFi write (§3 gap 11).** `AnchorService.sendWifiCredentials()` against `…0003`, plus reading `…000E`. This is currently *unimplemented* despite prior ✅ marks — it's the true starting point on the app side.
3. **App: Network settings §8.15.** Persistent saved-networks list (max 4, `flutter_secure_storage` passwords, empty-state startup warning gated on having hardware). This is the credential *source* everything downstream draws from — nothing to offer without it.
4. **App: schedule/config sync state §8.16.** Revision-vs-acked tracking, CRC cross-check for the schedule class, auto-sync-on-change (push / scan+push / yellow), reactive convergence. Reuses the existing `AnchorDistributionService` staleness machinery.
5. **App: anchor re-provisioning §8.14.** Check-then-offer built on steps 2–4 (needs the read path, saved networks, and sync/reachability signals).
6. **Firmware: watch-side anchor repair (firmware §5.5.3).** Independent of the app steps; needs only `…000E` (step 1) and the battery ADC. Can proceed in parallel after step 1.
7. **App: emergency-pass out-of-range fix §8.10.** Small but a behavior change to a locked decision — do it deliberately, with the ack-before-decrement + pending-spend UX.

**Cross-cutting notes for the implementer:**
- **Probe, don't assume, for the integrity characteristics.** `…001A`/`…001B` (§6.1) are already runtime-probed; keep that pattern. The v0.8 additions (`…000E`, `schedule_crc`, `GET /schedule`) ship in one flash, so within this batch the app may assume they're present — but still fail *gracefully* (treat a missing readback as "infer from acks," not a crash).
- **Two numbers must stay equal:** the app's saved-networks cap (§8.15) and firmware `ANCHOR_WIFI_MAX_CRED_SLOTS` (§4.4) are both 4. Reference the constant; don't hardcode a second literal that can drift.
- **Three independent indicators** — liveness (§8.7), sync/stale (§8.16), pending-loosening (§8.9) — must remain visually and logically distinct. The most common implementation mistake here will be collapsing "device behind" and "change deliberately withheld" into one state; §8.16 spells out why they differ.
- **The app is never the sole writer.** The watch heals anchors (firmware §5.5.3) and holds the authoritative pass/pending ledgers (§8.9/§8.10). Always re-read device state rather than trusting the app's last-known value.

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
- Required addition: **`drift`** for the integrity-critical stores — the pending-changes queue, emergency-pass ledger, and audit trail must be transactional, timestamped, and migration-safe (they are the app's trust machinery); `shared_preferences` remains fine for simple prefs and device records. Further additions: `flutter_local_notifications` (pre-session dock reminders, §8.6); `http` (anchor schedule push, §8.4); `multicast_dns` or platform mDNS for anchor IP discovery (§8.4); `network_info_plus` (LAN/SSID awareness); **`flutter_secure_storage`** for saved WiFi passwords (§8.15 — credential material that should not sit in plaintext `shared_preferences`). Justify any heavy addition beyond these.
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
11. **Anchor WiFi credentials are never written at all.** `anchorWifiCredCharUuid` is declared in `ble_constants.dart` but has **zero usages** anywhere in `lib/` — `AnchorService` exposes only `identify()` and `sendToggle()`. The watch's equivalent is wired up (`watch_service.dart`), the anchor's is not, so §8.1 step 4 / §8.2 "set WiFi + settings" is unimplemented despite the parity table marking those rows ✅. Implement `AnchorService.sendWifiCredentials()` plus the WiFi Status read, then build §8.14 on top.

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

**WiFi provisioning state (§8.14):** `lastWifiState` (the `…000E` `state` byte), `lastWifiSsid`, `lastWifiCheckAt`, `slotsUsed`, and `offeredSsids[]` — the SSIDs this app has already offered to this anchor, with the timestamp and observed outcome of each. `offeredSsids` is what prevents re-offering the same failing credentials on every sweep.

**Saved networks (app-level, not per-anchor):** a list of `{ssid, password}` pairs the user has entered in the app, **capped at 4** to match `ANCHOR_WIFI_MAX_CRED_SLOTS`. This is the *only* source of credentials an offer can draw from — see the platform constraint in §8.14. Managed in the Settings **Network** section (§8.15), and consumed by the watch credential push (`…0011`), anchor provisioning (`…0003`), and the watch's autonomous repair (firmware §5.5.3).

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
| Watch Status | `…0016` | Read + Notify | `[activity u8 (0 dormant,1 enforcement,2 dormant_sleep)][bt u8][wifi u8][worn u8][battery_pct u8 (0xFF=n/a)][active_event_id 16][condition_met u8 (0 = actively alarming; 1 otherwise — added firmware v0.6, lockstep)][schedule_crc u32 (CRC32 of the last-accepted schedule blob, 0 if none — added firmware v0.8, lockstep; §8.16 sync verification)]` then `[unreachable_count u8]` and per entry `[uuid 16][name_len u8][name UTF-8][ts u32]`. Notifies on change. |
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
| WiFi Credentials | `…0003` | Write w/Resp | JSON `{"ssid","password"}`. **Changed in firmware v0.8 (lockstep):** the anchor stores up to **4** credential pairs (dedup by SSID, LRU eviction) and the write **no longer blocks on the connection attempt** — resp `0x01` = *accepted and will be attempted*, `0x00` = malformed. The connection **outcome** arrives via a WiFi Status notify, so **subscribe to `…000E` before writing**. Never treat `0x01` as "connected." |
| **WiFi Status** | `…000E` | Read + Notify | **NEW (firmware v0.8 §4.4).** `[state u8][ssid_len u8][ssid UTF-8][ipv4 u32 network-order][rssi+128 u8][slots_used u8]`. `state`: 0 never provisioned · 1 connecting/retrying · 2 connected · 3 auth failed · 4 AP not found. States **3 and 4 (and 0) are "distress."** Notifies on state transition and on IP change. Also the BLE-side fallback for learning an anchor's IP when mDNS fails (§8.14). |
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
- **Watch:** connection state, live status (§8.7), battery, worn, saved WiFi list (add/remove), timezone, the two dormancy settings, "sync time" action, and the **sync-state marker** (§8.16 — yellow when the watch is behind the app's authoring copy, with a "Sync now" retry).
- **Anchors:** per-anchor card with online state (BLE seen + LAN reachable), name/role, Identify button, WiFi setup, `max_beep_minutes`, servo lock/unlock (respect the `0x02` "rejected during active event" response and explain it), IP (auto-discovered), and a "forget" action.
  - **WiFi state comes from the anchor, not from inference.** Read `…000E` (§8.14) when the card opens and render the real `state` — "on *\<ssid\>*", "can't find *\<ssid\>*", "wrong password for *\<ssid\>*", "never set up" — instead of guessing from HTTP timeouts. Show `slots_used` in Advanced mode only.
  - **"Re-send WiFi" action:** offers a saved network to this anchor (§8.14). Safe to expose unconditionally now that anchor credentials are slot-based and non-destructive; when the anchor is in distress and we hold no matching password, this is the prompt-for-password entry point.
  - **Sync-state marker (§8.16):** yellow when the app knows this anchor is behind on schedule/settings/creds, with a "Sync now" retry. Distinct from the online/offline liveness dot and from any pending-loosening state.
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
- **The spend is only real once the watch confirms it (important — surfaced by §8.16).** A spend, whether via `…001B` or the interim re-push, is a **BLE write that fails silently when the watch is out of range.** If the app optimistically decrements the budget and the write never lands, the user loses a pass *and keeps getting alarmed* — the exact opposite of the escape valve's purpose. So: **do not commit the decrement until the watch acknowledges** (the `…001B` `0x01` response, or the interim schedule END ack). If the watch is unreachable at spend time, hold the spend as **pending**, tell the user honestly — *"Can't reach your watch. The pass will apply the moment it's back in range — enforcement may continue until then"* — and complete it automatically when the watch reconnects (same opportunistic path as §8.16). The watch card shows stale/yellow meanwhile. A pending spend must be visibly distinct from a completed one in the audit trail, and must not be double-charged if the user retries. (When the watch is in range, this is invisible — the spend commits in the same round trip.)

### 8.11 Time sync (dedicated firmware characteristic)
The watch needs correct wall-clock time (schedule windows, phoneAway grace, logging) and today only gets it via NTP (needs WiFi). The app sets the watch clock over BLE via the dedicated **Time characteristic** `…0019` on the watch service, **specified in `firmware_spec_v2.md` §5.6**: write `[utc_epoch int64][tz_offset_minutes int16]`. (The characteristic is spec'd but may not be present in every firmware build yet — probe for it before writing; see §10.)
- Push time **on pairing, on every app-foreground while connected, and after any timezone change.**
- Until firmware ships the characteristic, still push timezone via Settings and surface a "watch clock not set" warning.

### 8.12 Seen anchors / discovery
- Read/subscribe Watch Status-adjacent **Seen Anchors** (`…0015`): the watch reports Impulse anchors it has seen (uuid, rssi, last_seen). Use this to (a) help the user discover/name anchors the watch can see, and (b) confirm the watch is in range of the anchors a commitment depends on. Surface "the watch can/can't currently see *<anchor>*."

### 8.13 Debug tools (`debug_screen`, `debug_log_service`)
This is the **Advanced-mode debug menu** described in §2A.4 — it exists only in Advanced mode. Keep and expand the current tools: raw BLE log, manual characteristic read/write, live **Prox Score** meter, live **Dock Status**, decoded **Watch Status** dump/raw packets, force schedule re-push, and the fingerprint-upload stub (§8.5). This is the "raw packets from the watch and any other relevant information" surface. Per §2A.4, the **write-capable tools** here (manual write, force re-push, fingerprint upload, time writes) exist **only in dev/debug builds**; release builds ship the read-only telemetry surface.

### 8.14 Anchor WiFi re-provisioning ("credential offers")

**The problem.** An anchor stores its WiFi credentials once, at setup. If it never got them, if NVS was cleared, or if the network changed, it falls off the LAN with no recovery path — and a stranded anchor is *silently inert*, not merely degraded: no WiFi means no SNTP, and with no valid time the anchor acts as though it has no schedule and will not beep at all (firmware §4.7). A Sunrise Lock whose nightstand anchor is stranded simply doesn't go off. BLE is always available as the repair channel, because anchors advertise continuously and stay connectable regardless of WiFi state (firmware §4.3).

**Platform constraint — read this before designing the UX.** Neither iOS nor Android will give the app the saved password for the network the phone is currently on. An offer can therefore only ever contain credentials **the user typed into the app** (the saved-networks list, §4.4). This mechanism can self-heal:
- an anchor that never successfully received credentials (setup failed, user walked away),
- an anchor whose NVS was cleared or was factory-reset,
- a network the user has since added in the app (moved house, new router, second AP),
- a multi-AP home where an anchor is stuck on the wrong band.

It **cannot** silently fix the most common real case — the user rotated the router password and never told the app. That case can only be *detected* and *prompted*. Do not write copy that implies automatic recovery in general; be specific.

**Check first, offer second.** The periodic action is a cheap BLE **read**, never a blind write. Connect, subscribe to `…000E`, read WiFi Status, then decide:

| Anchor `state` | Condition | Action |
|---|---|---|
| `2` connected | phone's current SSID is already in `offeredSsids` or matches the anchor's | nothing |
| `2` connected | a saved network the anchor doesn't hold | **offer** — additive resilience; the anchor banks it in a spare slot and will not drop its working link to try it (firmware §4.4) |
| `0` never provisioned | a saved network exists | **offer** |
| `3` auth failed / `4` AP not found | anchor's stored SSID matches a saved network **whose password we've not already offered** | **offer** |
| `3` / `4` | no saved password for the anchor's SSID, or we already offered it and it still failed | **prompt the user** (below) |
| `1` connecting | any | wait; re-check next sweep |
| BLE unreachable too | — | existing "check it's powered" state (§8.7) |

Offering to a *connected* anchor is safe only because of the firmware's 4 slots and most-recently-successful-first ordering — an offer can never orphan a working anchor. If that firmware behavior ever changes, this row must change with it.

**Triggers.** Don't invent a new timer — reuse `AnchorDistributionService`'s existing foreground staleness sweep (§7.3, ~12 h), which already walks every known anchor. Run the BLE WiFi-Status check when:
1. that sweep's HTTP push or mDNS resolve for an anchor **fails**, or
2. an anchor is visible in a BLE scan but has had no successful LAN contact in ~12 h, or
3. the user opens that anchor's card in Devices (check immediately — they're standing there), or
4. a new anchor IP is learned and the push still fails.

Failure-driven, with 12 h as the outer bound. One staleness concept for the user to understand, shared with the schedule push.

**Learning the IP over BLE.** When `state == 2`, record `ipv4` from the read into the anchor's `ipAddress`. This is a genuine fallback for the HTTP push when mDNS is unavailable — common on guest/enterprise networks. It does **not** rescue a denied iOS Local Network permission (the HTTP push itself still needs it); in that case keep the honest "can't reach anchors over WiFi" state from §9.

**The prompt path (distress we can't fix ourselves).** When an anchor is in state `3`/`4` and we have no working password for it, surface a **notification** — not just a passive card state:
> "*\<anchor name\>* can't get on *\<ssid\>*. Until it's back online it won't sound." → tapping opens the anchor's WiFi setup with the SSID pre-filled, asking only for the password.

This crosses the notification threshold because the failure is invisible and consequential: the user's Sunrise Lock will quietly not fire. Rate-limit to once per anchor per distress episode (reset when the anchor's `state` changes) so a permanently-dead anchor doesn't nag daily. Use the existing `NotificationService` (§8.6/§8.11). Keep the voice calm and factual per `impulse_overview.md` — state the consequence, don't alarm.

**The watch also repairs anchors (firmware §5.5.3).** A watch on the charger (battery > 4000 mV, dormant, not connected to the app) checks every ~20 min for schedule-referenced anchors in distress and offers its own stored credentials. This is the Sunrise Lock safety net — the watch is on the nightstand all night beside the exact anchors that commitment depends on. Implications for the app:
- **The app is not the only writer.** An anchor may recover without the app doing anything; always re-read `…000E` rather than trusting cached state. Offers are idempotent by SSID on the anchor side, so the two healers cannot conflict.
- **Repairs are silent** — the watch does not report them (deliberate, to keep Watch Status stable). The app discovers recovery on its next check.
- **Keep the watch's credential list current.** The watch can only offer what it holds, so pushing a newly saved network to the watch (`…0011`) is now also a *repair-capability* update, not just a watch-connectivity one. Push saved networks to the watch whenever the list changes.

**Security note.** The anchor GATT is unauthenticated, so any nearby device can write credentials to an anchor. This is pre-existing and acceptable — the anchor is not the root of trust (the watch is, §8.9) and anchor loss degrades beeping but not enforcement (fail-open by design). The corresponding *outbound* risk — leaking the user's WiFi password to a device merely advertising the Impulse iBeacon Major — is why the watch restricts its offers to schedule-referenced anchors (firmware §5.5.3). The app has a stronger filter: it only ever offers to anchors the user has explicitly paired and named.

### 8.15 Network settings (the saved-networks store)

**Replaces the "Push WiFi Credentials to Watch" section in Settings** (`settings_screen.dart`, currently a fire-and-forget SSID/password form calling `pushWifiCredentials` — it persists nothing). That form is the reason §8.14 has no credentials to draw on: the app has never remembered a network the user typed. The replacement is a **"Network"** section that owns the saved-networks list defined in §4.4.

**This list is now infrastructure, not a form.** It is the single source of credentials for three separate consumers:
1. the watch's credential list (`…0011`), pushed whenever the list changes,
2. anchor provisioning and re-provisioning offers (`…0003`, §8.14),
3. the watch's autonomous anchor repair (firmware §5.5.3) — the watch can only offer what it holds, so a network missing here is a repair the watch cannot perform.

Because of (3), keeping this list current is a *reliability* action, not a convenience. Say so in the section's supporting copy.

**Section contents:**
- **A list of saved networks**, each row showing the SSID and a compact status hint (e.g. "on this network now" when it matches the phone's current SSID via `network_info_plus`).
- **Tapping a row** opens the network detail: SSID, and the password rendered as `••••••••` with an **eye toggle** to reveal it. Editing either field is allowed; saving re-pushes to the watch and re-offers to any anchor in distress (§8.14) — this is the fix path for a rotated router password, which §8.14 can detect but not heal on its own.
- **A "Add network" button**, which opens the same add/edit sheet.
- **A delete affordance** per network. Deleting must be honest: it stops the app and watch offering that network, but it **cannot retract credentials already stored on a device**. Word it as "stop using this network," not "remove from devices."

**Limit: 4 networks.** This is not arbitrary — it matches `ANCHOR_WIFI_MAX_CRED_SLOTS` (firmware §7). An app list longer than the anchor's slot table would mean offers silently evicting each other on the anchor, producing an anchor that flaps between credential sets and an app that believes all of them are installed. Keep the two numbers equal; if the firmware constant changes, change this with it. At 4 networks, disable "Add network" and explain the ceiling ("anchors can hold four networks") rather than hiding the button.

**Empty-state startup warning.** When the saved-networks list is **empty**, warn on **every app startup**:
> "No WiFi networks configured. Your anchors can't come online without one, and your watch can't set its clock."
>
> **[Ignore]** **[Fix]**

- **Fix** opens the same add-network sheet as the button above.
- **Ignore** dismisses **for this launch only** — the warning returns next startup. This is deliberate: the empty state is not a preference, it's a broken install in which anchors never reach SNTP and therefore never beep at all (firmware §4.7). The nagging ends the moment one network exists, which is a single 20-second action, so there is no need for a permanent opt-out.
- Only the *empty* list triggers this. A populated-but-failing state is handled by the per-anchor distress notification in §8.14, which is more specific and more actionable.
- **Gate on having hardware.** Suppress the warning entirely until at least one device (watch or anchor) is paired. A "just exploring" user (§8.1 skip path) with no hardware has nothing that needs a network, and nagging them is noise. The warning is about a *broken* install, not an *empty* one.
- **Migration caveat.** The old form persisted nothing, so on first launch after this change the list is empty even for users whose watch/anchors already hold credentials. The warning may therefore fire once for an install that is actually fine; re-adding the network (a 20-second action) both silences it and gives §8.14/§5.5.3 something to work with. Acceptable — the app is the authoring source of truth and this reconciles it.

**Storage.** These are real WiFi passwords held in plaintext at rest if they go in `shared_preferences`. Prefer **`flutter_secure_storage`** (Keychain / Android Keystore) for the password field, keeping SSIDs and metadata in the existing prefs store. This is a justified dependency addition under §2: it is credential material, and the alternative is passwords readable from an unencrypted app-data backup. The reveal toggle needs no biometric gate — the threat model here is device theft, which secure storage addresses, not the self-binding adversary of §8.9 (WiFi credentials grant no commitment escape).

**Ordering.** Present in the order added; the app offers all saved networks and lets the anchor's own slot ordering (firmware §4.5.1, most-recently-successful first) decide what it actually uses. Don't build user-facing reordering — it would imply a priority the devices don't honor.

### 8.16 Sync state & the "stale" marker

The app is the authoring copy; the devices hold the enforced copy. Whenever the app *knows* its copy is ahead of what a device holds, it must say so plainly — a yellow "stale" marker on that device — and it must try to close the gap automatically. This is the visible half of a guarantee that's otherwise invisible until a commitment silently misbehaves.

**Model: derive staleness, never store a flag.** Do not set a "stale" boolean anywhere — flags rot (set-and-forget bugs, missed reset paths). Instead:
- Each **pushable payload class** carries a monotonic **revision counter**, bumped on every authoring edit that changes it. The classes and their target devices:

  | Payload class | Targets | Push transport |
  |---|---|---|
  | Schedule | watch + all anchors | watch BLE 3-phase (§7.1); anchors HTTP (§7.3), BLE fallback |
  | Watch settings (dormancy, tz, settle window) | watch | BLE `…0014` |
  | Watch saved-networks list | watch | BLE `…0011` |
  | Watch anchor-IP table | watch | BLE `…0017` |
  | Anchor settings (max_beep, tz) | per anchor | BLE `…0004` |
  | Anchor WiFi creds | per anchor | BLE `…0003` (§8.14) |

- Each **device record** stores, per payload class, the **last revision it acknowledged**. "Acknowledged" is strict: the write-with-response `0x01` (settings/creds/IP table), the schedule END `0x01`/`0x03` (§7.1), or an HTTP `200` (anchor schedule). A *sent* update that wasn't acked does **not** advance the acked revision — optimistic tracking would show green over a dropped write, which is the one thing this feature exists to prevent.
- **Confirm, don't just infer, for the schedule (firmware v0.8).** The watch reports the CRC32 of its last-accepted schedule in Watch Status (`…0016`), and each anchor answers `GET /schedule` — and mirrors the same CRC in WiFi Status (`…000E`) — with the blob it currently holds. Compare it against `ScheduleEncoder`'s CRC of the effective schedule: **match → confirmed synced** (clears yellow even if the app never saw the ack, e.g. after a reinstall); **mismatch → stale**, even if the app *believed* it had pushed. This catches a device that silently reverted to a stale persisted schedule after a reset/re-flash — the one failure inference alone can't see. Revision-vs-acked (above) remains the mechanism for the classes with no readback (settings, creds, IP table); the schedule additionally gets this authoritative cross-check.
- **Stale = `currentRevision > device.ackedRevision`** for any class that device owns. A device is shown stale if *any* of its classes is behind. Persist acked revisions with the device records (`shared_preferences` is fine — this is device state, not integrity trust machinery); persist current revisions with the authoring copy. On reinstall, acked revisions are absent → everything reads stale → the app re-pushes and converges. Pessimistic by construction.

**Time is not a payload class.** The watch clock (`…0019`) advances continuously and is pushed on its own triggers (§8.11); never fold it into staleness or the watch would read stale forever.

**Critical interaction with the self-binding delay (§8.9).** Staleness compares the device against the schedule it *should currently be running*, **not** the raw authoring copy. A pending **loosening** that hasn't promoted yet is *supposed* to be absent from the device — the device correctly runs the old rule. That is **not** stale; it is the pending-changes state (§8.9), shown by that UI, not by a yellow marker. Only the **effective** schedule (current rule + already-promoted changes + immediate tightenings) feeds the schedule revision counter. Concretely: an immediate tightening that hasn't reached the watch → stale/yellow; a queued loosening waiting out its 24 h → not stale. Getting this wrong makes the two systems fight — the stale marker would nag the user to "sync" a change the system is deliberately withholding.

**Auto-sync on change (the behavior you asked for).** Any authoring edit (Settings, Network, a commitment, anchor config) bumps the relevant revision(s), then immediately kicks a **sync attempt** for each affected device:
1. **Watch:** if BLE-connected, push the affected payload(s) now. If not connected, start a **bounded background scan** for the watch service `…0010` (the watch advertises on a ~6 s heartbeat even while dormant, firmware §8, so it's usually findable within seconds). On finding it: connect, push, and let the connection follow normal lifecycle. If the scan times out or the push fails → leave the acked revision where it was, so the watch renders **stale/yellow** in Devices.
2. **Anchors:** HTTP-push to every known anchor IP (existing §8.4 fire-and-forget). Each `200` advances that anchor's acked schedule revision; anchors that don't `200` stay **stale/yellow**. For config classes that only travel over BLE (anchor settings, WiFi creds), attempt a directed BLE connect when the anchor is BLE-visible but LAN-unreachable — the same visible-over-BLE-but-stranded fallback as §8.14.
3. **Debounce.** Coalesce a burst of rapid edits into one sync attempt (e.g. 1–2 s trailing debounce) so tapping through several settings doesn't fire several scans.
4. **Foreground operation.** The scan/connect/push is a **foreground** action — the user just edited something, so the app is open. Don't attempt background BLE scanning for sync (iOS forbids it and it drains battery); if the app is backgrounded before an attempt completes, leave the device stale and retry on next foreground (this is exactly the opportunistic-convergence path below).

**Opportunistic convergence.** Staleness is reactive state in `AppState`, recomputed when (a) an edit bumps a revision, (b) a device acks a push, or (c) a device's **connection state changes**. A stale device coming into range must auto-trigger its pending sync — a watch that reconnects, or an anchor whose IP is freshly learned/reachable, clears its own yellow without user action. This reuses the §7.3/§8.4 staleness-push machinery; sync state is that mechanism made *visible and per-payload* rather than schedule-only. **Self-binding promotion rides the same path:** when a queued loosening promotes (§8.9 item 5), it changes the *effective* schedule → bumps the schedule revision → triggers a sync attempt exactly like any other edit. No separate promotion-push path is needed.

**Transient vs. settled — don't cry wolf.** While a scan or push is **in flight**, show a **spinner / "syncing…"**, not yellow. Yellow appears only after an attempt has **failed or timed out** (device behind and not currently reachable). Distinguish the two subtitles honestly:
- *"Syncing…"* — attempt in progress.
- *"Waiting to reach your watch"* / *"Anchor offline — will sync when reachable"* — settled stale, will retry opportunistically.

Yellow is **informational, not an error** — a watch out of range and behind is a normal, calm state, consistent with the product voice (`impulse_overview.md`). Never red; red is for enforcement-critical failures, not sync lag.

**Devices screen presentation (§8.2).** A stale device card gets a **yellow background/edge** plus a one-line reason. **Never color-only** (§9 accessibility): pair the yellow with an icon and the text reason, so the state survives colorblindness and greyscale. Same rule for the green/neutral synced state — don't rely on hue alone to signal "all good." Tapping expands *what* is behind (schedule, settings, networks) and offers a **"Sync now"** retry that reruns the sync attempt (including a fresh scan). When everything is acked, the card returns to its normal (green/neutral) state with no marker. Aggregate honestly: "3 changes waiting" is fine; don't enumerate every revision.

**Scope note.** Sync state covers *configuration the app pushes*. It is distinct from **liveness** (§8.7, is the device online right now) and from **pending changes** (§8.9, deliberately-withheld loosenings). A device can be online, fully synced, and still have pending loosenings — three independent indicators. Keep them visually distinct so the user can tell "you need do nothing," "waiting to reach a device," and "a change is holding until Thursday" apart.

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
5. Confirm **anchor connection budget** (NimBLE max connections) supports phone (persistent) + watch (transient) + app concurrently during phoneAway sessions (§8.6). **Now also load-bearing for §8.14:** the app's periodic WiFi-Status checks and the watch's repair connects (firmware §5.5.3) both consume anchor connection slots. Keep both lean — connect, read, act, disconnect.
6. **Anchor WiFi slots + WiFi Status characteristic (firmware v0.8 §4.4/§4.5.1) — lockstep.** §8.14 depends on `…000E` and on the credential write becoming non-blocking/multi-slot. **Probe for `…000E` at runtime**; against older anchor firmware, fall back to the current behavior (treat `0x01` on the credential write as "connected," infer health from HTTP reachability only) and don't offer to anchors that appear healthy — the single-slot overwrite risk is real on those builds.
7. **Watch-side anchor repair (firmware §5.5.3)** — no app wire change, but the app must keep the watch's saved-network list current for it to work (§8.14). Nothing to probe; the app simply cannot observe repairs directly by design.
8. **Device-reported schedule CRC for §8.16 (firmware v0.8 — now in the lockstep batch).** The watch reports its last-accepted schedule CRC32 in Watch Status (`…0016`); each anchor answers `GET http://<ip>/schedule` with its stored blob's CRC and mirrors it in WiFi Status (`…000E`). The app compares against `ScheduleEncoder`'s CRC to **confirm** sync rather than infer it, catching a device that reverted to a stale persisted schedule after a reset. Prefer the CRC cross-check for the schedule class; revision-vs-acked remains the fallback for classes with no readback. **All devices are flashed in the v0.8 lockstep batch** (backward compatibility is explicitly out of scope), so the app may assume the v0.8 Watch Status layout — do **not** try to version-detect by Watch Status length, which is ambiguous because the trailing unreachable-notification section is variable-length.

---

## 11. Screen inventory & navigation (target)

- **Onboarding** — goal-first first-run flow (§8.1); re-entered later as "add another goal."
- **Home / Dashboard** — live watch + anchors status, today's timeline, active commitment, phone-free session banner.
- **Commitments** — weekly calendar builder (`automations_screen`), add/edit modal, pending-changes/self-binding view.
- **Devices** — watch card + anchor cards (setup, identify, WiFi, settings, servo, roles).
- **Phone-dock session** — pre-session dock screen + in-session monitor (§8.6).
- **Sunrise Lock** — dedicated setup (§8.8).
- **Settings** — account/app prefs, **Network** (saved-networks list, §8.15 — replaces "Push WiFi Credentials to Watch"), emergency-pass allowance, self-binding delay policy, timezone, permissions.
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
- **Anchor WiFi re-provisioning (§8.14):** **check-then-offer**, never blind periodic writes. Anchors hold **4** credential slots so offers are non-destructive; the app therefore *may* offer to healthy anchors for resilience, while the **watch** offers only to anchors **in distress** and only to those **referenced by its own schedule** (a security boundary — any device can advertise Major `0x4A0F`). Watch repair is gated on **battery > 4000 mV** (on the charger) at a **~20 min** interval and is **silent** (no Watch Status change). Trigger the app's checks off the existing ~12 h staleness sweep and on LAN-push failure. Anchors we can't fix from saved credentials **notify** the user. The app can never read OS-saved WiFi passwords — rotated passwords are detectable, not auto-healable.
- **Network settings (§8.15):** Settings' "Push WiFi Credentials to Watch" form is **replaced** by a **Network** section holding a persistent, user-managed list of **at most 4** saved networks (the cap mirrors the anchor's credential slots — keep the two equal). Password masked with an eye reveal; edits re-push to the watch and re-offer to distressed anchors. An **empty** list warns on **every** startup (Ignore = this launch only, Fix = add a network) because it silently breaks all anchor behavior. Passwords live in `flutter_secure_storage`.
- **Sync state (§8.16):** staleness is **derived** (per-payload revision vs. per-device *acked* revision), never a stored flag; unconfirmed counts as stale. Any authoring change **auto-syncs**: push if connected, else scan+connect+push, else the device goes **yellow** in Devices with a "Sync now" retry. Yellow only after an attempt settles (spinner while in flight); it's informational, never red. A withheld §8.9 loosening is **not** stale. Sync state, liveness (§8.7), and pending changes (§8.9) are three distinct indicators.
- **Calibration (§8.5):** ship the guided walk-around flow with a **donut progress ring** (live Prox Score shown inside), driven best-effort by **phone-IMU movement time**.
- **Scope this pass:** fingerprint upload = debug-only stub; **Mode C deferred** but design the phone-distance UI to accommodate it later; guided calibration shipped.
- **Tech (§2, §9):** state management = agent's choice (be consistent); persistence = **`drift` (mandatory) for the pending-changes queue, pass ledger, and audit trail**, `shared_preferences` for simple prefs/device records; notifications = `flutter_local_notifications`, local-only; minimum platform versions unpinned (use the APIs you need — revisit later).

## 14. Remaining items to verify (not blockers)

- **Sunrise Lock mechanics — resolved in firmware spec v0.6 (§5.4.4):** window-start unworn beeping + per-event `donningGraceS`. The template builder's parameter set is final (§8.8); firmware *implementation* is pending, tracked in firmware §0.1 as part of the lockstep batch.
- The precise **completion heuristic** for guided calibration (IMU movement-time target + duration) — the UI ships regardless; tune the threshold during testing (§8.5).
- **Status-characteristic version prefix (deferred — not in v1.3, tracked in firmware §10.1).** Watch Status (`…0016`) and anchor WiFi Status (`…000E`) carry no version/length prefix, so each field addition is an exact-byte lockstep change with no graceful degradation (v0.8 adds `schedule_crc` — the third such growth to Watch Status). Fine while every device is flashed together; if staged/OTA rollouts ever create mixed-firmware fleets, add a 1-byte version to both so older parsers can skip unknown trailing fields. When that lands, the app's status parsers become version-aware; until then they assume the current layout.


