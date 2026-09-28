import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/app_config.dart';
import 'controllers/app_controller.dart';
import 'ui/app_shell.dart';
import 'ui/app_theme.dart';
import 'ui/formatters.dart';

class MedicationReminderApp extends StatelessWidget {
  const MedicationReminderApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('th'),
      supportedLocales: const [Locale('th')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: build24HourMediaQuery,
      home: AppShell(controller: controller),
    );
  }
}
