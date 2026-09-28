import 'package:flutter/material.dart';

import '../domain/domain.dart';
import 'app_theme.dart';
import 'common_widgets.dart';
import 'formatters.dart';

class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({
    super.key,
    required this.medications,
    required this.isPremium,
    required this.freeMedicationLimit,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleActive,
    required this.onArchive,
    required this.onUpgrade,
  });

  final List<Medication> medications;
  final bool isPremium;
  final int freeMedicationLimit;
  final VoidCallback onAdd;
  final ValueChanged<Medication> onEdit;
  final Future<void> Function(Medication medication, bool active)
  onToggleActive;
  final Future<void> Function(Medication medication) onArchive;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final visible = medications.where((item) => !item.isArchived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const PageStorageKey('medicationsScroll'),
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
                        title: 'รายการยา',
                        subtitle: 'จัดการยาและเวลาแจ้งเตือนทั้งหมด',
                        trailing: FilledButton.icon(
                          key: const Key('addMedicationButton'),
                          onPressed: onAdd,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('เพิ่มยา'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _PlanBanner(
                        count: visible.length,
                        isPremium: isPremium,
                        freeMedicationLimit: freeMedicationLimit,
                        onUpgrade: onUpgrade,
                      ),
                      if (visible.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        SectionTitle(title: 'ยาของฉัน (${visible.length})'),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: AppEmptyState(
                icon: Icons.medication_liquid_outlined,
                title: 'ยังไม่มีรายการยา',
                message:
                    'เพิ่มชื่อยา ขนาดที่ทาน และเวลาเตือน แอปจะเก็บข้อมูลไว้ในเครื่องนี้',
                action: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('เพิ่มยารายการแรก'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 112),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final medication = visible[index];
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: _MedicationCard(
                        medication: medication,
                        onEdit: () => onEdit(medication),
                        onToggleActive: (value) =>
                            onToggleActive(medication, value),
                        onArchive: () => _confirmArchive(context, medication),
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

  Future<void> _confirmArchive(
    BuildContext context,
    Medication medication,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('นำรายการยาออก?'),
        content: Text(
          'รายการ “${medication.name}” จะหยุดแจ้งเตือน แต่ประวัติการทานเดิมยังคงอยู่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('นำออก'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onArchive(medication);
  }
}

class _PlanBanner extends StatelessWidget {
  const _PlanBanner({
    required this.count,
    required this.isPremium,
    required this.freeMedicationLimit,
    required this.onUpgrade,
  });

  final int count;
  final bool isPremium;
  final int freeMedicationLimit;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPremium
              ? const [Color(0xFF175D53), Color(0xFF147D6F)]
              : const [Color(0xFFE4F5EF), Color(0xFFF0F8F5)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPremium ? Colors.transparent : const Color(0xFFCBE8DE),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPremium ? const Color(0x24FFFFFF) : Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPremium ? Icons.workspace_premium_rounded : Icons.spa_outlined,
              color: isPremium ? Colors.white : AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPremium
                      ? 'ปลดล็อกแบบถาวรแล้ว'
                      : 'แพ็กเกจฟรี $count/$freeMedicationLimit รายการ',
                  style: TextStyle(
                    color: isPremium ? Colors.white : AppColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isPremium
                      ? 'เพิ่มยาได้ไม่จำกัด • จ่ายครั้งเดียว'
                      : count >= freeMedicationLimit
                      ? 'ครบจำนวนฟรีแล้ว ปลดล็อกเพื่อเพิ่มยาไม่จำกัด'
                      : 'เพิ่มได้อีก ${freeMedicationLimit - count} รายการโดยไม่เสียค่าใช้จ่าย',
                  style: TextStyle(
                    color: isPremium
                        ? const Color(0xFFD5F2E9)
                        : AppColors.muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (!isPremium)
            TextButton(onPressed: onUpgrade, child: const Text('ดูพรีเมียม')),
        ],
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.medication,
    required this.onEdit,
    required this.onToggleActive,
    required this.onArchive,
  });

  final Medication medication;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final color = Color(medication.colorValue);
    final times = medication.reminderTimes
        .map((time) => formatReminderTime(context, time))
        .join(' • ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.medication_rounded, color: color, size: 27),
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
                            medication.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        StatusPill(
                          label: medication.isActive ? 'เปิดอยู่' : 'พักไว้',
                          foreground: medication.isActive
                              ? AppColors.taken
                              : AppColors.skipped,
                          background: medication.isActive
                              ? const Color(0xFFE4F5EC)
                              : const Color(0xFFF0F1F3),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      medication.dosage,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (medication.instructions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        medication.instructions,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(icon: Icons.schedule_rounded, label: times),
                        _InfoChip(
                          icon: Icons.calendar_month_outlined,
                          label: formatMedicationDays(medication.weekdays),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('แจ้งเตือน'),
                            value: medication.isActive,
                            onChanged: onToggleActive,
                          ),
                        ),
                        IconButton(
                          tooltip: 'แก้ไข',
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'นำรายการออก',
                          onPressed: onArchive,
                          icon: const Icon(Icons.archive_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
