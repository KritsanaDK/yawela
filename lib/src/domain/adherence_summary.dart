import 'dose_occurrence.dart';

/// Aggregated adherence counts for a collection of dose occurrences.
final class AdherenceSummary {
  const AdherenceSummary({
    required this.taken,
    required this.skipped,
    required this.missed,
    required this.due,
  });

  final int taken;
  final int skipped;
  final int missed;
  final int due;

  int get completed => taken + skipped + missed;
  int get totalDue => completed + due;
  double get adherence => completed == 0 ? 0 : taken / completed;
}

/// Calculates adherence without depending on controllers or Flutter widgets.
AdherenceSummary summarizeAdherence(
  Iterable<DoseOccurrence> occurrences, {
  required DateTime now,
}) {
  var taken = 0;
  var skipped = 0;
  var missed = 0;
  var due = 0;

  for (final occurrence in occurrences) {
    switch (occurrence.effectiveState(now: now)) {
      case DoseEffectiveState.taken:
        taken += 1;
      case DoseEffectiveState.skipped:
        skipped += 1;
      case DoseEffectiveState.missed:
        missed += 1;
      case DoseEffectiveState.due:
        due += 1;
      case DoseEffectiveState.upcoming:
        break;
    }
  }

  return AdherenceSummary(
    taken: taken,
    skipped: skipped,
    missed: missed,
    due: due,
  );
}
