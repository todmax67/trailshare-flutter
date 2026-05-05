import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/data/models/monthly_report.dart';

void main() {
  group('MonthBoundaries.forYearMonth', () {
    test('start is the 1st at midnight', () {
      final mb = MonthBoundaries.forYearMonth(2026, 4);
      expect(mb.start, DateTime(2026, 4, 1));
    });

    test('end is just before the next month starts', () {
      final mb = MonthBoundaries.forYearMonth(2026, 4);
      // 30 aprile 23:59:59.999
      expect(mb.end.year, 2026);
      expect(mb.end.month, 4);
      expect(mb.end.day, 30);
      expect(mb.end.hour, 23);
      expect(mb.end.minute, 59);
    });

    test('handles December correctly (no rollover)', () {
      final mb = MonthBoundaries.forYearMonth(2026, 12);
      expect(mb.start, DateTime(2026, 12, 1));
      expect(mb.end.year, 2026);
      expect(mb.end.month, 12);
      expect(mb.end.day, 31);
    });

    test('handles February in a leap year (29 days)', () {
      // 2028 è bisestile
      final mb = MonthBoundaries.forYearMonth(2028, 2);
      expect(mb.end.day, 29);
    });

    test('handles February in a non-leap year (28 days)', () {
      final mb = MonthBoundaries.forYearMonth(2026, 2);
      expect(mb.end.day, 28);
    });
  });

  group('MonthBoundaries.forNow', () {
    test('uses the provided "now" parameter', () {
      final mb = MonthBoundaries.forNow(DateTime(2026, 7, 15, 10));
      expect(mb.start.month, 7);
      expect(mb.start.year, 2026);
    });
  });

  group('MonthBoundaries.previous', () {
    test('previous of April is March same year', () {
      final apr = MonthBoundaries.forYearMonth(2026, 4);
      final mar = apr.previous();
      expect(mar.start.year, 2026);
      expect(mar.start.month, 3);
    });

    test('previous of January wraps to December previous year', () {
      final jan = MonthBoundaries.forYearMonth(2026, 1);
      final dec = jan.previous();
      expect(dec.start.year, 2025);
      expect(dec.start.month, 12);
    });

    test('previous of February in a leap year still resolves to January', () {
      final feb = MonthBoundaries.forYearMonth(2028, 2);
      final jan = feb.previous();
      expect(jan.start.year, 2028);
      expect(jan.start.month, 1);
    });
  });

  group('MonthBoundaries.yearMonthId', () {
    test('format is YYYY-MM zero-padded', () {
      expect(MonthBoundaries.forYearMonth(2026, 4).yearMonthId, '2026-04');
      expect(MonthBoundaries.forYearMonth(2026, 12).yearMonthId, '2026-12');
      expect(MonthBoundaries.forYearMonth(2026, 1).yearMonthId, '2026-01');
    });

    test('different months produce different IDs', () {
      final apr = MonthBoundaries.forYearMonth(2026, 4).yearMonthId;
      final may = MonthBoundaries.forYearMonth(2026, 5).yearMonthId;
      expect(apr, isNot(may));
    });

    test('chained .previous() generates a sortable descending sequence', () {
      var b = MonthBoundaries.forYearMonth(2026, 3);
      final ids = <String>[];
      for (int i = 0; i < 6; i++) {
        ids.add(b.yearMonthId);
        b = b.previous();
      }
      // Devono essere in ordine descendente lessicografico (yyyy-mm).
      final sortedDesc = [...ids]..sort((a, b) => b.compareTo(a));
      expect(ids, sortedDesc);
      // E coprire correttamente il rollover anno.
      expect(ids, contains('2025-12'));
      expect(ids, contains('2025-10'));
    });
  });
}
