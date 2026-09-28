import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawela/src/config/app_config.dart';
import 'package:yawela/src/domain/domain.dart';
import 'package:yawela/src/ui/app_theme.dart';
import 'package:yawela/src/ui/formatters.dart';
import 'package:yawela/src/ui/medication_form_page.dart';
import 'package:yawela/src/ui/medications_screen.dart';
import 'package:yawela/src/ui/today_screen.dart';

Widget _testApp(Widget home) {
  return MaterialApp(
    theme: buildAppTheme(),
    locale: const Locale('th'),
    supportedLocales: const [Locale('th')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: build24HourMediaQuery,
    home: home,
  );
}

Medication _medication({int id = 1, String name = 'ยาความดัน'}) {
  return Medication(
    id: id,
    name: name,
    dosage: '1 เม็ด',
    instructions: 'หลังอาหาร',
    colorValue: AppColors.primary.toARGB32(),
    reminderTimes: [ReminderTime(8, 0)],
    weekdays: const {1, 2, 3, 4, 5, 6, 7},
    startDate: DateTime(2026, 8, 29),
  );
}

void main() {
  testWidgets('medication form validates required fields', (tester) async {
    await tester.pumpWidget(_testApp(const MedicationFormPage()));

    expect(find.text('เพิ่มรายการยา'), findsWidgets);
    await tester.tap(find.byKey(const Key('saveMedicationButton')));
    await tester.pump();

    expect(find.text('กรุณากรอกชื่อยา'), findsOneWidget);
    expect(find.text('กรุณากรอกขนาดที่ทาน'), findsOneWidget);
  });

  testWidgets('medication form uses instruction choices and 24-hour time', (
    tester,
  ) async {
    final medication = _medication().copyWith(
      instructions: 'หลังอาหาร',
      reminderTimes: [ReminderTime(20, 30)],
    );

    await tester.pumpWidget(
      _testApp(MedicationFormPage(initialMedication: medication)),
    );

    expect(find.text('ก่อนอาหาร'), findsOneWidget);
    expect(find.text('พร้อมอาหาร'), findsOneWidget);
    expect(find.text('หลังอาหาร'), findsOneWidget);
    expect(find.text('ก่อนนอน'), findsOneWidget);
    expect(find.text('ตามแพทย์สั่ง'), findsOneWidget);
    expect(find.text('อื่น ๆ'), findsOneWidget);
    expect(find.text('20:30'), findsOneWidget);

    final selectedChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey<String>('instruction-afterMeal')),
    );
    expect(selectedChip.selected, isTrue);

    await tester.ensureVisible(find.byTooltip('แก้ไขเวลา'));
    await tester.tap(find.byTooltip('แก้ไขเวลา'));
    await tester.pumpAndSettle();

    final pickerContext = tester.element(find.byType(TimePickerDialog));
    expect(MediaQuery.of(pickerContext).alwaysUse24HourFormat, isTrue);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
  });

  testWidgets('custom instruction is required and returned on save', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(const Scaffold()));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final resultFuture = navigator.push<Medication>(
      MaterialPageRoute<Medication>(
        builder: (_) => MedicationFormPage(initialMedication: _medication()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('instruction-custom')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveMedicationButton')));
    await tester.pump();
    expect(find.text('กรุณาระบุวิธีทาน'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('customMedicationInstructionField')),
      'หลังอาหารทันที',
    );
    await tester.tap(find.byKey(const Key('saveMedicationButton')));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result?.instructions, 'หลังอาหารทันที');
  });

  testWidgets('today screen shows an offline-first empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        TodayScreen(
          medications: const [],
          occurrences: const [],
          now: DateTime(2026, 8, 29, 8),
          reminderSync: null,
          onAddMedication: () {},
          onMarkTaken: (_) async {},
          onMarkSkipped: (_) async {},
          onUndo: (_) async {},
          onRequestNotifications: () async {},
        ),
      ),
    );

    expect(find.text('วันนี้'), findsOneWidget);
    expect(find.text('เริ่มเตือนกินยาได้เลย'), findsOneWidget);
    expect(find.text('เพิ่มยารายการแรก'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scheduled dose can be marked as taken', (tester) async {
    var markedTaken = false;
    final medication = _medication();
    final occurrence = DoseOccurrence(
      id: 10,
      medicationId: medication.id!,
      scheduledAt: DateTime(2026, 8, 29, 8).toUtc(),
      medicationName: medication.name,
      dosage: medication.dosage,
    );

    await tester.pumpWidget(
      _testApp(
        TodayScreen(
          medications: [medication],
          occurrences: [occurrence],
          now: DateTime(2026, 8, 29, 8, 15),
          reminderSync: null,
          onAddMedication: () {},
          onMarkTaken: (_) async => markedTaken = true,
          onMarkSkipped: (_) async {},
          onUndo: (_) async {},
          onRequestNotifications: () async {},
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('takeDose-10')));
    await tester.tap(find.byKey(const Key('takeDose-10')));
    await tester.pump();

    expect(markedTaken, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('free plan displays the three-medicine allowance', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _testApp(
        MedicationsScreen(
          medications: [
            _medication(id: 1, name: 'ยา A'),
            _medication(id: 2, name: 'ยา B'),
            _medication(id: 3, name: 'ยา C'),
          ],
          isPremium: false,
          freeMedicationLimit: AppConfig.freeMedicationLimit,
          onAdd: () {},
          onEdit: (_) {},
          onToggleActive: (_, _) async {},
          onArchive: (_) async {},
          onUpgrade: () {},
        ),
      ),
    );

    expect(
      find.text(
        'แพ็กเกจฟรี ${AppConfig.freeMedicationLimit}/'
        '${AppConfig.freeMedicationLimit} รายการ',
      ),
      findsOneWidget,
    );
    expect(find.text('ดูพรีเมียม'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
