import 'package:flutter_test/flutter_test.dart';
import 'package:yawela/src/domain/domain.dart';

DoseOccurrence _occurrence({
  required int id,
  required DateTime scheduledAt,
  DoseStatus status = DoseStatus.pending,
}) {
  return DoseOccurrence(
    id: id,
    medicationId: 1,
    scheduledAt: scheduledAt,
    medicationName: 'ยาทดสอบ',
    dosage: '1 เม็ด',
    status: status,
  );
}

void main() {
  group('ReminderTime', () {
    test('rejects invalid values in release-safe code', () {
      expect(() => ReminderTime(-1, 0), throwsRangeError);
      expect(() => ReminderTime(24, 0), throwsRangeError);
      expect(() => ReminderTime(8, 60), throwsRangeError);
    });

    test('formats a valid value as 24-hour time', () {
      expect(ReminderTime(8, 5).toString(), '08:05');
    });
  });

  test('summarizeAdherence counts only doses that are due', () {
    final now = DateTime.utc(2026, 8, 29, 12);
    final summary = summarizeAdherence([
      _occurrence(
        id: 1,
        scheduledAt: DateTime.utc(2026, 8, 29, 8),
        status: DoseStatus.taken,
      ),
      _occurrence(
        id: 2,
        scheduledAt: DateTime.utc(2026, 8, 29, 9),
        status: DoseStatus.skipped,
      ),
      _occurrence(id: 3, scheduledAt: DateTime.utc(2026, 8, 29, 8)),
      _occurrence(id: 4, scheduledAt: DateTime.utc(2026, 8, 29, 11)),
      _occurrence(id: 5, scheduledAt: DateTime.utc(2026, 8, 29, 13)),
    ], now: now);

    expect(summary.taken, 1);
    expect(summary.skipped, 1);
    expect(summary.missed, 1);
    expect(summary.due, 1);
    expect(summary.completed, 3);
    expect(summary.totalDue, 4);
    expect(summary.adherence, closeTo(1 / 3, 0.0001));
  });
}
