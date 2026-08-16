import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/business_caps.dart';
import 'package:trailshare_flutter/data/repositories/groups_repository.dart';

Group makeGroup({
  bool isBusinessGroup = false,
  String tier = 'none',
}) {
  return Group(
    id: 'g1',
    name: 'Test',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
    memberIds: const ['u1'],
    isBusinessGroup: isBusinessGroup,
    businessTier: tier,
  );
}

void main() {
  group('BusinessCaps.applies', () {
    // Semantica cambiata con Sprint B del 2026-05-10 (modello a tre livelli):
    // `applies` non vuol piu' dire "valgono i cap business" ma "valgono dei
    // cap", e per un gruppo normale valgono quelli base. Il test era rimasto
    // alla lettura precedente.
    test('returns true for non-business groups (cap base)', () {
      expect(BusinessCaps.applies(makeGroup()), isTrue);
    });

    test('returns true for verified tier business groups', () {
      expect(
        BusinessCaps.applies(makeGroup(isBusinessGroup: true, tier: 'verified')),
        isTrue,
      );
    });

    test('returns true for trial tier business groups', () {
      expect(
        BusinessCaps.applies(makeGroup(isBusinessGroup: true, tier: 'trial')),
        isTrue,
      );
    });

    test('returns false for pro/enterprise (no caps)', () {
      expect(
        BusinessCaps.applies(makeGroup(isBusinessGroup: true, tier: 'pro')),
        isFalse,
      );
      expect(
        BusinessCaps.applies(makeGroup(isBusinessGroup: true, tier: 'enterprise')),
        isFalse,
      );
    });
  });

  group('BusinessCaps.additionalAdminCap', () {
    test('un gruppo non business non ha co-admin aggiuntivi', () {
      // Prima ci si aspettava `null` (illimitato). Dal modello a tre livelli i
      // co-admin sono una funzione business: un gruppo normale ne ha zero.
      expect(BusinessCaps.additionalAdminCap(makeGroup()), 0);
    });

    test('verified and trial tiers allow zero co-admins', () {
      expect(
        BusinessCaps.additionalAdminCap(
            makeGroup(isBusinessGroup: true, tier: 'verified')),
        0,
      );
      expect(
        BusinessCaps.additionalAdminCap(
            makeGroup(isBusinessGroup: true, tier: 'trial')),
        0,
      );
    });

    test('pro tier allows up to proAdminCap', () {
      expect(
        BusinessCaps.additionalAdminCap(
            makeGroup(isBusinessGroup: true, tier: 'pro')),
        BusinessCaps.proAdminCap,
      );
      expect(BusinessCaps.proAdminCap, 5);
    });

    test('enterprise tier is unlimited (null)', () {
      expect(
        BusinessCaps.additionalAdminCap(
            makeGroup(isBusinessGroup: true, tier: 'enterprise')),
        isNull,
      );
    });

    test('un tier sconosciuto non sblocca co-admin', () {
      // Qui c'era una scelta difensiva — un tier nuovo non ancora distribuito
      // al client non doveva bloccare l'utente — e vale la pena dire perche'
      // non c'e' piu': l'API in uso, additionalAdminCapAsync, il tier non lo
      // guarda affatto. Decide su isBusinessGroup e sullo stato Pro del
      // proprietario, quindi un tier sconosciuto su un gruppo business prende
      // comunque proAdminCap.
      //
      // Questo resta il comportamento della sola versione deprecata, che
      // sparira' con B.4 portandosi via anche questo test.
      expect(
        BusinessCaps.additionalAdminCap(
            makeGroup(isBusinessGroup: true, tier: 'platinum')),
        0,
      );
    });
  });

  group('BusinessCaps constants', () {
    test('verifiedTrackCap and verifiedEventCap are documented values', () {
      expect(BusinessCaps.verifiedTrackCap, 10);
      expect(BusinessCaps.verifiedEventCap, 4);
    });
  });
}
