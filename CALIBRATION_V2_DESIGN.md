# Calibration v2 — per-anchor, demonstrated near-zones (design + build plan)

**Status:** design finalized 2026-07-27, ready to implement. All decisions below are
made — implement as written; deviate only if the code contradicts an assumption.

**Branch:** `calibration-v2`, cut in each repo off the current calibration work
(the uncommitted Option-A + seen-anchors-fallback + diagnostics state — commit that
first, then branch). Four repos are involved: `proximity_engine`, `AnchorFirmware`,
`WatchFIrmware`, `impulse_app`.

---

## 0. Why (the problem this fixes)

The proximity **decision** is vector-based (Signal A correlation + Signal B
fingerprint) and correctly avoids raw RSSI thresholds. But the **self-supervised
training** bootstraps its "is this a NEAR sample?" labels from the watch→anchor RSSI
(`ANCHOR_NEAR_RSSI_THRESHOLD_DBM`). That single global RSSI number is:
- **fragile** — arm's length reads anywhere from −54 to −75 on this hardware, and
- **incapable of per-anchor tolerance** — a desk anchor wants a 1–3 ft near-zone; a
  home-gym anchor wants 6–10 ft. One global threshold cannot express both (raise it
  for the gym and the desk over-accepts; lower it and the gym never trains).

Observed on hardware: at −70 the gym-distance samples (self_rssi −73…−85) are
rejected so the gym never calibrates; at −85 a desk anchor trains on across-the-room
samples and blurs its zone.

**Fix:** replace RSSI-bootstrapped labels with **app-signaled calibration phases**
(the user physically demonstrates the near-zone), and give each anchor its **own
calibrated decision threshold** learned from the score gap between "inside the zone"
and "just past the edge." The zone's *size* is defined by how far the user walks
during the inside phase — so desk vs gym is handled by demonstration, and no RSSI
threshold survives in either training or the decision.

Signal A already scales to any zone for free (same room ⇒ high correlation), so this
is mostly about (a) removing the RSSI training gate and (b) a per-anchor threshold.

---

## 1. Design decisions (all final)

1. **Two labeled phases, app-driven.** Calibration is: **INSIDE** (user roams the
   zone they want counted as near — small for a desk, the whole room for a gym) then
   **EDGE** (user steps just past their tolerance and stands there / moves along the
   boundary). A short **FINALIZE** step computes and persists the threshold.

2. **No RSSI gate during calibration.** In the INSIDE phase every vector trains the
   fingerprint unconditionally (the app guarantees the label). `sample_is_unambiguous`
   / `ANCHOR_NEAR_RSSI_THRESHOLD_DBM` is **not** consulted for phase-labeled samples.
   (Keep the old RSSI-gated self-supervision only for *passive* enforcement-time
   training, phase = NONE — see decision 7 — so the anchor can still refine itself
   between calibrations without corrupting a demonstrated zone.)

3. **Per-anchor decision threshold, in score space.** The anchor records the score
   distribution seen during INSIDE and during EDGE, and sets
   `near_threshold = clamp( midpoint biased toward the inside floor )`. Concretely:
   `near_threshold = max( edge_p90 + MARGIN, min(inside_p10, edge_p90 + MARGIN) )`
   — i.e. put the cutoff just above the top of the edge scores, but never above the
   bottom of the inside scores; if the two overlap (bad calibration), fall back to a
   sane default and flag low-confidence. Persist per anchor in NVS.

4. **Enforcement uses the per-anchor threshold**, replacing the global
   `PROX_CONFIDENCE_THRESHOLD_U8` for anchors that have been calibrated. Uncalibrated
   anchors keep the global default. Keep the AMBIGUOUS band as
   `[near_threshold - HYST, near_threshold]` → resolves to the fail-safe-compliant
   side (existing §5.4.1 behavior).

5. **Phase is anchor state, set over BLE by the watch.** Because the watch reconnects
   per query (Option A), the anchor must remember the current phase across
   connections. Add a **new anchor characteristic `Calibration Mode` (`…000F`)**:
   `[phase u8]` where 0 NONE, 1 INSIDE, 2 EDGE, 3 FINALIZE, 4 ABORT. The watch writes
   it (write-with-response) at the start of each phase. On FINALIZE the anchor
   computes+persists the threshold and returns it in the response
   (`0x01 [near_threshold u8][inside_n u16][edge_n u16][confidence u8]`); on ABORT it
   discards the in-progress calibration stats (keeps any prior persisted threshold).

6. **Watch calibration protocol gains phases.** `WATCH_CALIB_CTRL_CHAR_UUID` START
   payload gains a phase byte the app sets; the watch, while bursting, writes the
   anchor's `…000F` Calibration Mode to match before each vector submit, and forwards
   the FINALIZE result frame to the app in its calib progress notification. The
   burst-only-while-phone-disconnected rule (Option A) is unchanged.

7. **Passive enforcement-time training stays, but conservative.** When phase == NONE
   (normal enforcement), keep the existing RSSI-gated self-supervised update so an
   anchor keeps sharpening between calibrations. This is the ONLY remaining use of
   `ANCHOR_NEAR_RSSI_THRESHOLD_DBM`; set it back to a strict value (**−68**) so
   passive training only reinforces genuinely-close samples and never widens a
   demonstrated zone. (The gym's wide zone is established by the INSIDE phase, not by
   passive training.)

8. **App tolerance presets are guidance, not numbers.** The app offers the user a
   framing per anchor ("tight — desk/nightstand" vs "roomy — gym/room") that only
   changes the *instructions* ("stay within arm's reach" vs "cover the whole space")
   and the suggested INSIDE duration. The actual zone is whatever they walk. No
   tolerance number is sent to firmware.

9. **Fingerprint variance is fine for wide zones.** A large INSIDE zone makes each
   device's Welford variance large (broad Gaussian, less discriminative Signal B),
   but Signal A (correlation to the anchor's live scan) still separates in-room from
   out-of-room. Do not add per-zone variance hacks; rely on the calibrated threshold.

10. **Backward compatibility is out of scope** (consistent with the batch). All three
    devices reflash together; the app probes `…000F` and falls back to the old
    single-phase calibration + global threshold if the characteristic is absent.

---

## 2. Per-repo changes

### 2.1 `proximity_engine` (shared algorithm — the core)
File: `src/proximity.cpp`, `src/proximity.h`.

- **Phase-labeled training entry point.** Add
  `int prox_train_labeled(const ProxScanVector* v, int is_inside)` (or extend
  `prox_maybe_update_fingerprint` with a `label` arg): when `is_inside`, skip the
  score/RSSI/unambiguous gates and fold the vector in at full weight; return accepted.
- **Score-stat accumulators for calibration.** Add two running collectors
  (inside, edge) of the *score* (`ProxScoreResult.score`) — keep enough to get
  p10/p90 cheaply (either a small reservoir or a fixed-bucket histogram over 0..255;
  a 32-bucket histogram is plenty and O(1) memory). API:
  `void prox_calib_reset(void);`
  `void prox_calib_add(int is_inside, uint8_t score);`
  `uint8_t prox_calib_finalize(uint16_t* inside_n, uint16_t* edge_n, uint8_t* confidence);`
  finalize returns the computed `near_threshold` per decision 3 and clears the
  collectors.
- **Per-anchor threshold storage + use.** Add
  `void prox_set_near_threshold(uint8_t thr /*0=uncalibrated → use global*/);`
  `uint8_t prox_get_near_threshold(void);` and make `prox_interpret_score()` (watch
  side) / the anchor's NEAR/AWAY decision use it when non-zero. Persist alongside the
  fingerprint NVS blob (bump the blob format: prepend a 1-byte version + the
  threshold; keep reading the old format as version 0 / threshold 0).
- Keep the existing RSSI-gated `prox_maybe_update_fingerprint` for phase==NONE
  passive training. Keep the reason/self_rssi diagnostics (already added).
- **Set `ANCHOR_NEAR_RSSI_THRESHOLD_DBM` to −68** (decision 7). Note: this const is
  currently −85 (a manual test change) — revert intent is captured here.

### 2.2 `AnchorFirmware` (`src/main.cpp`)
- **New GATT characteristic `Calibration Mode` `…000F`** (Write w/Resp) —
  `ANCHOR_CALIB_MODE_CHAR_UUID = "4A0F000F-..."`. Callback stores `g_calib_phase`
  (0..4). On INSIDE→set phase; on EDGE→set phase; on FINALIZE→call
  `prox_calib_finalize`, `prox_set_near_threshold`, persist, respond with the result
  frame (decision 5); on ABORT→`prox_calib_reset`.
- **Route the prox-vector write by phase.** In `ProxVectorCallback::onWrite` (already
  computes score + trains): if `g_calib_phase==INSIDE` → `prox_train_labeled(v,1)` +
  `prox_calib_add(1, score)`; if `EDGE` → `prox_calib_add(0, score)` (no training);
  if `NONE` → existing `prox_maybe_update_fingerprint` passive path. Keep the
  diagnostic log; add `phase=` to it.
- **Enforcement decision** (`anchor`-side NEAR/AWAY, and the score the anchor stores)
  uses `prox_get_near_threshold()` when set. Persist threshold via the extended
  fingerprint NVS blob.
- Load persisted threshold on boot; `prox_set_near_threshold` from it.

### 2.3 `WatchFIrmware` (`src/main.cpp`)
- **`WATCH_CALIB_CTRL_CHAR` START gains a phase byte:** `[0x01][uuid16][dur u16][phase u8]`
  (phase 1 INSIDE / 2 EDGE). The app drives phase transitions by writing START again
  with a new phase (or add opcodes `0x02 FINALIZE`, `0x03 ABORT`, keeping `0x00` STOP).
- **Watch sets the anchor's `…000F` before submitting vectors.** In `calib_burst_once`
  (or `prox_query_anchor` when in a calib session), after connecting, write the
  anchor's Calibration Mode char = current phase, then submit the vector. On FINALIZE,
  write phase=FINALIZE, read the result frame, and surface it in the calib progress
  notification (extend the 9-byte progress frame or add a trailing result block).
- Keep Option A (query only while phone disconnected) and the seen-anchors fallback
  (`find_anchor_ble_addr`) exactly as they are.
- Add the `…000F` UUID next to the other anchor char UUIDs.

### 2.4 `impulse_app`
- **`ble_constants.dart`:** add `anchorCalibModeCharUuid = '4a0f000f-...'`.
- **`watch_service.dart`:** `startCalibration` gains a `phase` arg; add
  `setCalibrationPhase(...)` / `finalizeCalibration()` helpers that write the phased
  START / FINALIZE opcodes; extend `CalibrationProgress` to carry the finalize result
  (near_threshold, inside_n, edge_n, confidence).
- **`calibration_screen.dart`:** replace the single walk-around with a **stepper**:
  (1) intro + tolerance framing (decision 8), (2) **INSIDE** — "move through your
  near-zone" with the elapsed ring (Option A: disconnect, time-based, reconnect to
  advance), (3) **EDGE** — "step just past your limit and stand there", (4)
  **FINALIZE** — reconnect, send FINALIZE, show the result ("your desk zone is set —
  N inside / M edge samples, confidence X"). Low-confidence (overlap) → offer redo.
  Keep the reconnect-to-read pattern already built for Option A.
- Anchor card: show "calibrated ✓ (threshold N)" vs "not calibrated" from `…000E`
  or a status read; offer re-calibrate.

---

## 3. Wire-format summary (lockstep, all reflashed together)
- New anchor char `…000F Calibration Mode` (Write w/Resp): `[phase u8]`; FINALIZE
  resp `0x01 [near_threshold u8][inside_n u16][edge_n u16][confidence u8]`.
- Watch calib ctrl START: append `[phase u8]`; add FINALIZE/ABORT opcodes.
- Anchor fingerprint NVS blob: prepend `[version u8=1][near_threshold u8]`.
- `ANCHOR_NEAR_RSSI_THRESHOLD_DBM` → −68 (passive-only).

## 4. Testing
- Desk anchor: INSIDE at desk (1–3 ft) only; EDGE at 5–6 ft. Confirm sitting at desk
  reads NEAR, standing 6 ft away reads AWAY. Threshold persists across reboot.
- Gym anchor: INSIDE roaming the whole ~10 ft space; EDGE in the doorway/hall.
  Confirm anywhere in the gym reads NEAR, the next room reads AWAY.
- Regression: an uncalibrated anchor still works on the global threshold; enforcement
  proximity queries (phone disconnected) unaffected; no `ble_hs_timer_exp` crash.
- Watch the anchor's `[PROX] Query ... phase=P accepted=A` and the FINALIZE frame.

## 5. Execution notes
- Implement engine first (unit-testable logic: histogram → threshold), then anchor,
  then watch, then app. Build each firmware with `~/.platformio/penv/bin/pio run`;
  app with `flutter analyze` + `flutter test`.
- This is spawnable as a subagent job: point it at this file, one repo at a time,
  building after each. Keep the calibration debug logs until it's verified, then strip
  (`[PROX]`/`[CALIB]`/`[HTTP-RAW]`) as noted in the batch cleanup.
