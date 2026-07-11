import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/models/automation_model.dart';
import 'package:impulse_app/templates/template_registry.dart';

void main() {
  final registry = TemplateRegistry.seeded();
  int counter = 0;
  String fakeUuid() => 'uuid-${counter++}';

  test('seed registry has the four v1 templates + all are onboarders', () {
    expect(registry.all.length, 4);
    expect(registry.onboarders.length, 4);
    expect(registry.byId('sunrise_lock'), isNotNull);
  });

  test('onboarder quick-forms are at most 3 questions', () {
    for (final t in registry.onboarders) {
      expect(t.quickFormParams.length, lessThanOrEqualTo(3),
          reason: '${t.id} quick-form too long');
    }
  });

  test('Sunrise Lock expands to a getAway block with grace + beep anchor', () {
    final t = registry.byId('sunrise_lock')!;
    final blocks = t.expand(
      {
        'wakeTime': {'hour': 6, 'minute': 30},
        'graceSeconds': 300,
        'firmness': 'strictBoth',
        'bedroomAnchor': 'bedroom-uuid',
        'nightstandAnchor': 'nightstand-uuid',
      },
      instanceId: 'inst-1',
      newUuid: fakeUuid,
    );
    expect(blocks.length, 1);
    final b = blocks.first;
    expect(b.criteria, Criteria.getAway);
    expect(b.donningGraceS, 300);
    expect(b.anchorId, 'bedroom-uuid');
    expect(b.beepAnchors, ['nightstand-uuid']);
    expect(b.origin, TemplateOrigin.sunriseLock);
    expect(b.templateInstanceId, 'inst-1');
    expect(b.anchorProfile, AnchorEnforcementProfile.hard);
  });

  test('UUID stability: re-expansion reuses provided slot UUIDs', () {
    final t = registry.byId('study_time')!;
    final first = t.expand(
      {'deskAnchor': 'desk'},
      instanceId: 'inst-2',
      newUuid: fakeUuid,
    );
    final reused = t.expand(
      {'deskAnchor': 'desk'},
      instanceId: 'inst-2',
      newUuid: fakeUuid,
      slotUuids: {'primary': first.first.id},
    );
    expect(reused.first.id, first.first.id);
  });

  test('reparse round-trips core params', () {
    final t = registry.byId('phone_free')!;
    final blocks = t.expand(
      {
        'startTime': {'hour': 21, 'minute': 0},
        'endTime': {'hour': 22, 'minute': 0},
        'dockAnchor': 'dock-uuid',
        'firmness': 'strictBoth',
      },
      instanceId: 'inst-3',
      newUuid: fakeUuid,
    );
    final params = t.reparse(blocks);
    expect(params['dockAnchor'], 'dock-uuid');
    expect(params['firmness'], 'strictBoth');
    expect((params['startTime'] as Map)['hour'], 21);
    expect(blocks.first.criteria, Criteria.phoneAway);
  });
}
