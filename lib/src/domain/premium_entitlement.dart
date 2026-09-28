/// A locally cached, verified lifetime unlock.
final class PremiumEntitlement {
  const PremiumEntitlement({
    required this.productId,
    required this.transactionId,
    required this.grantedAt,
  });

  final String productId;
  final String transactionId;
  final DateTime grantedAt;
}

/// Raised when a free user attempts to keep more active medicine profiles than
/// the locally enforced free allowance.
final class MedicationLimitReached implements Exception {
  const MedicationLimitReached({required this.limit});

  final int limit;

  @override
  String toString() =>
      'MedicationLimitReached: the free plan allows $limit medicines.';
}
