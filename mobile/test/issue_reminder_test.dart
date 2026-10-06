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

  test('before 9am schedules for 9am the same day', () {
    final t = IssueReminder.nextReminderTime(DateTime(2026, 8, 14, 7, 30));
    expect(t.hour, IssueReminder.reminderHour);
    expect(t.day, 14);
  });

  test('after 9am rolls to the next day', () {
    final t = IssueReminder.nextReminderTime(DateTime(2026, 8, 14, 15, 0));
    expect(t.day, 15);
    expect(t.hour, IssueReminder.reminderHour);
    expect(t.minute, 0);
  });

  test('exactly 9am also rolls — the reminder must be strictly in the future', () {
    final t = IssueReminder.nextReminderTime(DateTime(2026, 8, 14, 9, 0));
    expect(t.day, 15);
  });

  test('month and year boundaries roll correctly', () {
    final t = IssueReminder.nextReminderTime(DateTime(2026, 8, 31, 22, 0));
    expect(t.month, 9);
    expect(t.day, 1);
    final yearEnd = IssueReminder.nextReminderTime(DateTime(2026, 12, 31, 18));
    expect(yearEnd.year, 2027);
    expect(yearEnd.day, 1);
  });
}
