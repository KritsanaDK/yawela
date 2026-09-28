import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the single SQLite connection used by the offline data layer.
///
/// A custom [databaseFactoryOverride] and [databasePath] can be supplied by
/// tests (for example an FFI factory and [inMemoryDatabasePath]).
final class AppDatabase {
  AppDatabase({DatabaseFactory? databaseFactoryOverride, this.databasePath})
    : _databaseFactory = databaseFactoryOverride ?? databaseFactory;

  static const String defaultFileName = 'medication_reminder.db';
  static const int schemaVersion = 1;

  final DatabaseFactory _databaseFactory;
  final String? databasePath;

  Database? _database;
  Future<Database>? _opening;
  bool _isClosed = false;

  Future<Database> get instance async {
    if (_isClosed) {
      throw StateError('AppDatabase has already been closed.');
    }

    final openDatabase = _database;
    if (openDatabase != null) return openDatabase;

    final inProgress = _opening;
    if (inProgress != null) return inProgress;

    final opening = _openAndRetain();
    _opening = opening;
    try {
      return await opening;
    } finally {
      _opening = null;
    }
  }

  Future<void> initialize() async {
    await instance;
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    final database = _database;
    _database = null;
    if (database != null) {
      await database.close();
      return;
    }

    // If opening is still in flight, [_openAndRetain] closes the connection as
    // soon as it becomes available. Await it so close never leaks a handle.
    final opening = _opening;
    if (opening == null) return;
    try {
      await opening;
    } on StateError {
      // Expected when close wins the race with open.
    }
  }

  Future<Database> _openAndRetain() async {
    final database = await _open();
    if (_isClosed) {
      await database.close();
      throw StateError('AppDatabase was closed while it was opening.');
    }
    _database = database;
    return database;
  }

  Future<Database> _open() async {
    final path =
        databasePath ??
        p.join(await _databaseFactory.getDatabasesPath(), defaultFileName);

    return _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  Future<void> _createSchema(Database database, int version) async {
    final batch = database.batch();
    batch.execute('''
      CREATE TABLE medications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
        dosage TEXT NOT NULL DEFAULT '',
        instructions TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        color_value INTEGER NOT NULL,
        reminder_minutes TEXT NOT NULL DEFAULT '',
        weekdays_mask INTEGER NOT NULL CHECK(weekdays_mask BETWEEN 0 AND 127),
        start_date TEXT NOT NULL,
        end_date TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
        archived_at_utc_ms INTEGER,
        created_at_utc_ms INTEGER NOT NULL,
        updated_at_utc_ms INTEGER NOT NULL,
        CHECK(end_date IS NULL OR end_date >= start_date)
      )
    ''');
    batch.execute('''
      CREATE INDEX idx_medications_archive_name
      ON medications(archived_at_utc_ms, name COLLATE NOCASE)
    ''');
    batch.execute('''
      CREATE TABLE dose_occurrences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medication_id INTEGER NOT NULL,
        scheduled_at_utc_ms INTEGER NOT NULL,
        medication_name TEXT NOT NULL,
        dosage TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK(status IN ('pending', 'taken', 'skipped')),
        acted_at_utc_ms INTEGER,
        created_at_utc_ms INTEGER NOT NULL,
        FOREIGN KEY(medication_id) REFERENCES medications(id)
          ON UPDATE CASCADE ON DELETE RESTRICT,
        UNIQUE(medication_id, scheduled_at_utc_ms)
      )
    ''');
    batch.execute('''
      CREATE INDEX idx_occurrences_scheduled_status
      ON dose_occurrences(scheduled_at_utc_ms, status)
    ''');
    batch.execute('''
      CREATE INDEX idx_occurrences_medication_scheduled
      ON dose_occurrences(medication_id, scheduled_at_utc_ms)
    ''');
    batch.execute('''
      CREATE TABLE entitlements (
        product_id TEXT PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        granted_at_utc_ms INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1))
      )
    ''');
    batch.execute('''
      CREATE INDEX idx_entitlements_active
      ON entitlements(is_active)
    ''');
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at_utc_ms INTEGER NOT NULL
      )
    ''');
    await batch.commit(noResult: true);
  }

  Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    // Version 1 is the initial production schema. Future migrations belong here
    // and must be additive so medicine and adherence history are never dropped.
    if (oldVersion < 1) await _createSchema(database, newVersion);
  }
}
