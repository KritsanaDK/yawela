import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/controllers/app_controller.dart';
import 'src/data/data.dart';
import 'src/services/notification_service.dart';
import 'src/services/purchase_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = MedicationRepository();
  final purchases = PurchaseService(
    loadCachedEntitlement: repository.isPremiumUnlocked,
    persistEntitlement: ({required productId, required transactionId}) async {
      await repository.grantPremium(
        productId: productId,
        transactionId: transactionId,
      );
    },
  );
  final controller = AppController(
    repository: repository,
    reminders: LocalReminderService(),
    purchases: purchases,
  );

  runApp(MedicationReminderApp(controller: controller));
}
