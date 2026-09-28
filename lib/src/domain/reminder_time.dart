/// A wall-clock reminder time without a date or time zone.
///
/// Values are ordered by their position in the day and use 24-hour time.
final class ReminderTime implements Comparable<ReminderTime> {
  ReminderTime(this.hour, this.minute) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
  }

  factory ReminderTime.fromMinutesSinceMidnight(int value) {
    if (value < 0 || value >= minutesPerDay) {
      throw RangeError.range(value, 0, minutesPerDay - 1, 'value');
    }
    return ReminderTime(value ~/ 60, value % 60);
  }

  static const int minutesPerDay = 24 * 60;

  final int hour;
  final int minute;

  int get minutesSinceMidnight => (hour * 60) + minute;

  @override
  int compareTo(ReminderTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderTime && hour == other.hour && minute == other.minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
