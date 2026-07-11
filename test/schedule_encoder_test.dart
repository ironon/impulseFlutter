import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/models/automation_model.dart';
import 'package:impulse_app/utils/schedule_encoder.dart';

void main() {
  Automation event({Criteria criteria = Criteria.stayNear, int donning = 0}) =>
      Automation(
        id: '11223344-5566-7788-99aa-bbccddeeff00',
        referenceDate: DateTime.utc(2026, 1, 1),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 10, minute: 0),
        recurrenceType: RecurrenceType.daily,
        criteria: criteria,
        profile: EnforcementProfile.normalBuzz,
        donningGraceS: donning,
        anchorId: '11223344-5566-7788-99aa-bbccddeeff00',
        color: const Color(0xFF000000),
      );

  test('blob starts with format version byte 0x02', () {
    final blob = ScheduleEncoder.encodeBlob([]);
    expect(blob[0], 0x02);
    // event_count u16 = 0 follows the version byte.
    expect(blob[1], 0);
    expect(blob[2], 0);
  });

  test('phoneAway serializes as criteria index 4', () {
    expect(Criteria.phoneAway.index, 4);
  });

  test('donning_grace_s u16 is emitted after negate', () {
    final blob = ScheduleEncoder.encodeBlob([event(donning: 300)]);
    // version(1) + count(2) = offset 3 begins first event.
    // uuid(16) ref(8) start(2) end(2) rec(1) dow(1) dom(1) crit(1)
    // profile(1) anchorProfile(1) negate(1) => donning starts at:
    const donningOffset = 3 + 16 + 8 + 2 + 2 + 1 + 1 + 1 + 1 + 1 + 1 + 1;
    final low = blob[donningOffset];
    final high = blob[donningOffset + 1];
    expect(low | (high << 8), 300);
  });

  test('encodeWithCrc appends 4-byte CRC', () {
    final blob = ScheduleEncoder.encodeBlob([event()]);
    final withCrc = ScheduleEncoder.encodeWithCrc([event()]);
    expect(withCrc.length, blob.length + 4);
  });
}
