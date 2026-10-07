import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:voteaxis/services/issue_reminder.dart';

void main() {
  setUpAll(() {
    // nextReminderTime resolves through tz.local — give it a deterministic
    // zone so the math below doesn't depend on the host machine.
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Detroit'));
  });

  // Inputs are TZDateTimes in the pinned zone — a plain `DateTime(...)`
  // would be read in the host machine's zone, which is UTC in CI.
  tz.TZDateTime at(int month, int day, [int hour = 0, int minute = 0]) =>
      tz.TZDateTime(tz.local, 2026, month, day, hour, minute);

  test('before 9am schedules for 9am the same day', () {
    final t = IssueReminder.nextReminderTime(at(8, 14, 7, 30));
    expect(t.hour, IssueReminder.reminderHour);
    expect(t.day, 14);
  });

  test('after 9am rolls to the next day', () {
    final t = IssueReminder.nextReminderTime(at(8, 14, 15));
    expect(t.day, 15);
    expect(t.hour, IssueReminder.reminderHour);
    expect(t.minute, 0);
  });

  test(
    'exactly 9am also rolls — the reminder must be strictly in the future',
    () {
      final t = IssueReminder.nextReminderTime(at(8, 14, 9));
      expect(t.day, 15);
    },
  );

  test('month and year boundaries roll correctly', () {
    final t = IssueReminder.nextReminderTime(at(8, 31, 22));
    expect(t.month, 9);
    expect(t.day, 1);
    final yearEnd = IssueReminder.nextReminderTime(at(12, 31, 18));
    expect(yearEnd.year, 2027);
    expect(yearEnd.day, 1);
  });
}
