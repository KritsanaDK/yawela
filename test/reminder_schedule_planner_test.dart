import 'package:flutter_test/flutter_test.dart';
import 'package:yawela/src/domain/domain.dart';
import 'package:yawela/src/services/reminder_schedule_planner.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

Medication _medication({
  DateTime? startDate,
  DateTime? endDate,
  Iterable<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
  bool isActive = true,
}) {
  return Medication(
    id: 1,
    name: 'ยาทดสอบ',
    dosage: '1 เม็ด',
    colorValue: 0xFF00695C,
    reminderTimes: [ReminderTime(20, 30)],
    weekdays: weekdays,
    startDate: startDate ?? DateTime(2026, 8, 1),
    endDate: endDate,
    isActive: isActive,
  );
}

void main() {
  late tz.Location location;
  setUpAll(() {
    tz_data.initializeTimeZones();
    location = tz.getLocation('Asia/Bangkok');
  });

  group('ReminderSchedulePlanner', () {
    const planner = ReminderSchedulePlanner();

    test('uses a compact daily entry for an ongoing schedule', () {
      final now = tz.TZDateTime(location, 2026, 8, 29, 10);
      final entries = planner.build(
        [_medication()],
        location: location,
        now: now,
      );

      expect(entries, hasLength(1));
      expect(entries.single.repeat, ReminderRepeat.daily);
      expect(
        entries.single.nextOccurrence,
        tz.TZDateTime(location, 2026, 8, 29, 20, 30),
      );
    });

    test('future medication uses one-shot entries and never fires early', () {
      final now = tz.TZDateTime(location, 2026, 8, 29, 10);
      final startDate = DateTime(2026, 9, 1);
      final entries = planner.build(
        [_medication(startDate: startDate)],
        location: location,
        now: now,
      );

      expect(entries, isNotEmpty);
      expect(
        entries.every((entry) => entry.repeat == ReminderRepeat.none),
        isTrue,
      );
      expect(
        entries.first.nextOccurrence,
        tz.TZDateTime(location, 2026, 9, 1, 20, 30),
      );
    });

    test('end date is inclusive and prevents later entries', () {
      final now = tz.TZDateTime(location, 2026, 8, 29, 10);
      final entries = planner.build(
        [_medication(endDate: DateTime(2026, 8, 30))],
        location: location,
        now: now,
      );

      expect(entries, hasLength(2));
      expect(entries.last.nextOccurrence.day, 30);
      expect(
        entries.every((entry) => entry.repeat == ReminderRepeat.none),
        isTrue,
      );
    });

    test('inactive medication produces no entries', () {
      final now = tz.TZDateTime(location, 2026, 8, 29, 10);
      final entries = planner.build(
        [_medication(isActive: false)],
        location: location,
        now: now,
      );

      expect(entries, isEmpty);
    });
  });
}
