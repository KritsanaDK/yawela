import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/medication.dart';
import 'reminder_schedule_planner.dart';

/// Result of asking the operating system for reminder permissions.
final class ReminderPermissionResult {
  const ReminderPermissionResult({
    required this.notificationsGranted,
    required this.exactAlarmPermissionGranted,
  });

  /// Whether the app may display notifications.
  final bool notificationsGranted;

  /// Android's exact-alarm access, or `null` when it is not applicable.
  final bool? exactAlarmPermissionGranted;

  /// Whether every permission needed for precise reminders is available.
  bool get isFullyGranted =>
      notificationsGranted && exactAlarmPermissionGranted != false;
}

/// Summary of a complete reminder reconciliation.
final class ReminderSyncResult {
  const ReminderSyncResult({
    required this.requestedPatternCount,
    required this.scheduledPatternCount,
    required this.failedPatternCount,
    required this.limitedPatternCount,
    required this.patternLimit,
    required this.notificationsGranted,
    required this.exactAlarmPermissionGranted,
    required this.usedExactScheduling,
    required this.timeZoneIdentifier,
  });

  /// Number of active one-shot or repeating entries represented by local data.
  final int requestedPatternCount;

  /// Number of patterns successfully handed to the operating system.
  final int scheduledPatternCount;

  /// Number of patterns the operating system rejected while scheduling.
  final int failedPatternCount;

  /// Number omitted to remain below the platform-safe pending-request limit.
  final int limitedPatternCount;

  /// Maximum number of repeating reminder patterns this service schedules.
  final int patternLimit;

  /// Whether the app may display notifications.
  final bool notificationsGranted;

  /// Android's exact-alarm access, or `null` when it is not applicable.
  final bool? exactAlarmPermissionGranted;

  /// Whether Android reminders were scheduled exactly while idle.
  final bool usedExactScheduling;

  /// IANA time-zone identifier used to calculate wall-clock reminders.
  final String timeZoneIdentifier;

  bool get wasLimited => limitedPatternCount > 0;
}

/// Schedules medication reminders from the app's local source of truth.
abstract interface class ReminderService {
  Future<void> initialize();

  Future<ReminderPermissionResult> requestPermissions();

  Future<ReminderSyncResult> sync(List<Medication> medications);

  Future<void> cancelAll();

  void dispose();
}

/// Offline reminder implementation backed by each platform's notification API.
final class LocalReminderService implements ReminderService {
  LocalReminderService({
    FlutterLocalNotificationsPlugin? notifications,
    ReminderSchedulePlanner? planner,
  }) : _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       _planner = planner ?? const ReminderSchedulePlanner();

  static const int maxScheduledPatterns = 60;
  static const String _channelId = 'medication_reminders_v1';
  static const String _channelName = 'เตือนทานยา';
  static const String _channelDescription = 'แจ้งเตือนตามเวลาทานยา';

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
      );

  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      icon: 'ic_stat_medication',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.active,
      threadIdentifier: 'medication-reminders',
    ),
  );

  final FlutterLocalNotificationsPlugin _notifications;
  final ReminderSchedulePlanner _planner;

  Future<void>? _initialization;
  String _timeZoneIdentifier = 'Etc/UTC';

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    await _refreshTimeZone();

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_medication'),
        iOS: IOSInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    if (_isAndroid) {
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_androidChannel);
    }
  }

  @override
  Future<ReminderPermissionResult> requestPermissions() async {
    await initialize();

    if (_isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();

      bool exactGranted =
          await android?.canScheduleExactNotifications() ?? false;
      if (await android?.areNotificationsEnabled() == true && !exactGranted) {
        await android?.requestExactAlarmsPermission();
        exactGranted = await android?.canScheduleExactNotifications() ?? false;
      }

      return ReminderPermissionResult(
        notificationsGranted: await android?.areNotificationsEnabled() ?? false,
        exactAlarmPermissionGranted: exactGranted,
      );
    }

    if (_isIOS) {
      final IOSFlutterLocalNotificationsPlugin? ios = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
      final NotificationsEnabledOptions? settings = await ios
          ?.checkPermissions();
      return ReminderPermissionResult(
        notificationsGranted: settings?.isEnabled ?? false,
        exactAlarmPermissionGranted: null,
      );
    }

    return const ReminderPermissionResult(
      notificationsGranted: true,
      exactAlarmPermissionGranted: null,
    );
  }

  @override
  Future<ReminderSyncResult> sync(List<Medication> medications) async {
    await initialize();
    await _refreshTimeZone();

    final patterns = _planner.build(medications, location: tz.local)
      ..sort((a, b) {
        final int byTime = a.nextOccurrence.compareTo(b.nextOccurrence);
        return byTime == 0 ? a.key.compareTo(b.key) : byTime;
      });
    final int limitedPatternCount = patterns.length > maxScheduledPatterns
        ? patterns.length - maxScheduledPatterns
        : 0;
    final selectedPatterns = patterns
        .take(maxScheduledPatterns)
        .toList(growable: false);
    final ReminderPermissionResult permissions = await _readPermissions();

    await _notifications.cancelAllPendingNotifications();

    if (!permissions.notificationsGranted) {
      return ReminderSyncResult(
        requestedPatternCount: patterns.length,
        scheduledPatternCount: 0,
        failedPatternCount: 0,
        limitedPatternCount: limitedPatternCount,
        patternLimit: maxScheduledPatterns,
        notificationsGranted: false,
        exactAlarmPermissionGranted: permissions.exactAlarmPermissionGranted,
        usedExactScheduling: false,
        timeZoneIdentifier: _timeZoneIdentifier,
      );
    }

    final bool useExactScheduling =
        _isAndroid && permissions.exactAlarmPermissionGranted == true;
    final AndroidScheduleMode androidScheduleMode = useExactScheduling
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final Set<int> allocatedIds = <int>{};
    int scheduledPatternCount = 0;
    int failedPatternCount = 0;

    for (final pattern in selectedPatterns) {
      final int notificationId = _allocateNotificationId(
        pattern.key,
        allocatedIds,
      );
      try {
        await _notifications.zonedSchedule(
          id: notificationId,
          title: 'ถึงเวลาทานยา',
          body: _notificationBody(pattern.medication),
          scheduledDate: pattern.nextOccurrence,
          notificationDetails: _notificationDetails,
          androidScheduleMode: androidScheduleMode,
          matchDateTimeComponents: switch (pattern.repeat) {
            ReminderRepeat.none => null,
            ReminderRepeat.daily => DateTimeComponents.time,
            ReminderRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
          },
          payload: pattern.medication.id.toString(),
        );
        scheduledPatternCount += 1;
      } on Object {
        failedPatternCount += 1;
      }
    }

    return ReminderSyncResult(
      requestedPatternCount: patterns.length,
      scheduledPatternCount: scheduledPatternCount,
      failedPatternCount: failedPatternCount,
      limitedPatternCount: limitedPatternCount,
      patternLimit: maxScheduledPatterns,
      notificationsGranted: true,
      exactAlarmPermissionGranted: permissions.exactAlarmPermissionGranted,
      usedExactScheduling: useExactScheduling,
      timeZoneIdentifier: _timeZoneIdentifier,
    );
  }

  Future<ReminderPermissionResult> _readPermissions() async {
    if (_isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return ReminderPermissionResult(
        notificationsGranted: await android?.areNotificationsEnabled() ?? false,
        exactAlarmPermissionGranted:
            await android?.canScheduleExactNotifications() ?? false,
      );
    }

    if (_isIOS) {
      final NotificationsEnabledOptions? settings = await _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return ReminderPermissionResult(
        notificationsGranted: settings?.isEnabled ?? false,
        exactAlarmPermissionGranted: null,
      );
    }

    return const ReminderPermissionResult(
      notificationsGranted: true,
      exactAlarmPermissionGranted: null,
    );
  }

  Future<void> _refreshTimeZone() async {
    try {
      final TimezoneInfo timeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZone.identifier));
      _timeZoneIdentifier = timeZone.identifier;
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Unable to refresh the device time zone: $error');
      }
      _timeZoneIdentifier = tz.local.name;
    }
  }

  static String _notificationBody(Medication medication) {
    final List<String> details = <String>[
      medication.name,
      if (medication.dosage.isNotEmpty) medication.dosage,
      if (medication.instructions.isNotEmpty) medication.instructions,
    ];
    if (details.length == 1) {
      return details.single;
    }
    return details.join(' • ');
  }

  static int _allocateNotificationId(String key, Set<int> allocatedIds) {
    int id = _stableHash(key);
    while (!allocatedIds.add(id)) {
      id = id == 0x7fffffff ? 1 : id + 1;
    }
    return id;
  }

  static int _stableHash(String value) {
    int hash = 0x811c9dc5;
    for (final int codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  @override
  Future<void> cancelAll() async {
    await initialize();
    await _notifications.cancelAll();
  }

  @override
  void dispose() {}
}
