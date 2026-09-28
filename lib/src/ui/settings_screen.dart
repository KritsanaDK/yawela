import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/notification_service.dart';
import '../services/purchase_service.dart';
import 'app_theme.dart';
import 'common_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.purchases,
    required this.reminderSync,
    required this.freeMedicationLimit,
    required this.onOpenPremium,
    required this.onRequestNotifications,
    required this.onResyncReminders,
  });

  final PurchaseService purchases;
  final ReminderSyncResult? reminderSync;
  final int freeMedicationLimit;
  final VoidCallback onOpenPremium;
  final Future<void> Function() onRequestNotifications;
  final Future<void> Function() onResyncReminders;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const PageStorageKey('settingsScroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 112),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppPageHeader(
                        title: 'ตั้งค่า',
                        subtitle:
                            'จัดการการแจ้งเตือน สิทธิ์พรีเมียม และข้อมูลแอป',
                      ),
                      const SizedBox(height: 24),
                      AnimatedBuilder(
                        animation: purchases,
                        builder: (context, _) => _PremiumSettingsCard(
                          isPremium: purchases.isPremium,
                          price: purchases.localizedPrice,
                          freeMedicationLimit: freeMedicationLimit,
                          onTap: onOpenPremium,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const SectionTitle(title: 'การแจ้งเตือน'),
                      const SizedBox(height: 10),
                      Card(
                        child: Column(
                          children: [
                            _SettingsTile(
                              icon: Icons.notifications_active_outlined,
                              title: 'สิทธิ์การแจ้งเตือน',
                              subtitle: _notificationStatus(reminderSync),
                              trailing: TextButton(
                                onPressed: onRequestNotifications,
                                child: const Text('ตรวจสอบ'),
                              ),
                            ),
                            const Divider(height: 1, indent: 68),
                            _SettingsTile(
                              icon: Icons.schedule_send_outlined,
                              title: 'ซิงก์ตารางเตือน',
                              subtitle: reminderSync == null
                                  ? 'ยังไม่ได้ตรวจสอบ'
                                  : '${reminderSync!.scheduledPatternCount} ตาราง • ${reminderSync!.timeZoneIdentifier}',
                              trailing: IconButton(
                                tooltip: 'ตั้งตารางใหม่',
                                onPressed: onResyncReminders,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const SectionTitle(title: 'ข้อมูลและความเป็นส่วนตัว'),
                      const SizedBox(height: 10),
                      const Card(
                        child: Column(
                          children: [
                            _SettingsTile(
                              icon: Icons.phone_android_rounded,
                              title: 'จัดเก็บในเครื่อง',
                              subtitle:
                                  'ชื่อยา ตาราง และประวัติไม่ถูกส่งขึ้นคลาวด์',
                            ),
                            Divider(height: 1, indent: 68),
                            _SettingsTile(
                              icon: Icons.cloud_off_outlined,
                              title: 'ใช้งานออฟไลน์',
                              subtitle:
                                  'เตือนยาและบันทึกประวัติได้โดยไม่ใช้อินเทอร์เน็ต',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Card(
                        color: Color(0xFFFFF8E9),
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.health_and_safety_outlined,
                                color: AppColors.warning,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ข้อควรทราบ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'แอปนี้ช่วยเตือนและบันทึกเท่านั้น ไม่ใช้แทนคำแนะนำจากแพทย์หรือเภสัชกร หากลืมทานยา โปรดปรึกษาผู้เชี่ยวชาญก่อนเพิ่มขนาดยา',
                                      style: TextStyle(
                                        color: AppColors.muted,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        '${AppConfig.appName} • เวอร์ชัน ${AppConfig.version}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
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

String _notificationStatus(ReminderSyncResult? result) {
  if (result == null) return 'ยังไม่ได้ตรวจสอบสิทธิ์';
  if (!result.notificationsGranted) return 'ปิดอยู่ — แตะเพื่อตั้งค่า';
  if (result.exactAlarmPermissionGranted == false) {
    return 'เปิดอยู่ • เวลาอาจคลาดเคลื่อนเล็กน้อย';
  }
  return result.usedExactScheduling ? 'เปิดอยู่ • เตือนตรงเวลา' : 'เปิดอยู่';
}

class _PremiumSettingsCard extends StatelessWidget {
  const _PremiumSettingsCard({
    required this.isPremium,
    required this.price,
    required this.freeMedicationLimit,
    required this.onTap,
  });

  final bool isPremium;
  final String? price;
  final int freeMedicationLimit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: isPremium
                      ? const Color(0xFFE4F5EC)
                      : const Color(0xFFFFF1D9),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  isPremium
                      ? Icons.verified_rounded
                      : Icons.workspace_premium_rounded,
                  color: isPremium ? AppColors.taken : AppColors.warning,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPremium ? 'พรีเมียมถาวร' : 'แพ็กเกจฟรี',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isPremium
                          ? 'เพิ่มยาได้ไม่จำกัดแล้ว'
                          : 'ใช้ฟรี $freeMedicationLimit รายการ • ปลดล็อก${price == null ? '' : ' $price'}ครั้งเดียว',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
