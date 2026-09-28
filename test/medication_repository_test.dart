import 'package:flutter_test/flutter_test.dart';
import 'package:yawela/src/config/app_config.dart';
import 'package:yawela/src/data/data.dart';
import 'package:yawela/src/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Medication _newMedication(String name) {
  return Medication(
    name: name,
    dosage: '1 เม็ด',
    colorValue: 0xFF147D6F,
    reminderTimes: [ReminderTime(8, 0)],
    weekdays: const {1, 2, 3, 4, 5, 6, 7},
    startDate: DateTime(2026, 8, 29),
  );
}

void main() {
  sqfliteFfiInit();

  late MedicationRepository repository;
  final fixedNow = DateTime(2026, 8, 29, 9);

  setUp(() async {
    repository = MedicationRepository(
      database: AppDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      ),
      now: () => fixedNow,
    );
    await repository.initialize();
  });

  tearDown(() => repository.close());

  test('free tier is enforced and premium removes the limit', () async {
    for (var index = 1; index <= AppConfig.freeMedicationLimit; index++) {
      await repository.createMedication(_newMedication('ยา $index'));
    }

    await expectLater(
      repository.createMedication(_newMedication('ยาเกินสิทธิ์')),
      throwsA(isA<MedicationLimitReached>()),
    );

    await repository.grantPremium(
      productId: 'medireminder.premium.lifetime.v1',
      transactionId: 'test-transaction',
    );
    await repository.createMedication(_newMedication('ยาพรีเมียม'));

    expect(
      await repository.countNonArchivedMedications(),
      AppConfig.freeMedicationLimit + 1,
    );
    expect(await repository.isPremiumUnlocked(), isTrue);
  });

  test('concurrent creation never exceeds the free limit', () async {
    final results = await Future.wait(
      List.generate(AppConfig.freeMedicationLimit + 2, (index) async {
        try {
          await repository.createMedication(
            _newMedication('ยาพร้อมกัน $index'),
          );
          return true;
        } on MedicationLimitReached {
          return false;
        }
      }),
    );

    expect(
      results.where((created) => created),
      hasLength(AppConfig.freeMedicationLimit),
    );
    expect(
      await repository.countNonArchivedMedications(),
      AppConfig.freeMedicationLimit,
    );
  });

  test('dose status is materialized and persisted offline', () async {
    await repository.createMedication(_newMedication('ยาหัวใจ'));

    final occurrences = await repository.loadOccurrences(
      from: DateTime(2026, 8, 29),
      to: DateTime(2026, 8, 30),
    );
    expect(occurrences, hasLength(1));
    expect(occurrences.single.status, DoseStatus.pending);

    await repository.markTaken(occurrences.single.id, actedAt: fixedNow);
    final reloaded = await repository.loadOccurrences(
      from: DateTime(2026, 8, 29),
      to: DateTime(2026, 8, 30),
    );

    expect(reloaded.single.status, DoseStatus.taken);
    expect(reloaded.single.actedAt, fixedNow.toUtc());
  });

  test('archiving frees a slot without deleting dose history', () async {
    final first = await repository.createMedication(_newMedication('ยา 1'));
    for (var index = 2; index <= AppConfig.freeMedicationLimit; index++) {
      await repository.createMedication(_newMedication('ยา $index'));
    }

    await repository.archiveMedication(first.id!);
    await repository.createMedication(_newMedication('ยาใหม่'));

    expect(
      await repository.countNonArchivedMedications(),
      AppConfig.freeMedicationLimit,
    );
    final history = await repository.loadOccurrences(
      from: DateTime(2026, 8, 29),
      to: DateTime(2026, 8, 30),
    );
    expect(history.any((dose) => dose.medicationId == first.id), isTrue);
  });
}
