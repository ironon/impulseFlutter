/// Per-device sync state for the Devices screen (§8.16). Distinct from liveness
/// (§8.7 — is the device online) and from pending changes (§8.9 — a deliberately
/// withheld loosening). Three independent indicators; never collapse them.
enum SyncStatus {
  /// Everything the app has pushed is acked. Normal (green/neutral) card.
  synced,

  /// A push/scan attempt is in flight — show a spinner + "Syncing…", never
  /// yellow. Yellow is only for a *settled* stale state.
  syncing,

  /// The device is behind and not currently reachable — yellow + a reason.
  /// Informational, not an error (never red).
  stale,
}

class DeviceSyncState {
  final SyncStatus status;

  /// Human-readable classes that are behind (e.g. "schedule", "settings",
  /// "networks"). Empty when synced. Aggregate honestly — don't enumerate raw
  /// revisions.
  final List<String> behindClasses;

  const DeviceSyncState({
    required this.status,
    this.behindClasses = const [],
  });

  static const synced = DeviceSyncState(status: SyncStatus.synced);
  static const syncing = DeviceSyncState(status: SyncStatus.syncing);

  bool get isStale => status == SyncStatus.stale;
  bool get isSyncing => status == SyncStatus.syncing;

  /// One-line reason for the card subtitle.
  String reason({required bool isWatch}) {
    switch (status) {
      case SyncStatus.syncing:
        return 'Syncing…';
      case SyncStatus.synced:
        return 'Up to date';
      case SyncStatus.stale:
        final n = behindClasses.length;
        final what = n <= 1
            ? (behindClasses.isEmpty ? 'changes' : behindClasses.first)
            : '$n changes';
        return isWatch
            ? 'Waiting to reach your watch — $what'
            : 'Anchor offline — will sync $what when reachable';
    }
  }
}
