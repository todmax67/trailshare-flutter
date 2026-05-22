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
    test('returns false for non-business groups', () {
      expect(BusinessCaps.applies(makeGroup()), isFalse);
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
    test('returns null for non-business groups (free behavior)', () {
      expect(BusinessCaps.additionalAdminCap(makeGroup()), isNull);
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

    test('unknown tier on a Business group falls back to unlimited', () {
      // Comportamento difensivo: se il dato remoto contiene un tier
      // sconosciuto (es. nuovo tier non ancora distribuito al client),
      // non blocchiamo l'utente.
      expect(
        BusinessCaps.additionalAdminCap(
            makeGroup(isBusinessGroup: true, tier: 'platinum')),
        isNull,
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
