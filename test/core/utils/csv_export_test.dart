import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/csv_export.dart';

void main() {
  group('csvRow (RFC 4180 quoting)', () {
    test('plain values without special chars are not quoted', () {
      expect(csvRow(['foo', 42, 3.14]), 'foo,42,3.14');
    });

    test('values containing comma are quoted', () {
      expect(csvRow(['a,b', 'c']), '"a,b",c');
    });

    test('values containing double quote are quoted with quote doubling', () {
      expect(csvRow(['a"b']), '"a""b"');
    });

    test('values containing newline are quoted', () {
      expect(csvRow(['line1\nline2']), '"line1\nline2"');
    });

    test('values containing carriage return are quoted', () {
      expect(csvRow(['line1\rline2']), '"line1\rline2"');
    });

    test('null values become empty string', () {
      expect(csvRow([null, 'x']), ',x');
    });

    test('empty list returns empty string', () {
      expect(csvRow([]), '');
    });

    test('all special chars combined', () {
      // Una stringa con virgola + apici + newline → quoted, apici doppi
      expect(
        csvRow(['hello, "world"\nfoo']),
        '"hello, ""world""\nfoo"',
      );
    });

    test('numeric and bool values pass through toString', () {
      expect(csvRow([true, false, 0, -1]), 'true,false,0,-1');
    });
  });
}
