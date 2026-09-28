import 'package:flutter/material.dart';

import '../domain/domain.dart';
import '../services/notification_service.dart';
import 'app_theme.dart';
import 'common_widgets.dart';
import 'dose_state_presentation.dart';
import 'formatters.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.medications,
    required this.occurrences,
    required this.now,
    required this.reminderSync,
    required this.onAddMedication,
    required this.onMarkTaken,
    required this.onMarkSkipped,
    required this.onUndo,
    required this.onRequestNotifications,
  });

  final List<Medication> medications;
  final List<DoseOccurrence> occurrences;
  final DateTime now;
  final ReminderSyncResult? reminderSync;
  final VoidCallback onAddMedication;
  final Future<void> Function(DoseOccurrence occurrence) onMarkTaken;
  final Future<void> Function(DoseOccurrence occurrence) onMarkSkipped;
  final Future<void> Function(DoseOccurrence occurrence) onUndo;
  final Future<void> Function() onRequestNotifications;

  @override
  Widget build(BuildContext context) {
    final visibleMedications = medications
        .where((medication) => !medication.isArchived)
        .toList(growable: false);
    final sortedOccurrences = occurrences.toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final taken = sortedOccurrences
        .where((occurrence) => occurrence.status == DoseStatus.taken)
        .length;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const PageStorageKey('todayScroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppPageHeader(
                        title: 'วันนี้',
                        subtitle: MaterialLocalizations.of(
                          context,
                        ).formatFullDate(now.toLocal()),
                        trailing: IconButton.filledTonal(
                          key: const Key('quickAddMedicationButton'),
                          tooltip: 'เพิ่มรายการยา',
                          onPressed: onAddMedication,
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _TodaySummary(
                        taken: taken,
                        total: sortedOccurrences.length,
                      ),
                      if (visibleMedications.isNotEmpty &&
                          reminderSync?.notificationsGranted == false) ...[
                        const SizedBox(height: 14),
                        _NotificationBanner(onEnable: onRequestNotifications),
                      ],
                      if (reminderSync?.wasLimited == true) ...[
                        const SizedBox(height: 14),
                        const _ReminderLimitBanner(),
                      ],
                      if (sortedOccurrences.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        SectionTitle(
                          title: 'ตารางวันนี้ (${sortedOccurrences.length})',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (visibleMedications.isEmpty)
            SliverToBoxAdapter(
              child: AppEmptyState(
                icon: Icons.notifications_active_outlined,
                title: 'เริ่มเตือนกินยาได้เลย',
                message:
                    'เพิ่มรายการยาและเวลาที่ต้องทาน ข้อมูลทั้งหมดจะเก็บอยู่ในเครื่องของคุณ',
                action: FilledButton.icon(
                  onPressed: onAddMedication,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('เพิ่มยารายการแรก'),
                ),
              ),
            )
          else if (sortedOccurrences.isEmpty)
            const SliverToBoxAdapter(
              child: AppEmptyState(
                icon: Icons.event_available_rounded,
                title: 'วันนี้ไม่มีรายการต้องทาน',
                message:
                    'พักผ่อนให้เต็มที่ แล้วกลับมาตรวจตารางอีกครั้งพรุ่งนี้',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
              sliver: SliverList.separated(
                itemCount: sortedOccurrences.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final occurrence = sortedOccurrences[index];
                  final medication = _findMedication(
                    medications,
                    occurrence.medicationId,
                  );
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: _DoseCard(
                        occurrence: occurrence,
                        now: now,
                        color: medication == null
                            ? AppColors.primary
                            : Color(medication.colorValue),
                        instructions: medication?.instructions ?? '',
                        onTaken: () => onMarkTaken(occurrence),
                        onSkipped: () => onMarkSkipped(occurrence),
                        onUndo: () => onUndo(occurrence),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

Medication? _findMedication(List<Medication> values, int id) {
  for (final medication in values) {
    if (medication.id == id) return medication;
  }
  return null;
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.taken, required this.total});

  final int taken;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : taken / total;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D665B), Color(0xFF168D7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24147D6F),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'แผนการทานวันนี้',
                  style: TextStyle(color: Color(0xFFD8F3EC), fontSize: 14),
                ),
                const SizedBox(height: 5),
                Text(
                  total == 0
                      ? 'ยังไม่มีรายการ'
                      : 'ทานแล้ว $taken จาก $total ครั้ง',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 9,
                    color: Colors.white,
                    backgroundColor: const Color(0x35FFFFFF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0x24FFFFFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.health_and_safety_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({required this.onEnable});

  final Future<void> Function() onEnable;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF8E9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.notifications_off_outlined,
              color: AppColors.warning,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ยังไม่ได้เปิดการแจ้งเตือน',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'อนุญาตเพื่อให้แอปเตือนตามเวลาแม้ไม่ได้เปิดแอป',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onEnable, child: const Text('เปิดใช้งาน')),
          ],
        ),
      ),
    );
  }
}

class _ReminderLimitBanner extends StatelessWidget {
  const _ReminderLimitBanner();

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: Color(0xFFFFF3F2),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.missed),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'ระบบจัดคิวเวลาเตือนที่ใกล้ที่สุด 60 รายการ กรุณาเปิดแอปเป็นระยะเพื่อเติมคิวถัดไป',
                style: TextStyle(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({
    required this.occurrence,
    required this.now,
    required this.color,
    required this.instructions,
    required this.onTaken,
    required this.onSkipped,
    required this.onUndo,
  });

  final DoseOccurrence occurrence;
  final DateTime now;
  final Color color;
  final String instructions;
  final Future<void> Function() onTaken;
  final Future<void> Function() onSkipped;
  final Future<void> Function() onUndo;

  @override
  Widget build(BuildContext context) {
    final state = occurrence.effectiveState(now: now);
    final presentation = doseStatePresentation(state);
    final completed =
        state == DoseEffectiveState.taken ||
        state == DoseEffectiveState.skipped;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(Icons.medication_rounded, color: color, size: 29),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              occurrence.medicationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          StatusPill(
                            label: presentation.label,
                            foreground: presentation.foreground,
                            background: presentation.background,
                            icon: presentation.icon,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        occurrence.dosage,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (instructions.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          instructions,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'เวลาที่กำหนด',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const Spacer(),
                  Text(
                    formatOccurrenceTime(context, occurrence.scheduledAt),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (completed)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('แก้ไขสถานะ'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSkipped,
                      child: const Text('ข้ามครั้งนี้'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      key: Key('takeDose-${occurrence.id}'),
                      onPressed: onTaken,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('ทานแล้ว'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
