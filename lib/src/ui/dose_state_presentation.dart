import 'package:flutter/material.dart';

import '../domain/domain.dart';
import 'app_theme.dart';

final class DoseStatePresentation {
  const DoseStatePresentation({
    required this.label,
    required this.foreground,
    required this.background,
    required this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData icon;
}

DoseStatePresentation doseStatePresentation(DoseEffectiveState state) {
  return switch (state) {
    DoseEffectiveState.taken => const DoseStatePresentation(
      label: 'ทานแล้ว',
      foreground: AppColors.taken,
      background: Color(0xFFE4F5EC),
      icon: Icons.check_rounded,
    ),
    DoseEffectiveState.skipped => const DoseStatePresentation(
      label: 'ข้าม',
      foreground: AppColors.skipped,
      background: Color(0xFFF0F1F3),
      icon: Icons.fast_forward_rounded,
    ),
    DoseEffectiveState.missed => const DoseStatePresentation(
      label: 'เลยเวลา',
      foreground: AppColors.missed,
      background: Color(0xFFFBEAEA),
      icon: Icons.error_outline_rounded,
    ),
    DoseEffectiveState.due => const DoseStatePresentation(
      label: 'ถึงเวลาแล้ว',
      foreground: AppColors.warning,
      background: Color(0xFFFFF3DF),
      icon: Icons.alarm_on_rounded,
    ),
    DoseEffectiveState.upcoming => const DoseStatePresentation(
      label: 'กำลังจะถึง',
      foreground: AppColors.primary,
      background: AppColors.mint,
      icon: Icons.schedule_rounded,
    ),
  };
}
