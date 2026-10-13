import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../config/app_constants.dart';

class NotificationService {
  NotificationService(
    this._preferences, {
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _enabledKey = 'daily_reminder_enabled';
  static const _hourKey = 'daily_reminder_hour';
  static const _minuteKey = 'daily_reminder_minute';
  static const _titleKey = 'daily_reminder_title';
  static const _bodyKey = 'daily_reminder_body';
  final SharedPreferences _preferences;
  final FlutterLocalNotificationsPlugin _plugin;
  bool get enabled => _preferences.getBool(_enabledKey) ?? false;
  int get reminderHour =>
      _preferences.getInt(_hourKey) ?? AppConstants.defaultReminderHour;
  int get reminderMinute =>
      _preferences.getInt(_minuteKey) ?? AppConstants.defaultReminderMinute;

  Future<void> initialize() async {
    if (kIsWeb) return;
    tz.initializeTimeZones();
    if (!Platform.isWindows && !Platform.isLinux) {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
    bool skipToday = false,
  }) async {
    if (kIsWeb) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (skipToday || !next.isAfter(now)) {
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      next = tz.TZDateTime(
        tz.local,
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        hour,
        minute,
      );
    }
    await _plugin.cancel(id: 1001);
    await _plugin.zonedSchedule(
      id: 1001,
      title: title,
      body: body,
      scheduledDate: next,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_frame',
          'Daily frame reminder',
          channelDescription: 'Reminds you to capture your daily frame',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    await _preferences.setBool(_enabledKey, true);
    await _preferences.setInt(_hourKey, hour);
    await _preferences.setInt(_minuteKey, minute);
    await _preferences.setString(_titleKey, title);
    await _preferences.setString(_bodyKey, body);
  }

  Future<void> skipTodayForPhoto(DateTime capturedAt) async {
    if (!enabled) return;

    final now = tz.TZDateTime.now(tz.local);
    final localCapture = capturedAt.toLocal();
    if (localCapture.year != now.year ||
        localCapture.month != now.month ||
        localCapture.day != now.day) {
      return;
    }

    final reminderToday = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminderHour,
      reminderMinute,
    );
    final captureTime = tz.TZDateTime.from(localCapture, tz.local);
    if (!captureTime.isBefore(reminderToday) || !now.isBefore(reminderToday)) {
      return;
    }

    final title = _preferences.getString(_titleKey);
    final body = _preferences.getString(_bodyKey);
    if (title == null || body == null) return;

    await scheduleDaily(
      hour: reminderHour,
      minute: reminderMinute,
      title: title,
      body: body,
      skipToday: true,
    );
  }

  Future<void> cancelDaily() async {
    await _preferences.setBool(_enabledKey, false);
    await _plugin.cancel(id: 1001);
  }
}
