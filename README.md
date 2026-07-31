# Impulse — Mobile App

The Flutter companion app for the Impulse watch and anchors. This is the calm side of the system: where clear-headed you designs the day, and then hands it off to hardware that will not renegotiate.

Full specification: **[MOBILE_APP_SPEC.md](MOBILE_APP_SPEC.md)**. Product framing: **[impulse_overview.md](../WatchFIrmware/impulse_overview.md)**.

---

## What it is

Impulse is a habit-enforcement system built on **self-binding**: you decide in advance what your day should look like, and the hardware holds you to it later, when a tireder and more impulsive version of you would rather not. Three parts — a watch, anchors placed around the home, and this app.

The app **designs and distributes**; it does not enforce. The watch is the root of trust and owns the schedule and the clock. That separation is the whole point: an enforcement mechanism running on the phone in your hand is one you can always win against.

## The two ideas worth understanding first

### Normal mode vs. Advanced mode

The firmware only ever deals in primitives: `getAway`, `stayNear`, `getOnWifi`, `getOffWifi`, `phoneAway` — each a time-windowed block with a firmness profile. **There is no "Sunrise Lock" in the firmware.**

- **Advanced mode** is the truthful view. You see and edit raw blocks exactly as the watch sees them, plus the debug menu.
- **Normal mode** (the default) is a friendlier layer of named templates — Sunrise Lock, Study Time, Gym Time, Phone-Free — that expand into those same blocks. Sunrise Lock is really a `getAway` from the bedroom anchor with beeping pointed at the nightstand anchor. Nothing more.

Templates live in a **registry**, not in the UI, and the Normal-mode surface is generated from it — so adding a template is an isolated addition rather than a UI rewrite. See [lib/templates/](lib/templates/).

### The self-binding delay

This is the integrity guarantee, and it's the feature most likely to look like a bug if you don't know it's deliberate.

**You can always make the system harder on yourself immediately. You cannot make it easier in the heat of the moment.** Edits are classified as tightening, loosening, or non-comparable; a pure tightening applies right away, and anything else is quarantined for ~24 hours. A settle window (user-configurable, 30–240 minutes, default 120) governs how long a change must sit before it counts. Non-comparable changes are treated as loosening, because that's the conservative direction.

That delay is the difference between a real exception and a 6am excuse. Emergency passes exist for the days you genuinely can't plan for, on a frequency you set in advance. Implementation: [lib/services/self_binding_policy.dart](lib/services/self_binding_policy.dart) and [lib/services/integrity_store.dart](lib/services/integrity_store.dart).

## What it does

- **Onboarding and pairing**, driven goal-first — you pick a problem ("I can't get out of bed") and it drives anchor placement from there.
- **A weekly commitment builder** with per-commitment firmness, from a nudge you can shrug off to a wake-up you can't.
- **Schedule distribution** to the watch over BLE GATT and to anchors over HTTP, with a pending-changes queue and a staleness marker so you can see what hasn't landed yet.
- **Device management** — anchor naming, identify-by-beep, WiFi credential provisioning, live status for which anchors are online and whether the watch is worn.
- **Proximity calibration** — walks the user through demonstrating the inside and the edge of an anchor's zone, and reports honestly when the two don't separate rather than silently producing a threshold that won't work.
- **Phone-distance sessions** (docking), the Mode B flow behind Phone-Free windows.
- **An Advanced-only debug menu** with raw Watch Status packets, live proximity and dock meters, and the BLE log.

## Layout

| Path | What's in it |
|---|---|
| [lib/services/](lib/services/) | The real logic. BLE transport, watch/anchor clients, self-binding and commitment policy, the integrity and sync stores, calibration. |
| [lib/templates/](lib/templates/) | Template registry and the v1 seed templates. |
| [lib/models/](lib/models/) | `automation_model.dart` holds the commitment model and the `Criteria` enum — the primitives the firmware actually understands. |
| [lib/screens/](lib/screens/) · [lib/widgets/](lib/widgets/) | UI. |
| [lib/utils/ble_constants.dart](lib/utils/ble_constants.dart) | GATT UUIDs. Must stay in lockstep with both firmwares. |
| [lib/utils/schedule_encoder.dart](lib/utils/schedule_encoder.dart) | The schedule wire format. |
| [lib/data/](lib/data/) | Drift database — transactional, timestamped, migration-safe, because it's the trust machinery. |
| [MOBILE_APP_SPEC.md](MOBILE_APP_SPEC.md) | The spec, including the full GATT contract and wire formats. |
| [CALIBRATION_V2_DESIGN.md](CALIBRATION_V2_DESIGN.md) | The per-anchor demonstrated-zone calibration design. |

## Build & test

```sh
flutter pub get
flutter test        # 62 tests
flutter run
```

Android and iOS targets are both configured; Android is the one actually exercised.

## Notes

- **Write-capable debug tools are compile-time excluded from release builds**, not runtime-gated. Without that, "push an empty schedule" or "jump the watch's clock past the window" is a one-tap bypass of the self-binding delay. Read-only telemetry ships in release Advanced mode. See [lib/utils/build_config.dart](lib/utils/build_config.dart).
- **Capabilities that were cut:** app-blocking and uninstall-detection. Neither survived contact with what the mobile platforms allow. Don't reintroduce claims about them anywhere in the app copy.
- WiFi passwords go in `flutter_secure_storage`, never `shared_preferences`.

## Related repos

- [`WatchFirmware`](../WatchFIrmware/README.md) — the watch; root of trust, owns the schedule.
- [`AnchorFirmware`](../AnchorFirmware/README.md) — the anchors; define places, enforce in the room.
- [`proximity_engine`](../proximity_engine/README.md) — the shared BLE proximity engine both firmwares run.
