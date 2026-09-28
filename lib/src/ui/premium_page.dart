import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/purchase_service.dart';
import 'app_theme.dart';

class PremiumPage extends StatelessWidget {
  const PremiumPage({
    super.key,
    required this.purchases,
    required this.freeMedicationLimit,
  });

  final PurchaseService purchases;
  final int freeMedicationLimit;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: purchases,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('ปลดล็อก${AppConfig.appName}')),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0C6257), Color(0xFF15937F)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 78,
                              height: 78,
                              decoration: const BoxDecoration(
                                color: Color(0x24FFFFFF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.workspace_premium_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              purchases.isPremium
                                  ? 'ปลดล็อกเรียบร้อยแล้ว'
                                  : 'เพิ่มยาได้ไม่จำกัด',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              purchases.isPremium
                                  ? 'ขอบคุณที่สนับสนุน${AppConfig.appName}'
                                  : 'จ่ายครั้งเดียว ใช้งานได้ถาวร ไม่มีค่าสมาชิกรายเดือน',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFD8F3EC),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              _BenefitRow(
                                icon: Icons.medication_outlined,
                                title: 'รายการยาไม่จำกัด',
                                message:
                                    'จากแพ็กเกจฟรีสูงสุด $freeMedicationLimit รายการ',
                              ),
                              const Divider(height: 28),
                              const _BenefitRow(
                                icon: Icons.cloud_off_outlined,
                                title: 'ข้อมูลทำงานออฟไลน์',
                                message: 'ยา ประวัติ และสถิติอยู่ในเครื่อง',
                              ),
                              const Divider(height: 28),
                              const _BenefitRow(
                                icon: Icons.all_inclusive_rounded,
                                title: 'ซื้อครั้งเดียวจบ',
                                message: 'ไม่ต่ออายุอัตโนมัติและไม่มีรายเดือน',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (purchases.isPremium)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE4F5EC),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                color: AppColors.taken,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'บัญชีร้านค้านี้มีสิทธิ์พรีเมียมแล้ว',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        SizedBox(
                          height: 56,
                          child: FilledButton(
                            key: const Key('buyPremiumButton'),
                            onPressed:
                                purchases.isLoading ||
                                    purchases.isPurchasePending ||
                                    !purchases.productFound
                                ? null
                                : purchases.buyLifetime,
                            child:
                                purchases.isLoading ||
                                    purchases.isPurchasePending
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    purchases.localizedPrice == null
                                        ? 'ซื้อแบบถาวร'
                                        : 'ซื้อแบบถาวร • ${purchases.localizedPrice}',
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: purchases.isLoading
                              ? null
                              : purchases.restorePurchases,
                          child: const Text('กู้คืนการซื้อเดิม'),
                        ),
                        if (!purchases.storeAvailable) ...[
                          const SizedBox(height: 8),
                          const _StoreMessage(
                            message:
                                'ยังเชื่อมต่อร้านค้าไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
                          ),
                        ] else if (!purchases.productFound) ...[
                          const SizedBox(height: 8),
                          const _StoreMessage(
                            message:
                                'ยังไม่พบสินค้าพรีเมียม ต้องสร้างสินค้าใน App Store Connect และ Google Play Console ก่อนทดสอบการซื้อ',
                          ),
                        ] else if (purchases.errorMessage != null) ...[
                          const SizedBox(height: 8),
                          const _StoreMessage(
                            message:
                                'ทำรายการไม่สำเร็จ กรุณาลองใหม่หรือกู้คืนการซื้อเดิม',
                          ),
                        ],
                      ],
                      const SizedBox(height: 18),
                      const Text(
                        'การซื้อและกู้คืนสิทธิ์ต้องเชื่อมต่อ App Store หรือ Google Play เพียงชั่วคราว หลังปลดล็อกแล้วฟังก์ชันหลักยังใช้งานออฟไลน์ได้',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                message,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const Icon(Icons.check_circle_rounded, color: AppColors.taken),
      ],
    );
  }
}

class _StoreMessage extends StatelessWidget {
  const _StoreMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}
