import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'voteaxis_api.dart';

/// A daily local notification pointing at the Issue of the Day.
///
/// Entirely on-device: the schedule lives in the OS's notification tray, the
/// content comes from the same cached Issue of the Week the widget shows, and
/// no server ever learns that reminders exist. Turning the setting off cancels
/// the pending notification outright — there is nothing to "unsubscribe" from
/// because nothing was ever subscribed.
class IssueReminder {
  IssueReminder._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Single pending notification — each reschedule replaces the last so the
  /// body always shows the current week's headline.
  static const _id = 4107;
  static const _channelId = 'issue_of_the_day';
  static const _channelName = 'Issue of the Day';
  static const _channelDescription =
      'A daily nudge to read and weigh in on the issue of the day.';

  /// The local hour the reminder fires at. Kept as a constant rather than a
  /// user setting — a time picker is a lot of UI for a courtesy nudge, and 9am
  /// clears both "too early" and "commute over" complaints.
  static const reminderHour = 9;

  /// The next `reminderHour` o'clock strictly after [now], in local time.
  /// Pure so the edge cases (before 9, exactly 9, after 9) are testable.
  static tz.TZDateTime nextReminderTime(DateTime now) {
    final local = tz.TZDateTime.from(now, tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      local.year,
      local.month,
      local.day,
      reminderHour,
    );
    if (!scheduled.isAfter(local)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Initialize the plugin and the timezone database. Safe to call more than
  /// once; only the first call does work.
  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    // iOS init defaults would request permission immediately — that prompts
    // at cold start, long before the user has seen the reminder toggle. Defer
    // to the explicit request in setEnabled(true).
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// Enable or disable the daily nudge. Returns whether reminders are now
  /// armed — on iOS/Android the user can decline the permission prompt, in
  /// which case the toggle reports back as off so settings don't lie.
  static Future<bool> setEnabled(bool enabled, {IssueOfTheWeek? week}) async {
    await init();
    if (!enabled) {
      await _plugin.cancel(id: _id);
      return false;
    }
    final granted = await _requestPermission();
    if (!granted) return false;
    await _schedule(week);
    return true;
  }

  /// Refresh the pending notification's copy after the week's issue changes.
  /// No-op when reminders are off — there is no pending notification to update.
  static Future<void> refreshContent(IssueOfTheWeek? week) async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    if (!pending.any((r) => r.id == _id)) return;
    await _schedule(week);
  }

  static Future<bool> _requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  static Future<void> _schedule(IssueOfTheWeek? week) async {
    final body = week == null
        ? 'A fresh issue is up — see where you land.'
        : week.headline;
    await _plugin.zonedSchedule(
      id: _id,
      title: 'Issue of the Day',
      body: body,
      scheduledDate: nextReminderTime(DateTime.now()),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // Inexact on purpose: a daily nudge does not need wake-the-device
      // precision, and inexact scheduling needs no special alarm permission.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    debugPrint(
      'IssueReminder: scheduled at ${nextReminderTime(DateTime.now())}',
    );
  }
}
