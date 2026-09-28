import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../controllers/app_controller.dart';
import '../domain/domain.dart';
import 'app_theme.dart';
import 'medication_form_page.dart';
import 'medications_screen.dart';
import 'premium_page.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';
import 'today_screen.dart';

enum _AppDestination {
  today(Icons.today_outlined, Icons.today_rounded, 'วันนี้'),
  medications(Icons.medication_outlined, Icons.medication_rounded, 'รายการยา'),
  statistics(Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'สถิติ'),
  settings(Icons.settings_outlined, Icons.settings_rounded, 'ตั้งค่า');

  const _AppDestination(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  _AppDestination _selectedDestination = _AppDestination.today;

  AppController get controller => widget.controller;
  int get _selectedIndex => _selectedDestination.index;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.refreshForResume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.isLoading) return const _StartupScreen();
        if (controller.startupError != null) {
          return _StartupErrorScreen(onRetry: controller.retryStartup);
        }

        final pages = <Widget>[
          TodayScreen(
            medications: controller.medications,
            occurrences: controller.todayOccurrences,
            now: controller.now,
            reminderSync: controller.reminderSync,
            onAddMedication: () => _openMedicationForm(),
            onMarkTaken: _markTaken,
            onMarkSkipped: _markSkipped,
            onUndo: _undoDose,
            onRequestNotifications: _requestNotifications,
          ),
          MedicationsScreen(
            medications: controller.medications,
            isPremium: controller.isPremium,
            freeMedicationLimit: controller.freeMedicationLimit,
            onAdd: () => _openMedicationForm(),
            onEdit: (medication) => _openMedicationForm(medication),
            onToggleActive: _toggleMedication,
            onArchive: _archiveMedication,
            onUpgrade: _openPremium,
          ),
          StatisticsScreen(
            occurrences: controller.occurrences,
            now: controller.now,
          ),
          SettingsScreen(
            purchases: controller.purchases,
            reminderSync: controller.reminderSync,
            freeMedicationLimit: controller.freeMedicationLimit,
            onOpenPremium: _openPremium,
            onRequestNotifications: _requestNotifications,
            onResyncReminders: _resyncReminders,
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Scaffold(
              body: Stack(
                children: [
                  if (wide)
                    Row(
                      children: [
                        _AppNavigationRail(
                          selectedIndex: _selectedIndex,
                          onDestinationSelected: _selectPage,
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: IndexedStack(
                            index: _selectedIndex,
                            children: pages,
                          ),
                        ),
                      ],
                    )
                  else
                    IndexedStack(index: _selectedIndex, children: pages),
                  if (controller.isBusy)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                ],
              ),
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectPage,
                      destinations: _AppDestination.values
                          .map(
                            (destination) => NavigationDestination(
                              icon: Icon(destination.icon),
                              selectedIcon: Icon(destination.selectedIcon),
                              label: destination.label,
                            ),
                          )
                          .toList(growable: false),
                    ),
            );
          },
        );
      },
    );
  }

  void _selectPage(int index) {
    setState(() => _selectedDestination = _AppDestination.values[index]);
  }

  Future<void> _openMedicationForm([Medication? medication]) async {
    if (medication == null &&
        !controller.isPremium &&
        controller.currentMedications.length >=
            controller.freeMedicationLimit) {
      await _openPremium();
      return;
    }

    final result = await Navigator.of(context).push<Medication>(
      MaterialPageRoute(
        builder: (_) => MedicationFormPage(initialMedication: medication),
      ),
    );
    if (result == null || !mounted) return;

    try {
      if (medication == null) {
        await controller.createMedication(result);
        if (!mounted) return;
        _showMessage('เพิ่ม “${result.name}” แล้ว');
        if (controller.reminderSync?.notificationsGranted != true) {
          await _offerNotificationPermission();
        }
      } else {
        await controller.updateMedication(result);
        if (mounted) _showMessage('บันทึกการแก้ไขแล้ว');
      }
    } on MedicationLimitReached {
      if (mounted) await _openPremium();
    } on Object catch (_) {
      if (mounted) _showError('บันทึกรายการยาไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  Future<void> _offerNotificationPermission() async {
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.notifications_active_outlined,
          color: AppColors.primary,
        ),
        title: const Text('เปิดการแจ้งเตือนกินยา'),
        content: const Text(
          'อนุญาตให้${AppConfig.appName}แจ้งเตือนตามเวลาที่ตั้งไว้ แม้แอปไม่ได้เปิดอยู่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ไว้ทีหลัง'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('เปิดการแจ้งเตือน'),
          ),
        ],
      ),
    );
    if (shouldRequest == true) await _requestNotifications();
  }

  Future<void> _requestNotifications() async {
    try {
      final result = await controller.requestReminderPermissions();
      if (!mounted) return;
      if (!result.notificationsGranted) {
        _showError('ยังไม่ได้รับอนุญาตให้แจ้งเตือน กรุณาเปิดในตั้งค่าเครื่อง');
      } else if (result.exactAlarmPermissionGranted == false) {
        _showMessage('เปิดแจ้งเตือนแล้ว แต่เวลาอาจคลาดเคลื่อนเล็กน้อย');
      } else {
        _showMessage('เปิดการแจ้งเตือนเรียบร้อยแล้ว');
      }
    } on Object catch (_) {
      if (mounted) _showError('ตรวจสอบสิทธิ์การแจ้งเตือนไม่สำเร็จ');
    }
  }

  Future<void> _resyncReminders() => _runUiAction(
    action: controller.resyncReminders,
    successMessage: 'ตั้งตารางแจ้งเตือนใหม่แล้ว',
    errorMessage: 'ตั้งตารางแจ้งเตือนไม่สำเร็จ',
  );

  Future<void> _toggleMedication(Medication medication, bool value) =>
      _runUiAction(
        action: () => controller.setMedicationActive(medication, value),
        successMessage: value ? 'เปิดแจ้งเตือนแล้ว' : 'พักรายการยาแล้ว',
        errorMessage: 'เปลี่ยนสถานะไม่สำเร็จ',
      );

  Future<void> _archiveMedication(Medication medication) => _runUiAction(
    action: () => controller.archiveMedication(medication),
    successMessage: 'นำรายการออกแล้ว ประวัติยังคงอยู่',
    errorMessage: 'นำรายการยาออกไม่สำเร็จ',
  );

  Future<void> _markTaken(DoseOccurrence occurrence) => _runUiAction(
    action: () => controller.markTaken(occurrence),
    successMessage: 'บันทึกว่าทานแล้ว',
    errorMessage: 'บันทึกสถานะไม่สำเร็จ',
  );

  Future<void> _markSkipped(DoseOccurrence occurrence) => _runUiAction(
    action: () => controller.markSkipped(occurrence),
    successMessage: 'บันทึกว่าข้ามครั้งนี้',
    errorMessage: 'บันทึกสถานะไม่สำเร็จ',
  );

  Future<void> _undoDose(DoseOccurrence occurrence) => _runUiAction(
    action: () => controller.undoOccurrence(occurrence),
    successMessage: 'คืนสถานะเพื่อบันทึกใหม่แล้ว',
    errorMessage: 'แก้ไขสถานะไม่สำเร็จ',
  );

  Future<void> _runUiAction({
    required Future<void> Function() action,
    required String successMessage,
    required String errorMessage,
  }) async {
    try {
      await action();
      if (mounted) _showMessage(successMessage);
    } on Object catch (_) {
      if (mounted) _showError(errorMessage);
    }
  }

  Future<void> _openPremium() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PremiumPage(
          purchases: controller.purchases,
          freeMedicationLimit: controller.freeMedicationLimit,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(backgroundColor: AppColors.missed, content: Text(message)),
      );
  }
}

class _AppNavigationRail extends StatelessWidget {
  const _AppNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      extended: MediaQuery.sizeOf(context).width >= 1180,
      backgroundColor: Colors.white,
      leading: const Padding(
        padding: EdgeInsets.only(top: 12, bottom: 24),
        child: _AppLogo(),
      ),
      destinations: _AppDestination.values
          .map(
            (destination) => NavigationRailDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: Text(destination.label),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.medication_rounded,
            color: Colors.white,
            size: 23,
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 1180) ...[
          const SizedBox(width: 10),
          const Text(
            AppConfig.appName,
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ],
      ],
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AppLogo(),
            SizedBox(height: 24),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 14),
            Text('กำลังเตรียมข้อมูลในเครื่อง…'),
          ],
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storage_rounded,
                    size: 56,
                    color: AppColors.missed,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'เปิดข้อมูลในเครื่องไม่สำเร็จ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ข้อมูลเดิมยังไม่ถูกลบ กรุณาลองเปิดอีกครั้ง',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('ลองอีกครั้ง'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
