import 'reminder_time.dart';

const Object _notProvided = Object();

/// A locally stored medicine and its repeating reminder rule.
///
/// [weekdays] follows [DateTime.weekday] (`1` Monday through `7` Sunday).
/// [startDate] and [endDate] are local calendar dates; time components are
/// discarded. Instant fields such as [createdAt] are stored in UTC.
final class Medication {
  Medication({
    this.id,
    required String name,
    required String dosage,
    String instructions = '',
    String notes = '',
    required this.colorValue,
    required Iterable<ReminderTime> reminderTimes,
    required Iterable<int> weekdays,
    required DateTime startDate,
    DateTime? endDate,
    this.isActive = true,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : name = name.trim(),
       dosage = dosage.trim(),
       instructions = instructions.trim(),
       notes = notes.trim(),
       reminderTimes = _normalizeTimes(reminderTimes),
       weekdays = _normalizeWeekdays(weekdays),
       startDate = dateOnly(startDate),
       endDate = endDate == null ? null : dateOnly(endDate),
       archivedAt = archivedAt?.toUtc(),
       createdAt = (createdAt ?? DateTime.now()).toUtc(),
       updatedAt = (updatedAt ?? createdAt ?? DateTime.now()).toUtc() {
    if (this.name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Medication name is required.');
    }
    if (this.endDate != null && this.endDate!.isBefore(this.startDate)) {
      throw ArgumentError.value(
        endDate,
        'endDate',
        'End date cannot be before start date.',
      );
    }
  }

  final int? id;
  final String name;
  final String dosage;
  final String instructions;
  final String notes;
  final int colorValue;
  final List<ReminderTime> reminderTimes;
  final Set<int> weekdays;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isArchived => archivedAt != null;

  /// Whether this medication is expected on [localDate].
  bool occursOn(DateTime localDate) {
    final date = dateOnly(localDate);
    return !isArchived &&
        isActive &&
        !date.isBefore(startDate) &&
        (endDate == null || !date.isAfter(endDate!)) &&
        weekdays.contains(date.weekday);
  }

  Medication copyWith({
    int? id,
    String? name,
    String? dosage,
    String? instructions,
    String? notes,
    int? colorValue,
    Iterable<ReminderTime>? reminderTimes,
    Iterable<int>? weekdays,
    DateTime? startDate,
    Object? endDate = _notProvided,
    bool? isActive,
    Object? archivedAt = _notProvided,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Medication(
      id: id ?? this.id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      instructions: instructions ?? this.instructions,
      notes: notes ?? this.notes,
      colorValue: colorValue ?? this.colorValue,
      reminderTimes: reminderTimes ?? this.reminderTimes,
      weekdays: weekdays ?? this.weekdays,
      startDate: startDate ?? this.startDate,
      endDate: identical(endDate, _notProvided)
          ? this.endDate
          : endDate as DateTime?,
      isActive: isActive ?? this.isActive,
      archivedAt: identical(archivedAt, _notProvided)
          ? this.archivedAt
          : archivedAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static List<ReminderTime> _normalizeTimes(Iterable<ReminderTime> values) {
    final result = values.toSet().toList()..sort();
    return List.unmodifiable(result);
  }

  static Set<int> _normalizeWeekdays(Iterable<int> values) {
    final result = values.toSet();
    for (final weekday in result) {
      if (weekday < DateTime.monday || weekday > DateTime.sunday) {
        throw RangeError.range(
          weekday,
          DateTime.monday,
          DateTime.sunday,
          'weekdays',
        );
      }
    }
    return Set.unmodifiable(result);
  }
}
