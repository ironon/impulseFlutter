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
  static bool get debugWriteToolsEnabled => !kReleaseMode || _forceDebugTools;
}
