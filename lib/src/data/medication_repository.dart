import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../domain/domain.dart';
import 'app_database.dart';

/// SQLite-backed source of truth for medicines, expected doses and the cached
/// lifetime entitlement.
///
/// All ranges use an inclusive [from] and exclusive [to]. Calendar schedules
/// are interpreted in the device's current local time zone, while instants are
/// persisted as UTC epoch milliseconds.
final class MedicationRepository {
  MedicationRepository({
    AppDatabase? database,
    DateTime Function()? now,
    this.freeMedicationLimit = AppConfig.freeMedicationLimit,
    this.materializationDays = 60,
  }) : assert(freeMedicationLimit > 0),
       assert(materializationDays >= 60),
       _database = database ?? AppDatabase(),
       _now = now ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _now;
  final int freeMedicationLimit;
  final int materializationDays;

  AppDatabase get database => _database;

  /// Opens/migrates the database and ensures upcoming occurrences exist.
  Future<void> initialize() async {
    await _database.initialize();
    await refreshOccurrences();
  }

  Future<void> close() => _database.close();

  /// Loads medicines in display order. Archived rows are included by default.
  Future<List<Medication>> loadMedications({
    bool includeArchived = true,
  }) async {
    final database = await _database.instance;
    final rows = await database.query(
      'medications',
      where: includeArchived ? null : 'archived_at_utc_ms IS NULL',
      orderBy:
          'CASE WHEN archived_at_utc_ms IS NULL THEN 0 ELSE 1 END, '
          'name COLLATE NOCASE, id',
    );
    return rows.map(_medicationFromRow).toList(growable: false);
  }

  Future<Medication?> loadMedication(int id) async {
    final database = await _database.instance;
    final rows = await database.query(
      'medications',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _medicationFromRow(rows.single);
  }

  /// Loads scheduled doses in `[from, to)`, ordered chronologically.
  Future<List<DoseOccurrence>> loadOccurrences({
    required DateTime from,
    required DateTime to,
  }) async {
    final fromUtc = from.toUtc();
    final toUtc = to.toUtc();
    if (!toUtc.isAfter(fromUtc)) {
      throw ArgumentError.value(to, 'to', 'Must be later than from.');
    }

    final database = await _database.instance;
    final rows = await database.query(
      'dose_occurrences',
      where: 'scheduled_at_utc_ms >= ? AND scheduled_at_utc_ms < ?',
      whereArgs: [fromUtc.millisecondsSinceEpoch, toUtc.millisecondsSinceEpoch],
      orderBy: 'scheduled_at_utc_ms, id',
    );
    return rows.map(_occurrenceFromRow).toList(growable: false);
  }

  /// Creates a medicine and its initial dose occurrences atomically.
  ///
  /// Paused medicines still consume a free slot. Archived medicines do not.
  Future<Medication> createMedication(Medication medication) async {
    if (medication.id != null) {
      throw ArgumentError.value(
        medication.id,
        'medication.id',
        'A new medication cannot already have an id.',
      );
    }

    final database = await _database.instance;
    final current = _now();
    final now = current.toUtc();
    final localToday = _dateOnly(current.toLocal());
    final through = _addCalendarDays(localToday, materializationDays);

    return database.transaction((transaction) async {
      if (medication.archivedAt == null) {
        await _enforceCreateLimit(transaction);
      }

      final saved = Medication(
        name: medication.name,
        dosage: medication.dosage,
        instructions: medication.instructions,
        notes: medication.notes,
        colorValue: medication.colorValue,
        reminderTimes: medication.reminderTimes,
        weekdays: medication.weekdays,
        startDate: medication.startDate,
        endDate: medication.endDate,
        isActive: medication.isActive,
        archivedAt: medication.archivedAt,
        createdAt: now,
        updatedAt: now,
      );
      final id = await transaction.insert(
        'medications',
        _medicationToRow(saved),
      );
      final withId = saved.copyWith(id: id);
      await _materializeMedication(
        transaction,
        withId,
        from: localToday,
        throughInclusive: through,
        createdAt: now,
      );
      return withId;
    });
  }

  /// Updates a medicine, preserving every past or explicitly acted-on dose.
  /// Future pending doses are rebuilt with fresh name/dosage snapshots.
  Future<Medication> updateMedication(Medication medication) async {
    final id = medication.id;
    if (id == null) {
      throw ArgumentError.value(id, 'medication.id', 'An id is required.');
    }

    final database = await _database.instance;
    final current = _now();
    final now = current.toUtc();
    final localToday = _dateOnly(current.toLocal());
    final through = _addCalendarDays(localToday, materializationDays);

    return database.transaction((transaction) async {
      final existing = await _loadMedication(transaction, id);
      if (existing == null) _notFound('Medication', id);

      if (existing.isArchived && !medication.isArchived) {
        await _enforceCreateLimit(transaction);
      }

      final updated = Medication(
        id: id,
        name: medication.name,
        dosage: medication.dosage,
        instructions: medication.instructions,
        notes: medication.notes,
        colorValue: medication.colorValue,
        reminderTimes: medication.reminderTimes,
        weekdays: medication.weekdays,
        startDate: medication.startDate,
        endDate: medication.endDate,
        isActive: medication.isActive,
        archivedAt: medication.archivedAt,
        createdAt: existing.createdAt,
        updatedAt: now,
      );

      await transaction.update(
        'medications',
        _medicationToRow(updated, includeId: false),
        where: 'id = ?',
        whereArgs: [id],
      );
      await _deleteFuturePending(transaction, id, after: now);
      await _materializeMedication(
        transaction,
        updated,
        from: localToday,
        throughInclusive: through,
        createdAt: now,
      );
      return updated;
    });
  }

  Future<Medication> archiveMedication(int medicationId) async {
    final now = _now().toUtc();
    return _mutateMedication(
      medicationId,
      (medication) =>
          medication.copyWith(isActive: false, archivedAt: now, updatedAt: now),
      replaceFuture: true,
    );
  }

  /// Restores an archived medicine and atomically re-applies the free limit.
  Future<Medication> restoreMedication(int medicationId) async {
    final database = await _database.instance;
    final current = _now();
    final now = current.toUtc();
    final localToday = _dateOnly(current.toLocal());
    final through = _addCalendarDays(localToday, materializationDays);

    return database.transaction((transaction) async {
      final existing = await _loadMedication(transaction, medicationId);
      if (existing == null) _notFound('Medication', medicationId);
      if (!existing.isArchived) return existing;

      await _enforceCreateLimit(transaction);
      final restored = existing.copyWith(
        isActive: true,
        archivedAt: null,
        updatedAt: now,
      );
      await transaction.update(
        'medications',
        _medicationToRow(restored, includeId: false),
        where: 'id = ?',
        whereArgs: [medicationId],
      );
      await _materializeMedication(
        transaction,
        restored,
        from: localToday,
        throughInclusive: through,
        createdAt: now,
      );
      return restored;
    });
  }

  Future<Medication> pauseMedication(int medicationId) {
    final now = _now().toUtc();
    return _mutateMedication(
      medicationId,
      (medication) => medication.copyWith(isActive: false, updatedAt: now),
      replaceFuture: true,
    );
  }

  Future<Medication> resumeMedication(int medicationId) async {
    final now = _now().toUtc();
    return _mutateMedication(medicationId, (medication) {
      if (medication.isArchived) {
        throw StateError('Restore archived medication $medicationId first.');
      }
      return medication.copyWith(isActive: true, updatedAt: now);
    }, replaceFuture: true);
  }

  Future<DoseOccurrence> markTaken(int occurrenceId, {DateTime? actedAt}) =>
      _setOccurrenceStatus(
        occurrenceId,
        DoseStatus.taken,
        actedAt: actedAt ?? _now(),
      );

  Future<DoseOccurrence> markSkipped(int occurrenceId, {DateTime? actedAt}) =>
      _setOccurrenceStatus(
        occurrenceId,
        DoseStatus.skipped,
        actedAt: actedAt ?? _now(),
      );

  /// Clears the explicit outcome so time once again determines due/missed.
  Future<DoseOccurrence> undoOccurrence(int occurrenceId) =>
      _setOccurrenceStatus(occurrenceId, DoseStatus.pending);

  /// Backfills gaps and extends active schedules to at least 60 days ahead.
  Future<void> refreshOccurrences({DateTime? from, DateTime? through}) async {
    final database = await _database.instance;
    final current = _now();
    final now = current.toUtc();
    final localToday = _dateOnly(current.toLocal());
    final minimumThrough = _addCalendarDays(localToday, materializationDays);
    final requestedThrough = through == null
        ? minimumThrough
        : _dateOnly(through);
    final throughDate = requestedThrough.isAfter(minimumThrough)
        ? requestedThrough
        : minimumThrough;

    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'medications',
        where: 'archived_at_utc_ms IS NULL AND is_active = 1',
      );
      for (final row in rows) {
        final medication = _medicationFromRow(row);
        var fromDate = from == null
            ? await _nextMaterializationDate(
                transaction,
                medication,
                localToday,
              )
            : _dateOnly(from);
        if (fromDate.isBefore(medication.startDate)) {
          fromDate = medication.startDate;
        }
        await _materializeMedication(
          transaction,
          medication,
          from: fromDate,
          throughInclusive: throughDate,
          createdAt: now,
        );
      }
    });
  }

  /// Re-resolves all future pending wall-clock doses, intended for time-zone
  /// changes. Past and acted-on occurrences remain untouched.
  Future<void> rebuildFuturePendingOccurrences({DateTime? through}) async {
    final database = await _database.instance;
    final current = _now();
    final now = current.toUtc();
    final localToday = _dateOnly(current.toLocal());
    final minimumThrough = _addCalendarDays(localToday, materializationDays);
    final requestedThrough = through == null
        ? minimumThrough
        : _dateOnly(through);
    final throughDate = requestedThrough.isAfter(minimumThrough)
        ? requestedThrough
        : minimumThrough;

    await database.transaction((transaction) async {
      await transaction.delete(
        'dose_occurrences',
        where: 'status = ? AND scheduled_at_utc_ms > ?',
        whereArgs: [DoseStatus.pending.name, now.millisecondsSinceEpoch],
      );
      final rows = await transaction.query(
        'medications',
        where: 'archived_at_utc_ms IS NULL AND is_active = 1',
      );
      for (final row in rows) {
        await _materializeMedication(
          transaction,
          _medicationFromRow(row),
          from: localToday,
          throughInclusive: throughDate,
          createdAt: now,
        );
      }
    });
  }

  Future<int> countNonArchivedMedications() async {
    final database = await _database.instance;
    return _countNonArchived(database);
  }

  Future<bool> isPremiumUnlocked() async =>
      await readPremiumEntitlement() != null;

  Future<PremiumEntitlement?> readPremiumEntitlement() async {
    final database = await _database.instance;
    final rows = await database.query(
      'entitlements',
      where: 'is_active = 1',
      orderBy: 'granted_at_utc_ms DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return PremiumEntitlement(
      productId: row['product_id']! as String,
      transactionId: row['transaction_id']! as String,
      grantedAt: DateTime.fromMillisecondsSinceEpoch(
        row['granted_at_utc_ms']! as int,
        isUtc: true,
      ),
    );
  }

  /// Caches an entitlement only after the purchase layer has verified it.
  Future<PremiumEntitlement> grantPremium({
    required String productId,
    required String transactionId,
    DateTime? grantedAt,
  }) async {
    final normalizedProductId = productId.trim();
    final normalizedTransactionId = transactionId.trim();
    if (normalizedProductId.isEmpty || normalizedTransactionId.isEmpty) {
      throw ArgumentError('Product and transaction ids are required.');
    }
    final granted = (grantedAt ?? _now()).toUtc();
    final database = await _database.instance;
    await database.transaction((transaction) async {
      await transaction.update('entitlements', {'is_active': 0});
      await transaction.insert('entitlements', {
        'product_id': normalizedProductId,
        'transaction_id': normalizedTransactionId,
        'granted_at_utc_ms': granted.millisecondsSinceEpoch,
        'is_active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return PremiumEntitlement(
      productId: normalizedProductId,
      transactionId: normalizedTransactionId,
      grantedAt: granted,
    );
  }

  /// Deactivates the local cache after an explicit, verified store revocation.
  Future<void> revokePremium(String productId) async {
    final database = await _database.instance;
    await database.update(
      'entitlements',
      {'is_active': 0},
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  Future<String?> readSetting(String key) async {
    final database = await _database.instance;
    final rows = await database.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  Future<void> writeSetting(String key, String value) async {
    if (key.trim().isEmpty) throw ArgumentError.value(key, 'key');
    final database = await _database.instance;
    await database.insert('settings', {
      'key': key,
      'value': value,
      'updated_at_utc_ms': _now().toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSetting(String key) async {
    final database = await _database.instance;
    await database.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<Medication> _mutateMedication(
    int medicationId,
    Medication Function(Medication medication) mutate, {
    required bool replaceFuture,
  }) async {
    final database = await _database.instance;
    final current = _now();
    final now = current.toUtc();
    final localToday = _dateOnly(current.toLocal());
    final through = _addCalendarDays(localToday, materializationDays);

    return database.transaction((transaction) async {
      final existing = await _loadMedication(transaction, medicationId);
      if (existing == null) _notFound('Medication', medicationId);
      final updated = mutate(existing);

      await transaction.update(
        'medications',
        _medicationToRow(updated, includeId: false),
        where: 'id = ?',
        whereArgs: [medicationId],
      );
      if (replaceFuture) {
        await _deleteFuturePending(transaction, medicationId, after: now);
      }
      await _materializeMedication(
        transaction,
        updated,
        from: localToday,
        throughInclusive: through,
        createdAt: now,
      );
      return updated;
    });
  }

  Future<DoseOccurrence> _setOccurrenceStatus(
    int occurrenceId,
    DoseStatus status, {
    DateTime? actedAt,
  }) async {
    final database = await _database.instance;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'dose_occurrences',
        where: 'id = ?',
        whereArgs: [occurrenceId],
        limit: 1,
      );
      if (rows.isEmpty) _notFound('Dose occurrence', occurrenceId);

      final actedAtUtc = status == DoseStatus.pending
          ? null
          : (actedAt ?? _now()).toUtc();
      await transaction.update(
        'dose_occurrences',
        {
          'status': status.name,
          'acted_at_utc_ms': actedAtUtc?.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [occurrenceId],
      );
      return _occurrenceFromRow({
        ...rows.single,
        'status': status.name,
        'acted_at_utc_ms': actedAtUtc?.millisecondsSinceEpoch,
      });
    });
  }

  Future<void> _enforceCreateLimit(DatabaseExecutor executor) async {
    if (await _hasPremium(executor)) return;
    final count = await _countNonArchived(executor);
    if (count >= freeMedicationLimit) {
      throw MedicationLimitReached(limit: freeMedicationLimit);
    }
  }

  Future<bool> _hasPremium(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery(
      'SELECT 1 FROM entitlements WHERE is_active = 1 LIMIT 1',
    );
    return rows.isNotEmpty;
  }

  Future<int> _countNonArchived(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) AS count FROM medications '
      'WHERE archived_at_utc_ms IS NULL',
    );
    return (rows.single['count']! as num).toInt();
  }

  Future<Medication?> _loadMedication(DatabaseExecutor executor, int id) async {
    final rows = await executor.query(
      'medications',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _medicationFromRow(rows.single);
  }

  Future<void> _deleteFuturePending(
    DatabaseExecutor executor,
    int medicationId, {
    required DateTime after,
  }) async {
    await executor.delete(
      'dose_occurrences',
      where: 'medication_id = ? AND status = ? AND scheduled_at_utc_ms > ?',
      whereArgs: [
        medicationId,
        DoseStatus.pending.name,
        after.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  Future<DateTime> _nextMaterializationDate(
    DatabaseExecutor executor,
    Medication medication,
    DateTime localToday,
  ) async {
    final rows = await executor.rawQuery(
      'SELECT MAX(scheduled_at_utc_ms) AS latest '
      'FROM dose_occurrences WHERE medication_id = ?',
      [medication.id],
    );
    final latest = rows.single['latest'] as int?;
    if (latest == null) {
      return medication.startDate.isAfter(localToday)
          ? medication.startDate
          : localToday;
    }
    final latestLocalDate = _dateOnly(
      DateTime.fromMillisecondsSinceEpoch(latest, isUtc: true).toLocal(),
    );
    if (latestLocalDate.isBefore(localToday)) {
      return _addCalendarDays(latestLocalDate, 1);
    }
    return localToday;
  }

  Future<void> _materializeMedication(
    DatabaseExecutor executor,
    Medication medication, {
    required DateTime from,
    required DateTime throughInclusive,
    required DateTime createdAt,
  }) async {
    final id = medication.id;
    if (id == null || medication.isArchived || !medication.isActive) return;
    if (medication.reminderTimes.isEmpty || medication.weekdays.isEmpty) return;

    var cursor = _dateOnly(from);
    if (cursor.isBefore(medication.startDate)) cursor = medication.startDate;
    var lastDate = _dateOnly(throughInclusive);
    final endDate = medication.endDate;
    if (endDate != null && endDate.isBefore(lastDate)) lastDate = endDate;
    if (cursor.isAfter(lastDate)) return;

    final batch = executor.batch();
    while (!cursor.isAfter(lastDate)) {
      if (medication.weekdays.contains(cursor.weekday)) {
        for (final reminder in medication.reminderTimes) {
          final localScheduled = DateTime(
            cursor.year,
            cursor.month,
            cursor.day,
            reminder.hour,
            reminder.minute,
          );
          batch.insert('dose_occurrences', {
            'medication_id': id,
            'scheduled_at_utc_ms': localScheduled
                .toUtc()
                .millisecondsSinceEpoch,
            'medication_name': medication.name,
            'dosage': medication.dosage,
            'status': DoseStatus.pending.name,
            'acted_at_utc_ms': null,
            'created_at_utc_ms': createdAt.toUtc().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      cursor = _addCalendarDays(cursor, 1);
    }
    await batch.commit(noResult: true);
  }
}

Map<String, Object?> _medicationToRow(
  Medication medication, {
  bool includeId = true,
}) {
  return {
    if (includeId && medication.id != null) 'id': medication.id,
    'name': medication.name,
    'dosage': medication.dosage,
    'instructions': medication.instructions,
    'notes': medication.notes,
    'color_value': medication.colorValue,
    'reminder_minutes': medication.reminderTimes
        .map((time) => time.minutesSinceMidnight)
        .join(','),
    'weekdays_mask': _encodeWeekdays(medication.weekdays),
    'start_date': _encodeDate(medication.startDate),
    'end_date': medication.endDate == null
        ? null
        : _encodeDate(medication.endDate!),
    'is_active': medication.isActive ? 1 : 0,
    'archived_at_utc_ms': medication.archivedAt?.millisecondsSinceEpoch,
    'created_at_utc_ms': medication.createdAt.millisecondsSinceEpoch,
    'updated_at_utc_ms': medication.updatedAt.millisecondsSinceEpoch,
  };
}

Medication _medicationFromRow(Map<String, Object?> row) {
  final reminderMinutes = row['reminder_minutes']! as String;
  return Medication(
    id: row['id']! as int,
    name: row['name']! as String,
    dosage: row['dosage']! as String,
    instructions: row['instructions']! as String,
    notes: row['notes']! as String,
    colorValue: row['color_value']! as int,
    reminderTimes: reminderMinutes.isEmpty
        ? const <ReminderTime>[]
        : reminderMinutes
              .split(',')
              .map(int.parse)
              .map(ReminderTime.fromMinutesSinceMidnight),
    weekdays: _decodeWeekdays(row['weekdays_mask']! as int),
    startDate: _decodeDate(row['start_date']! as String),
    endDate: row['end_date'] == null
        ? null
        : _decodeDate(row['end_date']! as String),
    isActive: (row['is_active']! as int) == 1,
    archivedAt: _decodeInstant(row['archived_at_utc_ms'] as int?),
    createdAt: _decodeInstant(row['created_at_utc_ms']! as int)!,
    updatedAt: _decodeInstant(row['updated_at_utc_ms']! as int)!,
  );
}

DoseOccurrence _occurrenceFromRow(Map<String, Object?> row) {
  return DoseOccurrence(
    id: row['id']! as int,
    medicationId: row['medication_id']! as int,
    scheduledAt: _decodeInstant(row['scheduled_at_utc_ms']! as int)!,
    medicationName: row['medication_name']! as String,
    dosage: row['dosage']! as String,
    status: DoseStatus.values.byName(row['status']! as String),
    actedAt: _decodeInstant(row['acted_at_utc_ms'] as int?),
  );
}

int _encodeWeekdays(Set<int> weekdays) {
  var mask = 0;
  for (final weekday in weekdays) {
    mask |= 1 << (weekday - 1);
  }
  return mask;
}

Set<int> _decodeWeekdays(int mask) => Set.unmodifiable([
  for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
    if ((mask & (1 << (weekday - 1))) != 0) weekday,
]);

String _encodeDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _decodeDate(String encoded) {
  final parts = encoded.split('-');
  if (parts.length != 3) throw FormatException('Invalid local date', encoded);
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

DateTime? _decodeInstant(int? milliseconds) => milliseconds == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _addCalendarDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

Never _notFound(String entity, int id) =>
    throw StateError('$entity $id was not found.');
