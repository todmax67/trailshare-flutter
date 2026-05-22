import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/data/models/weekly_challenge.dart';

void main() {
  group('WeekBoundaries.forNow', () {
    test('starts on Monday for a Wednesday "now"', () {
      // 2026-04-15 è un mercoledì
      final wed = DateTime(2026, 4, 15, 14, 30);
      final wb = WeekBoundaries.forNow(wed);
      expect(wb.start.weekday, DateTime.monday);
      expect(wb.start.year, 2026);
      expect(wb.start.month, 4);
      expect(wb.start.day, 13); // lunedì 13/04/2026
    });

    test('Monday "now" yields the same Monday as start', () {
      final mon = DateTime(2026, 4, 13, 9);
      final wb = WeekBoundaries.forNow(mon);
      expect(wb.start.day, 13);
      expect(wb.start.weekday, DateTime.monday);
    });

    test('Sunday "now" still wraps to the previous Monday', () {
      // Domenica 2026-04-19
      final sun = DateTime(2026, 4, 19, 23);
      final wb = WeekBoundaries.forNow(sun);
      expect(wb.start.day, 13);
      expect(wb.start.weekday, DateTime.monday);
    });

    test('start is at midnight (00:00:00)', () {
      final wb = WeekBoundaries.forNow(DateTime(2026, 4, 15, 14, 30, 22));
      expect(wb.start.hour, 0);
      expect(wb.start.minute, 0);
      expect(wb.start.second, 0);
    });

    test('end is just before next Monday (Sunday 23:59:59.999)', () {
      final wb = WeekBoundaries.forNow(DateTime(2026, 4, 15));
      // end = monday + 7d - 1ms → domenica 23:59:59.999
      final nextMonday = wb.start.add(const Duration(days: 7));
      expect(wb.end.isBefore(nextMonday), isTrue);
      // ma a meno di 1s da nextMonday
      expect(nextMonday.difference(wb.end).inMilliseconds, lessThanOrEqualTo(1));
    });

    test('week duration is 7 days minus 1ms', () {
      final wb = WeekBoundaries.forNow(DateTime(2026, 4, 15));
      final span = wb.end.difference(wb.start);
      expect(span.inDays, 6);
      expect(span.inMilliseconds, const Duration(days: 7).inMilliseconds - 1);
    });
  });

  group('WeekBoundaries.isoWeekId', () {
    test('format is YYYY-WW with zero-padded week', () {
      // Settimana 1 di gennaio 2026
      final wb = WeekBoundaries.forNow(DateTime(2026, 1, 5));
      expect(wb.isoWeekId, matches(RegExp(r'^\d{4}-\d{2}$')));
      expect(wb.isoWeekId.startsWith('2026-'), isTrue);
    });

    test('different weeks of the same year produce different IDs', () {
      final w1 = WeekBoundaries.forNow(DateTime(2026, 1, 5));
      final w2 = WeekBoundaries.forNow(DateTime(2026, 6, 1));
      final w3 = WeekBoundaries.forNow(DateTime(2026, 12, 28));
      expect({w1.isoWeekId, w2.isoWeekId, w3.isoWeekId}.length, 3);
    });

    test('two days in the same week produce the same ID', () {
      final mon = WeekBoundaries.forNow(DateTime(2026, 4, 13));
      final wed = WeekBoundaries.forNow(DateTime(2026, 4, 15));
      final sun = WeekBoundaries.forNow(DateTime(2026, 4, 19));
      expect(mon.isoWeekId, wed.isoWeekId);
      expect(mon.isoWeekId, sun.isoWeekId);
    });
  });
}
