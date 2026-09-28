import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/domain.dart';
import 'app_theme.dart';
import 'common_widgets.dart';
import 'dose_state_presentation.dart';
import 'formatters.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({
    super.key,
    required this.occurrences,
    required this.now,
  });

  final List<DoseOccurrence> occurrences;
  final DateTime now;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final current = widget.now.toLocal();
    final today = startOfDay(current);
    final from = today.subtract(Duration(days: _days - 1));
    final dueOccurrences = widget.occurrences
        .where((occurrence) {
          final local = occurrence.scheduledAt.toLocal();
          return !local.isBefore(from) && !local.isAfter(current);
        })
        .toList(growable: false);
    final summary = summarizeAdherence(dueOccurrences, now: current);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const PageStorageKey('statisticsScroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 112),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppPageHeader(
                        title: 'สถิติการทานยา',
                        subtitle:
                            'ดูความสม่ำเสมอจากรายการที่บันทึกไว้ในเครื่อง',
                      ),
                      const SizedBox(height: 20),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 7, label: Text('7 วัน')),
                          ButtonSegment(value: 30, label: Text('30 วัน')),
                        ],
                        selected: {_days},
                        onSelectionChanged: (selection) {
                          setState(() => _days = selection.single);
                        },
                      ),
                      const SizedBox(height: 20),
                      _AdherenceHero(summary: summary),
                      const SizedBox(height: 14),
                      _SummaryGrid(summary: summary),
                      const SizedBox(height: 28),
                      const SectionTitle(title: 'แนวโน้มรายวัน'),
                      const SizedBox(height: 12),
                      _DailyChart(
                        occurrences: dueOccurrences,
                        days: _days,
                        today: today,
                        now: current,
                      ),
                      const SizedBox(height: 28),
                      const SectionTitle(title: 'ประวัติล่าสุด'),
                      const SizedBox(height: 12),
                      if (dueOccurrences.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'ยังไม่มีข้อมูลในช่วงเวลานี้',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ),
                        )
                      else
                        _HistoryList(
                          occurrences: (dueOccurrences.toList()
                            ..sort(
                              (a, b) => b.scheduledAt.compareTo(a.scheduledAt),
                            )),
                          now: current,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdherenceHero extends StatelessWidget {
  const _AdherenceHero({required this.summary});

  final AdherenceSummary summary;

  @override
  Widget build(BuildContext context) {
    final percentage = (summary.adherence * 100).round();
    final message = summary.completed == 0
        ? 'เริ่มบันทึกการทานยาเพื่อดูสถิติ'
        : percentage >= 90
        ? 'ยอดเยี่ยมมาก รักษาความสม่ำเสมอนี้ไว้นะ'
        : percentage >= 70
        ? 'ทำได้ดี อีกนิดเดียวก็ถึงเป้าหมาย'
        : 'ลองเปิดแจ้งเตือนและบันทึกทุกครั้งที่ทาน';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E6E61), Color(0xFF18947F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: summary.completed == 0 ? 0 : summary.adherence,
                  strokeWidth: 9,
                  backgroundColor: const Color(0x33FFFFFF),
                  color: Colors.white,
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Text(
                    '$percentage%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 21,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ความสม่ำเสมอ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(color: Color(0xFFD8F3EC), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final AdherenceSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(140.0, (constraints.maxWidth - 12) / 2);
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              width: width,
              icon: Icons.check_circle_rounded,
              label: 'ทานแล้ว',
              value: summary.taken,
              color: AppColors.taken,
            ),
            _SummaryCard(
              width: width,
              icon: Icons.error_outline_rounded,
              label: 'พลาด',
              value: summary.missed,
              color: AppColors.missed,
            ),
            _SummaryCard(
              width: width,
              icon: Icons.fast_forward_rounded,
              label: 'ข้าม',
              value: summary.skipped,
              color: AppColors.skipped,
            ),
            _SummaryCard(
              width: width,
              icon: Icons.timelapse_rounded,
              label: 'รอบันทึก',
              value: summary.due,
              color: AppColors.warning,
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$value',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
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

class _DailyChart extends StatelessWidget {
  const _DailyChart({
    required this.occurrences,
    required this.days,
    required this.today,
    required this.now,
  });

  final List<DoseOccurrence> occurrences;
  final int days;
  final DateTime today;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final dayValues = List.generate(days, (index) {
      final date = today.subtract(Duration(days: days - index - 1));
      final end = date.add(const Duration(days: 1));
      final values = occurrences.where((occurrence) {
        final local = occurrence.scheduledAt.toLocal();
        return !local.isBefore(date) && local.isBefore(end);
      });
      return (date: date, summary: summarizeAdherence(values, now: now));
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
        child: SizedBox(
          height: 190,
          child: SingleChildScrollView(
            reverse: true,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: dayValues.map((entry) {
                final summary = entry.summary;
                final hasData = summary.completed > 0;
                final height = hasData
                    ? math.max(12.0, summary.adherence * 120)
                    : 8.0;
                return SizedBox(
                  width: days == 7 ? 47 : 36,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (hasData)
                        Text(
                          '${(summary.adherence * 100).round()}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      const SizedBox(height: 5),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 22,
                        height: height,
                        decoration: BoxDecoration(
                          color: hasData ? AppColors.primary : AppColors.border,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.date.day.toString(),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.occurrences, required this.now});

  final List<DoseOccurrence> occurrences;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var index = 0; index < math.min(occurrences.length, 12); index++)
            _HistoryRow(
              occurrence: occurrences[index],
              now: now,
              showDivider: index < math.min(occurrences.length, 12) - 1,
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.occurrence,
    required this.now,
    required this.showDivider,
  });

  final DoseOccurrence occurrence;
  final DateTime now;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final state = occurrence.effectiveState(now: now);
    final presentation = doseStatePresentation(state);
    final local = occurrence.scheduledAt.toLocal();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: presentation.background,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.medication_rounded,
                  color: presentation.foreground,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      occurrence.medicationName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${MaterialLocalizations.of(context).formatShortDate(local)} • ${formatOccurrenceTime(context, local)} • ${occurrence.dosage}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: presentation.label,
                foreground: presentation.foreground,
                background: presentation.background,
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 70),
      ],
    );
  }
}
