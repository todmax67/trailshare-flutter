import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailshare_flutter/core/services/feature_tips.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FeatureTipsService service;

  setUp(() {
    service = FeatureTipsService();
    SharedPreferences.setMockInitialValues({});
  });

  group('FeatureTipsService.isTipShown', () {
    test('returns false for a never-seen tip', () async {
      expect(await service.isTipShown('lifeline_intro'), isFalse);
    });

    test('returns true for a previously shown tip', () async {
      await service.markTipShown('lifeline_intro');
      expect(await service.isTipShown('lifeline_intro'), isTrue);
    });

    test('different tip IDs are independent', () async {
      await service.markTipShown('a');
      expect(await service.isTipShown('a'), isTrue);
      expect(await service.isTipShown('b'), isFalse);
    });
  });

  group('FeatureTipsService.markTipShown', () {
    test('persists with the prefix "tip_shown_"', () async {
      await service.markTipShown('xyz');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tip_shown_xyz'), isTrue);
    });

    test('is idempotent (calling twice keeps the flag true)', () async {
      await service.markTipShown('repeat');
      await service.markTipShown('repeat');
      expect(await service.isTipShown('repeat'), isTrue);
    });
  });

  group('FeatureTipsService.resetAllTips', () {
    test('removes only tip-prefixed keys, leaves other prefs untouched',
        () async {
      SharedPreferences.setMockInitialValues({
        'tip_shown_a': true,
        'tip_shown_b': true,
        'unrelated_pref': 'keep me',
        'pro_unlocked': true,
      });

      await service.resetAllTips();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tip_shown_a'), isNull);
      expect(prefs.getBool('tip_shown_b'), isNull);
      // Le altre preferenze sopravvivono.
      expect(prefs.getString('unrelated_pref'), 'keep me');
      expect(prefs.getBool('pro_unlocked'), isTrue);
    });

    test('after reset, isTipShown returns false again', () async {
      await service.markTipShown('foo');
      expect(await service.isTipShown('foo'), isTrue);
      await service.resetAllTips();
      expect(await service.isTipShown('foo'), isFalse);
    });

    test('reset on empty store does not throw', () async {
      await service.resetAllTips();
      expect(await service.isTipShown('any'), isFalse);
    });
  });
}
