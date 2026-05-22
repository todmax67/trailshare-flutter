import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailshare_flutter/core/constants/pro_products.dart';
import 'package:trailshare_flutter/core/services/pro_gate_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProGateService gate;

  setUp(() {
    gate = ProGateService();
    gate.resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  group('ProGateService.load', () {
    test('default _unlocked is true (closed-testing default)', () async {
      await gate.load();
      // Su darwin (host di test) i rami Platform.isAndroid/iOS non si
      // attivano, quindi isPro riflette _unlocked direttamente.
      expect(gate.isPro, isTrue);
      expect(gate.isLoaded, isTrue);
    });

    test('reads previously stored unlocked=false', () async {
      SharedPreferences.setMockInitialValues({'pro_unlocked': false});
      await gate.load();
      expect(gate.isPro, isFalse);
    });

    test('reads previously stored productId', () async {
      SharedPreferences.setMockInitialValues({
        'pro_unlocked': true,
        'pro_current_product_id': ProProducts.yearly,
      });
      await gate.load();
      expect(gate.currentProductId, ProProducts.yearly);
      expect(gate.isYearly, isTrue);
      expect(gate.isMonthly, isFalse);
    });

    test('is idempotent (second call is a no-op)', () async {
      SharedPreferences.setMockInitialValues({'pro_unlocked': false});
      await gate.load();
      // Cambia il backing store: la seconda load() non deve rileggerlo.
      SharedPreferences.setMockInitialValues({'pro_unlocked': true});
      await gate.load();
      expect(gate.isPro, isFalse);
    });
  });

  group('ProGateService.setUnlocked', () {
    test('persists the new value to SharedPreferences', () async {
      await gate.setUnlocked(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pro_unlocked'), isFalse);
    });

    test('does not notify when value is unchanged', () async {
      await gate.setUnlocked(true);
      int notifications = 0;
      gate.addListener(() => notifications++);
      await gate.setUnlocked(true);
      expect(notifications, 0);
    });

    test('notifies listeners on actual change', () async {
      await gate.setUnlocked(true);
      int notifications = 0;
      gate.addListener(() => notifications++);
      await gate.setUnlocked(false);
      expect(notifications, 1);
    });

    test('clears currentProductId when set to false', () async {
      await gate.setCurrentProductId(ProProducts.monthly);
      expect(gate.currentProductId, ProProducts.monthly);
      await gate.setUnlocked(false);
      expect(gate.currentProductId, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pro_current_product_id'), isNull);
    });

    test('does NOT clear productId when set to true', () async {
      await gate.setCurrentProductId(ProProducts.monthly);
      await gate.setUnlocked(true);
      // Era già true (default) ma il side-effect non deve attivarsi.
      // Rimettiamolo prima a false poi a true:
      await gate.setUnlocked(false);
      await gate.setCurrentProductId(ProProducts.monthly);
      await gate.setUnlocked(true);
      expect(gate.currentProductId, ProProducts.monthly);
    });
  });

  group('ProGateService.setCurrentProductId', () {
    test('persists the productId', () async {
      await gate.setCurrentProductId(ProProducts.yearly);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pro_current_product_id'), ProProducts.yearly);
    });

    test('null removes the stored productId', () async {
      await gate.setCurrentProductId(ProProducts.yearly);
      await gate.setCurrentProductId(null);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pro_current_product_id'), isNull);
    });

    test('isMonthly / isYearly reflect the current productId', () async {
      await gate.setCurrentProductId(ProProducts.monthly);
      expect(gate.isMonthly, isTrue);
      expect(gate.isYearly, isFalse);

      await gate.setCurrentProductId(ProProducts.yearly);
      expect(gate.isMonthly, isFalse);
      expect(gate.isYearly, isTrue);
    });

    test('does not notify when productId is unchanged', () async {
      await gate.setCurrentProductId(ProProducts.monthly);
      int notifications = 0;
      gate.addListener(() => notifications++);
      await gate.setCurrentProductId(ProProducts.monthly);
      expect(notifications, 0);
    });
  });
}
