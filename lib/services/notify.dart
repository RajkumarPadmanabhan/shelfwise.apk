import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';
import '../data/store.dart';
import '../theme.dart';

/// Local reminders for to-dos and an optional evening reading nudge.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Timer? _debounce;

  static NotificationDetails get _todoDetails => NotificationDetails(
    android: AndroidNotificationDetails(
      'todos',
      'To-do reminders',
      channelDescription: 'Reminders for your reading to-dos',
      importance: Importance.high,
      priority: Priority.high,
      color: C.brown,
      icon: 'ic_stat_shelfwise',
    ),
  );

  static NotificationDetails get _nudgeDetails => NotificationDetails(
    android: AndroidNotificationDetails(
      'nudge',
      'Reading nudge',
      channelDescription: 'A gentle evening reminder to read',
      importance: Importance.defaultImportance,
      color: C.brown,
      icon: 'ic_stat_shelfwise',
    ),
  );

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {}
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_shelfwise')),
      );
      _ready = true;
      store.addListener(_queueSync);
      unawaited(sync());
    } catch (e) {
      debugPrint('Shelfwise: notifications unavailable: $e');
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Asks Android 13+ for permission. Returns whether notifications are allowed.
  static Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  static void _queueSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), sync);
  }

  static String _sig = '';

  /// Re-schedules every reminder from the current data.
  static Future<void> sync() async {
    if (!_ready) return;
    final s = store.settings;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final openTodos = s.reminders ? store.todos.where((t) => !t.done).toList() : <Todo>[];
    final sig = '${s.dailyNudge}|${openTodos.map((t) => '${t.id}:${t.due}:${t.text}').join(',')}';
    if (sig == _sig) return;
    _sig = sig;
    try {
      await _plugin.cancelAllPendingNotifications();
      var id = 100;
      for (final t in openTodos.take(60)) {
        if (t.due != null && t.dueAt != null) {
          final dueAt = t.dueAt!;
          final oneHourBefore = dueAt.subtract(const Duration(hours: 1));
          // 1 hour before reminder
          if (oneHourBefore.isAfter(now)) {
            await _plugin.zonedSchedule(
              id: id++,
              scheduledDate: tz.TZDateTime.from(oneHourBefore, tz.local),
              notificationDetails: _todoDetails,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              title: '⏰ Starting in 1 hr',
              body: '${t.text} starts in 1 hr',
            );
          }
          // At due time
          if (dueAt.isAfter(now)) {
            await _plugin.zonedSchedule(
              id: id++,
              scheduledDate: tz.TZDateTime.from(dueAt, tz.local),
              notificationDetails: _todoDetails,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              title: t.book.isEmpty ? 'To-do reminder' : '📖 ${t.book}',
              body: t.text,
            );
          }
        } else {
          // If user didn't click 'due' button, schedule a reminder for today
          final created = DateTime.fromMillisecondsSinceEpoch(t.createdAt);
          if (created.isAfter(todayStart)) {
            var remindAt = created.add(const Duration(hours: 1));
            if (!remindAt.isAfter(now)) {
              remindAt = now.add(const Duration(hours: 1));
            }
            await _plugin.zonedSchedule(
              id: id++,
              scheduledDate: tz.TZDateTime.from(remindAt, tz.local),
              notificationDetails: _todoDetails,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              title: 'To-do reminder',
              body: '${t.text} starts in 1 hr',
            );
          }
        }
      }
      if (s.dailyNudge) {
        final l = tz.TZDateTime.now(tz.local);
        var at = tz.TZDateTime(tz.local, l.year, l.month, l.day, 20);
        if (!at.isAfter(l)) at = at.add(const Duration(days: 1));
        await _plugin.zonedSchedule(
          id: 1,
          scheduledDate: at,
          notificationDetails: _nudgeDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: 'Time to read 📖',
          body: 'Even ten pages count. Your shelf misses you, ${store.profile.first}.',
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (e) {
      debugPrint('Shelfwise: scheduling failed: $e');
    }
  }
}
