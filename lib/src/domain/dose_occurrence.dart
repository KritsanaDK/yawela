const Object _notProvided = Object();

/// The persisted user outcome for a scheduled dose.
enum DoseStatus { pending, taken, skipped }

/// A time-aware presentation state. Upcoming/due/missed are derived and are
/// deliberately not persisted so elapsed time cannot make the database stale.
enum DoseEffectiveState { upcoming, due, missed, taken, skipped }

/// One expected dose. Medication name and dosage are snapshots so history does
/// not change when the parent medicine is renamed or archived.
final class DoseOccurrence {
  const DoseOccurrence({
    required this.id,
    required this.medicationId,
    required this.scheduledAt,
    required this.medicationName,
    required this.dosage,
    this.status = DoseStatus.pending,
    this.actedAt,
  });

  final int id;
  final int medicationId;

  /// An absolute instant in UTC.
  final DateTime scheduledAt;
  final String medicationName;
  final String dosage;
  final DoseStatus status;

  /// The UTC instant of the latest explicit user action, if any.
  final DateTime? actedAt;

  DoseEffectiveState effectiveState({
    DateTime? now,
    Duration missedAfter = const Duration(hours: 2),
  }) {
    if (status == DoseStatus.taken) return DoseEffectiveState.taken;
    if (status == DoseStatus.skipped) return DoseEffectiveState.skipped;

    final current = (now ?? DateTime.now()).toUtc();
    final scheduled = scheduledAt.toUtc();
    if (current.isBefore(scheduled)) return DoseEffectiveState.upcoming;
    if (current.isAfter(scheduled.add(missedAfter))) {
      return DoseEffectiveState.missed;
    }
    return DoseEffectiveState.due;
  }

  DoseOccurrence copyWith({
    DoseStatus? status,
    Object? actedAt = _notProvided,
  }) {
    return DoseOccurrence(
      id: id,
      medicationId: medicationId,
      scheduledAt: scheduledAt,
      medicationName: medicationName,
      dosage: dosage,
      status: status ?? this.status,
      actedAt: identical(actedAt, _notProvided)
          ? this.actedAt
          : actedAt as DateTime?,
    );
  }
}
