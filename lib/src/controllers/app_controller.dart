import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/data.dart';
import '../domain/domain.dart';
import '../services/notification_service.dart';
import '../services/purchase_service.dart';

/// Coordinates local persistence, scheduled notifications and the cached store
/// entitlement. UI code only talks to this object; SQLite remains authoritative.
class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.reminders,
    required this.purchases,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final MedicationRepository repository;
  final ReminderService reminders;
  final PurchaseService purchases;
  final DateTime Function() _now;

  static const String _lastTimeZoneSettingKey = 'last_reminder_time_zone';

  final List<Medication> _medications = [];
  final List<DoseOccurrence> _occurrences = [];

  bool _isLoading = true;
  int _pendingOperations = 0;
  bool _initialized = false;
  bool _disposed = false;
  Object? _startupError;
  ReminderSyncResult? _reminderSync;

  bool get isLoading => _isLoading;
  bool get isBusy => _pendingOperations > 0;
  bool get isPremium => purchases.isPremium;
  int get freeMedicationLimit => repository.freeMedicationLimit;
  Object? get startupError => _startupError;
  ReminderSyncResult? get reminderSync => _reminderSync;
  DateTime get now => _now();

  List<Medication> get medications => List.unmodifiable(_medications);

  List<Medication> get currentMedications => List.unmodifiable(
    _medications.where((medication) => !medication.isArchived),
  );

  List<DoseOccurrence> get occurrences => List.unmodifiable(_occurrences);

  List<DoseOccurrence> get todayOccurrences {
    final current = _now().toLocal();
    final start = DateTime(current.year, current.month, current.day);
    final end = start.add(const Duration(days: 1));
    return _occurrences
        .where((occurrence) {
          final scheduled = occurrence.scheduledAt.toLocal();
          return !scheduled.isBefore(start) && scheduled.isBefore(end);
        })
        .toList(growable: false);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    purchases.addListener(_handlePurchaseChange);

    try {
      await repository.initialize();
      await _reloadData();

      try {
        await reminders.initialize();
        await _syncReminders();
      } on Object catch (error, stackTrace) {
        _logReminderFailure(error, stackTrace);
      }

      // Cached premium is loaded before the store query. Store failures never
      // block access to the offline medicine data.
      unawaited(
        purchases.initialize().catchError((Object error, StackTrace stack) {
          if (kDebugMode) debugPrint('Purchase initialization: $error\n$stack');
        }),
      );
    } on Object catch (error, stackTrace) {
      _startupError = error;
      if (kDebugMode) debugPrint('App startup failed: $error\n$stackTrace');
    } finally {
      _isLoading = false;
      _notifySafely();
    }
  }

  Future<void> retryStartup() async {
    _startupError = null;
    _isLoading = true;
    _initialized = false;
    purchases.removeListener(_handlePurchaseChange);
    _notifySafely();
    await initialize();
  }

  Future<void> refreshForResume() async {
    if (_isLoading || _startupError != null) return;
    await _runBusy(() async {
      await repository.refreshOccurrences();
      await _reloadData();
      await _syncReminders();
    });
  }

  Future<Medication> createMedication(Medication medication) {
    return _runBusy(() async {
      final created = await repository.createMedication(medication);
      await _afterMedicationMutation();
      return created;
    });
  }

  Future<Medication> updateMedication(Medication medication) {
    return _runBusy(() async {
      final updated = await repository.updateMedication(medication);
      await _afterMedicationMutation();
      return updated;
    });
  }

  Future<void> archiveMedication(Medication medication) async {
    final id = medication.id;
    if (id == null) return;
    await _runBusy(() async {
      await repository.archiveMedication(id);
      await _afterMedicationMutation();
    });
  }

  Future<void> setMedicationActive(Medication medication, bool active) async {
    final id = medication.id;
    if (id == null) return;
    await _runBusy(() async {
      if (active) {
        await repository.resumeMedication(id);
      } else {
        await repository.pauseMedication(id);
      }
      await _afterMedicationMutation();
    });
  }

  Future<void> markTaken(DoseOccurrence occurrence) =>
      _updateOccurrence(() => repository.markTaken(occurrence.id));

  Future<void> markSkipped(DoseOccurrence occurrence) =>
      _updateOccurrence(() => repository.markSkipped(occurrence.id));

  Future<void> undoOccurrence(DoseOccurrence occurrence) =>
      _updateOccurrence(() => repository.undoOccurrence(occurrence.id));

  Future<ReminderPermissionResult> requestReminderPermissions() {
    return _runBusy(() async {
      final result = await reminders.requestPermissions();
      await _syncReminders();
      return result;
    });
  }

  Future<void> resyncReminders() => _runBusy(_syncReminders);

  Future<void> _afterMedicationMutation() async {
    await _reloadData();
    await _syncReminders();
  }

  Future<void> _reloadData() async {
    final current = _now().toLocal();
    final today = DateTime(current.year, current.month, current.day);
    final from = today.subtract(const Duration(days: 30));
    final to = today.add(const Duration(days: 2));
    final medicationsFuture = repository.loadMedications();
    final occurrencesFuture = repository.loadOccurrences(from: from, to: to);
    final medications = await medicationsFuture;
    final occurrences = await occurrencesFuture;

    _medications
      ..clear()
      ..addAll(medications);
    _occurrences
      ..clear()
      ..addAll(occurrences);
    _notifySafely();
  }

  Future<void> _syncReminders() async {
    try {
      final result = await reminders.sync(_medications);
      await _reconcileOccurrenceTimeZone(result.timeZoneIdentifier);
      _reminderSync = result;
    } on Object catch (error, stackTrace) {
      _logReminderFailure(error, stackTrace);
    }
    _notifySafely();
  }

  Future<void> _reconcileOccurrenceTimeZone(String currentTimeZone) async {
    final previousTimeZone = await repository.readSetting(
      _lastTimeZoneSettingKey,
    );
    if (previousTimeZone == currentTimeZone) return;

    if (previousTimeZone != null) {
      await repository.rebuildFuturePendingOccurrences();
      await _reloadData();
    }
    await repository.writeSetting(_lastTimeZoneSettingKey, currentTimeZone);
  }

  Future<void> _updateOccurrence(Future<DoseOccurrence> Function() update) {
    return _runBusy(() async {
      await update();
      await _reloadData();
      // Replenish rolling one-shot reminders whenever the user records a dose.
      await _syncReminders();
    });
  }

  Future<T> _runBusy<T>(Future<T> Function() action) async {
    _pendingOperations += 1;
    _notifySafely();
    try {
      return await action();
    } finally {
      _pendingOperations -= 1;
      _notifySafely();
    }
  }

  void _logReminderFailure(Object error, StackTrace stackTrace) {
    if (kDebugMode) debugPrint('Reminder service: $error\n$stackTrace');
  }

  void _handlePurchaseChange() => _notifySafely();

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    purchases.removeListener(_handlePurchaseChange);
    purchases.dispose();
    reminders.dispose();
    unawaited(repository.close());
    super.dispose();
  }
}
