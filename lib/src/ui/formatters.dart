import 'package:flutter/material.dart';

import '../domain/domain.dart';

const weekdayShortLabels = <int, String>{
  DateTime.monday: 'จ.',
  DateTime.tuesday: 'อ.',
  DateTime.wednesday: 'พ.',
  DateTime.thursday: 'พฤ.',
  DateTime.friday: 'ศ.',
  DateTime.saturday: 'ส.',
  DateTime.sunday: 'อา.',
};

const weekdayLongLabels = <int, String>{
  DateTime.monday: 'จันทร์',
  DateTime.tuesday: 'อังคาร',
  DateTime.wednesday: 'พุธ',
  DateTime.thursday: 'พฤหัสบดี',
  DateTime.friday: 'ศุกร์',
  DateTime.saturday: 'เสาร์',
  DateTime.sunday: 'อาทิตย์',
};

Widget build24HourMediaQuery(BuildContext context, Widget? child) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
    child: child ?? const SizedBox.shrink(),
  );
}

String formatReminderTime(BuildContext context, ReminderTime value) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: value.hour, minute: value.minute),
    alwaysUse24HourFormat: true,
  );
}

String formatOccurrenceTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: local.hour, minute: local.minute),
    alwaysUse24HourFormat: true,
  );
}

String formatMedicationDays(Set<int> weekdays) {
  if (weekdays.length == DateTime.daysPerWeek) return 'ทุกวัน';
  if (_sameDays(weekdays, const {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  })) {
    return 'วันจันทร์–ศุกร์';
  }
  if (_sameDays(weekdays, const {DateTime.saturday, DateTime.sunday})) {
    return 'วันเสาร์–อาทิตย์';
  }

  final ordered = weekdays.toList()..sort();
  return ordered.map((day) => weekdayShortLabels[day] ?? '').join(' ');
}

bool _sameDays(Set<int> left, Set<int> right) =>
    left.length == right.length && left.containsAll(right);

DateTime startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime endOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
