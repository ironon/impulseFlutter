import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:impulse_app/services/sync_state_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh device with no acks reads behind once a class is bumped', () async {
    final s = SyncStateStore();
    await s.loadCurrent();
    await s.loadDevice('watch-1');
    // Nothing edited yet → not behind.
    expect(s.isBehind('watch-1', SyncClass.schedule), isFalse);
    await s.bump(SyncClass.schedule);
    // Edited but not acked → behind (pessimistic).
    expect(s.isBehind('watch-1', SyncClass.schedule), isTrue);
  });

  test('acking clears behind; a later edit makes it behind again', () async {
    final s = SyncStateStore();
    await s.loadCurrent();
    await s.loadDevice('watch-1');
    await s.bump(SyncClass.watchSettings);
    await s.setAcked('watch-1', SyncClass.watchSettings);
    expect(s.isBehind('watch-1', SyncClass.watchSettings), isFalse);
    await s.bump(SyncClass.watchSettings);
    expect(s.isBehind('watch-1', SyncClass.watchSettings), isTrue);
  });

  test('markBehind forces stale even after an optimistic ack (CRC mismatch)', () async {
    final s = SyncStateStore();
    await s.loadCurrent();
    await s.loadDevice('anchor-1');
    await s.bump(SyncClass.schedule);
    await s.setAcked('anchor-1', SyncClass.schedule); // believed pushed
    expect(s.isBehind('anchor-1', SyncClass.schedule), isFalse);
    // Device's reported CRC disagreed → prove it's actually behind (§8.16).
    await s.markBehind('anchor-1', SyncClass.schedule);
    expect(s.isBehind('anchor-1', SyncClass.schedule), isTrue);
  });

  test('acked revisions persist and reload; absent device reads stale', () async {
    final s1 = SyncStateStore();
    await s1.loadCurrent();
    await s1.loadDevice('watch-1');
    await s1.bump(SyncClass.schedule);
    await s1.setAcked('watch-1', SyncClass.schedule);

    // New instance (same backing prefs) — current + watch-1 acks reload.
    final s2 = SyncStateStore();
    await s2.loadCurrent();
    await s2.loadDevice('watch-1');
    expect(s2.isBehind('watch-1', SyncClass.schedule), isFalse);

    // A device that never acked (e.g. after reinstall/new anchor) reads stale.
    await s2.loadDevice('anchor-99');
    expect(s2.isBehind('anchor-99', SyncClass.schedule), isTrue);
  });

  test('per-anchor keys are independent', () async {
    final s = SyncStateStore();
    await s.loadCurrent();
    final kA = SyncClass.anchorKey(SyncClass.anchorSettings, 'aaa');
    final kB = SyncClass.anchorKey(SyncClass.anchorSettings, 'bbb');
    await s.loadDevice('aaa');
    await s.loadDevice('bbb');
    await s.bump(kA);
    expect(s.isBehind('aaa', kA), isTrue);
    expect(s.isBehind('bbb', kB), isFalse);
  });
}
