// Compile-time debug-tool gating (spec v2 §2A.4 / §8.13).
//
// This file exists so the write-capable debug tools can be removed from release
// binaries by the tree shaker rather than hidden at runtime. It is the whole
// release gate: the only call site is `debug_screen.dart`, which wraps
// `_WriteTools` in `if (BuildConfig.debugWriteToolsEnabled)`.
//
// Verified in this repo: `flutter analyze` / `flutter test` run in debug, where
// the getter is `true`, so the tools are visible there — do not judge "is this
// shipped?" from a test run.

import 'package:flutter/foundation.dart';

/// Compile-time build gating (§2A.4).
class BuildConfig {
  const BuildConfig._();

  /// Set in dev builds via `--dart-define=IMPULSE_DEBUG_TOOLS=true`.
  static const bool _forceDebugTools =
      bool.fromEnvironment('IMPULSE_DEBUG_TOOLS');

  /// Whether the debug menu's **write-capable** tools (manual characteristic
  /// write, force schedule re-push, fingerprint upload, time/clock writes) are
  /// available. These are an integrity risk — a one-tap bypass of §8.9 — so
  /// they are excluded from release builds. Read-only telemetry (decoded Watch
  /// Status, Prox Score, Dock Status, BLE log) may ship in release Advanced
  /// mode regardless.
  ///
  /// `kReleaseMode` is a compile-time const, so guarding write tools with this
  /// getter lets the tree-shaker drop them from release binaries entirely.
  ///
  /// Concretely: profile and debug builds (`flutter run`, `flutter test`) get
  /// the tools; `flutter build apk|ipa --release` does not, *unless* it is
  /// explicitly opted back in with
  /// `--dart-define=IMPULSE_DEBUG_TOOLS=true` — which is how a dev build can be
  /// produced from release-mode AOT when needed. Nothing else in lib/ reads
  /// `_forceDebugTools`.
  static bool get debugWriteToolsEnabled => !kReleaseMode || _forceDebugTools;
}
