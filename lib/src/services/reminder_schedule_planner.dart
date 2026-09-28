import 'package:timezone/timezone.dart' as tz;

import '../domain/domain.dart';

enum ReminderRepeat { none, daily, weekly }

/// A platform-independent reminder request produced from local medication data.
final class ReminderScheduleEntry {
  const ReminderScheduleEntry({
    required this.medication,
    required this.key,
    required this.nextOccurrence,
    required this.repeat,
  });

  final Medication medication;
  final String key;
  final tz.TZDateTime nextOccurrence;
  final ReminderRepeat repeat;
}

/// Converts medication rules into deterministic one-shot or repeating entries.
final class ReminderSchedulePlanner {
  const ReminderSchedulePlanner({this.finiteHorizonDays = 90})
    : assert(finiteHorizonDays > 0);

  final int finiteHorizonDays;

  List<ReminderScheduleEntry> build(
    List<Medication> medications, {
    required tz.Location location,
    tz.TZDateTime? now,
  }) {
    final current = now ?? tz.TZDateTime.now(location);
    final today = DateTime(current.year, current.month, current.day);
    final entries = <ReminderScheduleEntry>[];

    for (final medication in medications) {
      if (!_canSchedule(medication)) continue;

      final startsInFuture = medication.startDate.isAfter(today);
      if (medication.endDate != null || startsInFuture) {
        _addOneShotEntries(
          entries,
          medication,
          current: current,
          today: today,
          location: location,
        );
      } else {
        _addRepeatingEntries(
          entries,
          medication,
          current: current,
          location: location,
        );
      }
    }

    return entries;
  }

  bool _canSchedule(Medication medication) {
    return medication.isActive &&
        !medication.isArchived &&
        medication.id != null &&
        medication.weekdays.isNotEmpty &&
        medication.reminderTimes.isNotEmpty;
  }

  void _addOneShotEntries(
    List<ReminderScheduleEntry> entries,
    Medication medication, {
    required tz.TZDateTime current,
    required DateTime today,
    required tz.Location location,
  }) {
    final startsInFuture = medication.startDate.isAfter(today);
    var cursor = startsInFuture ? medication.startDate : today;
    final horizon = DateTime(
      cursor.year,
      cursor.month,
      cursor.day + finiteHorizonDays,
    );
    final endDate = medication.endDate;
    final finalDate = endDate != null && endDate.isBefore(horizon)
        ? endDate
        : horizon;

    while (!cursor.isAfter(finalDate)) {
      if (medication.weekdays.contains(cursor.weekday)) {
        for (final time in medication.reminderTimes) {
          final occurrence = tz.TZDateTime(
            location,
            cursor.year,
            cursor.month,
            cursor.day,
            time.hour,
            time.minute,
          );
          if (occurrence.isAfter(current)) {
            entries.add(
              ReminderScheduleEntry(
                medication: medication,
                key: _oneShotKey(medication, time, cursor),
                nextOccurrence: occurrence,
                repeat: ReminderRepeat.none,
              ),
            );
          }
        }
      }
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
  }

  void _addRepeatingEntries(
    List<ReminderScheduleEntry> entries,
    Medication medication, {
    required tz.TZDateTime current,
    required tz.Location location,
  }) {
    if (medication.weekdays.length == DateTime.daysPerWeek) {
      for (final time in medication.reminderTimes) {
        entries.add(
          ReminderScheduleEntry(
            medication: medication,
            key: '${medication.id}|${time.minutesSinceMidnight}|daily',
            nextOccurrence: _nextOccurrence(
              time,
              current: current,
              location: location,
              notBefore: medication.startDate,
            ),
            repeat: ReminderRepeat.daily,
          ),
        );
      }
      return;
    }

    final weekdays = medication.weekdays.toList()..sort();
    for (final time in medication.reminderTimes) {
      for (final weekday in weekdays) {
        entries.add(
          ReminderScheduleEntry(
            medication: medication,
            key: '${medication.id}|${time.minutesSinceMidnight}|$weekday',
            nextOccurrence: _nextOccurrence(
              time,
              current: current,
              location: location,
              notBefore: medication.startDate,
              weekday: weekday,
            ),
            repeat: ReminderRepeat.weekly,
          ),
        );
      }
    }
  }

  tz.TZDateTime _nextOccurrence(
    ReminderTime time, {
    required tz.TZDateTime current,
    required tz.Location location,
    required DateTime notBefore,
    int? weekday,
  }) {
    final today = DateTime(current.year, current.month, current.day);
    final firstDate = notBefore.isAfter(today) ? notBefore : today;
    var candidate = tz.TZDateTime(
      location,
      firstDate.year,
      firstDate.month,
      firstDate.day,
      time.hour,
      time.minute,
    );

    if (!candidate.isAfter(current)) {
      candidate = _atTimeOnNextDay(candidate, time, location);
    }
    while (weekday != null && candidate.weekday != weekday) {
      candidate = _atTimeOnNextDay(candidate, time, location);
    }
    return candidate;
  }

  tz.TZDateTime _atTimeOnNextDay(
    tz.TZDateTime date,
    ReminderTime time,
    tz.Location location,
  ) {
    return tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day + 1,
      time.hour,
      time.minute,
    );
  }

  String _oneShotKey(Medication medication, ReminderTime time, DateTime date) {
    return '${medication.id}|${time.minutesSinceMidnight}|'
        '${date.year}-${date.month}-${date.day}';
  }
}
