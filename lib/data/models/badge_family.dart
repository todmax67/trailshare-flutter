import 'package:flutter/material.dart';

/// Famiglia di badge "Garmin-style": ogni famiglia ha 4 tier
/// (Bronze, Silver, Gold, Platinum). L'utente progredisce dentro la
/// famiglia accumulando il valore della metrica corrispondente
/// (km, dislivello, follower, cheers, giorni streak, ecc.).
///
/// Le soglie per tier sono definite in [GameBadgeFamilyExt.thresholds].
enum GameBadgeFamily {
  totalDistance,       // km totali percorsi (qualsiasi attività)
  totalElevation,      // metri D+ totali
  totalTracks,         // numero di tracce salvate (escluse pianificate)
  streak,              // giorni consecutivi con almeno una traccia
  followers,           // numero follower
  cheersReceived,     // cheers ricevuti sulle tracce pubblicate

  // Activity-specific (Garmin-style)
  trailRunner,         // km running + trailRunning
  cyclist,             // km cycling + gravelBiking + eBike
  mountainBiker,       // km mountainBiking + eMountainBike
  skiTourer,           // # sessioni scialpinismo / ciaspole
  peakConquered;       // # cime salvate (Mountain Finder)

  static GameBadgeFamily? fromWire(String? s) {
    for (final f in GameBadgeFamily.values) {
      if (f.name == s) return f;
    }
    return null;
  }
}

enum GameBadgeTier {
  bronze,
  silver,
  gold,
  platinum;

  /// Tier successivo, null se [platinum].
  GameBadgeTier? get next {
    switch (this) {
      case GameBadgeTier.bronze:
        return GameBadgeTier.silver;
      case GameBadgeTier.silver:
        return GameBadgeTier.gold;
      case GameBadgeTier.gold:
        return GameBadgeTier.platinum;
      case GameBadgeTier.platinum:
        return null;
    }
  }

  /// Tier precedente, null se [bronze].
  GameBadgeTier? get previous {
    switch (this) {
      case GameBadgeTier.bronze:
        return null;
      case GameBadgeTier.silver:
        return GameBadgeTier.bronze;
      case GameBadgeTier.gold:
        return GameBadgeTier.silver;
      case GameBadgeTier.platinum:
        return GameBadgeTier.gold;
    }
  }

  String get label {
    switch (this) {
      case GameBadgeTier.bronze:
        return 'Bronzo';
      case GameBadgeTier.silver:
        return 'Argento';
      case GameBadgeTier.gold:
        return 'Oro';
      case GameBadgeTier.platinum:
        return 'Platino';
    }
  }

  /// Colore principale del tier per ring/border/text.
  Color get color {
    switch (this) {
      case GameBadgeTier.bronze:
        return const Color(0xFFCD7F32);
      case GameBadgeTier.silver:
        return const Color(0xFFBDC3C7);
      case GameBadgeTier.gold:
        return const Color(0xFFFFD700);
      case GameBadgeTier.platinum:
        return const Color(0xFF7AB6E5); // azzurro platino moderno
    }
  }

  /// Gradient per le card più "premium" (platino).
  List<Color> get gradient {
    switch (this) {
      case GameBadgeTier.platinum:
        return const [Color(0xFF7AB6E5), Color(0xFFE5E4E2)];
      default:
        return [color, color.withValues(alpha: 0.7)];
    }
  }

  /// ID stabile per persistenza Firestore.
  String get wireName => name;

  static GameBadgeTier? fromWire(String? s) {
    for (final t in GameBadgeTier.values) {
      if (t.wireName == s) return t;
    }
    return null;
  }
}

extension GameBadgeFamilyExt on GameBadgeFamily {
  /// Soglie per i 4 tier in ordine [bronze, silver, gold, platinum].
  /// Per metriche in metri (totalElevation) o conteggi (tracks/followers)
  /// le soglie sono in unità nativa; per le distanze totali (km) le
  /// soglie sono in km.
  List<double> get thresholds {
    switch (this) {
      case GameBadgeFamily.totalDistance:
        return const [10, 50, 500, 2000];
      case GameBadgeFamily.totalElevation:
        return const [1000, 5000, 10000, 50000];
      case GameBadgeFamily.totalTracks:
        return const [1, 10, 50, 200];
      case GameBadgeFamily.streak:
        return const [3, 7, 30, 100];
      case GameBadgeFamily.followers:
        return const [5, 25, 100, 500];
      case GameBadgeFamily.cheersReceived:
        return const [10, 50, 250, 1000];
      case GameBadgeFamily.trailRunner:
        return const [5, 25, 100, 500];
      case GameBadgeFamily.cyclist:
        return const [50, 250, 1000, 5000];
      case GameBadgeFamily.mountainBiker:
        return const [10, 50, 250, 1000];
      case GameBadgeFamily.skiTourer:
        return const [1, 5, 25, 100];
      case GameBadgeFamily.peakConquered:
        return const [1, 5, 25, 100];
    }
  }

  /// Soglia per uno specifico tier.
  double thresholdFor(GameBadgeTier tier) {
    return thresholds[tier.index];
  }

  /// Titolo localizzato per la card.
  String get title {
    switch (this) {
      case GameBadgeFamily.totalDistance:
        return 'Camminatore';
      case GameBadgeFamily.totalElevation:
        return 'Scalatore';
      case GameBadgeFamily.totalTracks:
        return 'Esploratore';
      case GameBadgeFamily.streak:
        return 'Costante';
      case GameBadgeFamily.followers:
        return 'Influencer';
      case GameBadgeFamily.cheersReceived:
        return 'Popolare';
      case GameBadgeFamily.trailRunner:
        return 'Trail Runner';
      case GameBadgeFamily.cyclist:
        return 'Ciclista';
      case GameBadgeFamily.mountainBiker:
        return 'Mountain Biker';
      case GameBadgeFamily.skiTourer:
        return 'Scialpinista';
      case GameBadgeFamily.peakConquered:
        return 'Cacciatore di cime';
    }
  }

  String get icon {
    switch (this) {
      case GameBadgeFamily.totalDistance:
        return '🚶';
      case GameBadgeFamily.totalElevation:
        return '⛰️';
      case GameBadgeFamily.totalTracks:
        return '🗺️';
      case GameBadgeFamily.streak:
        return '🔥';
      case GameBadgeFamily.followers:
        return '👥';
      case GameBadgeFamily.cheersReceived:
        return '🎉';
      case GameBadgeFamily.trailRunner:
        return '🏃';
      case GameBadgeFamily.cyclist:
        return '🚴';
      case GameBadgeFamily.mountainBiker:
        return '🚵';
      case GameBadgeFamily.skiTourer:
        return '🎿';
      case GameBadgeFamily.peakConquered:
        return '🏔️';
    }
  }

  /// Unità di misura per il display ("km", "m", "tracce", "giorni", ...).
  String get unit {
    switch (this) {
      case GameBadgeFamily.totalDistance:
      case GameBadgeFamily.trailRunner:
      case GameBadgeFamily.cyclist:
      case GameBadgeFamily.mountainBiker:
        return 'km';
      case GameBadgeFamily.totalElevation:
        return 'm';
      case GameBadgeFamily.totalTracks:
        return 'tracce';
      case GameBadgeFamily.streak:
        return 'giorni';
      case GameBadgeFamily.followers:
        return 'follower';
      case GameBadgeFamily.cheersReceived:
        return 'cheers';
      case GameBadgeFamily.skiTourer:
        return 'sessioni';
      case GameBadgeFamily.peakConquered:
        return 'cime';
    }
  }

  String get wireName => name;

  /// ID badge persistito su Firestore = `${family}_${tier}`.
  /// Es: `totalDistance_bronze`, `streak_platinum`.
  String badgeId(GameBadgeTier tier) => '${wireName}_${tier.wireName}';

  /// Categoria UI raggruppamento (per la tab "tutti").
  String get categoryGroup {
    switch (this) {
      case GameBadgeFamily.totalDistance:
      case GameBadgeFamily.totalElevation:
      case GameBadgeFamily.totalTracks:
        return 'Volume';
      case GameBadgeFamily.streak:
        return 'Costanza';
      case GameBadgeFamily.followers:
      case GameBadgeFamily.cheersReceived:
        return 'Social';
      case GameBadgeFamily.trailRunner:
      case GameBadgeFamily.cyclist:
      case GameBadgeFamily.mountainBiker:
      case GameBadgeFamily.skiTourer:
        return 'Sport';
      case GameBadgeFamily.peakConquered:
        return 'Esplorazione';
    }
  }
}

/// Stato corrente dell'utente in una famiglia di badge.
///
/// - [currentValue]: metrica raw corrente (es. 87.3 km totali).
/// - [currentTier]: tier più alto già raggiunto. null = sotto Bronze.
/// - [nextTier]: prossimo tier da raggiungere. null = Platinum già preso.
/// - [progressToNext]: 0..1 tra la soglia del tier corrente e quella
///   del prossimo. Usato dalla progress bar UI.
class BadgeProgress {
  final GameBadgeFamily family;
  final double currentValue;
  final GameBadgeTier? currentTier;
  final GameBadgeTier? nextTier;
  final DateTime? bronzeUnlockedAt;
  final DateTime? silverUnlockedAt;
  final DateTime? goldUnlockedAt;
  final DateTime? platinumUnlockedAt;

  const BadgeProgress({
    required this.family,
    required this.currentValue,
    this.currentTier,
    this.nextTier,
    this.bronzeUnlockedAt,
    this.silverUnlockedAt,
    this.goldUnlockedAt,
    this.platinumUnlockedAt,
  });

  /// Calcola lo stato `BadgeProgress` data la metrica corrente.
  /// L'unlock si attiva quando currentValue >= soglia. La data di
  /// sblocco viene passata dal caller se nota (lookup Firestore badges).
  factory BadgeProgress.compute({
    required GameBadgeFamily family,
    required double currentValue,
    Map<GameBadgeTier, DateTime>? unlockedAt,
  }) {
    final thresholds = family.thresholds;
    GameBadgeTier? current;
    GameBadgeTier? next;
    for (final tier in GameBadgeTier.values) {
      if (currentValue >= thresholds[tier.index]) {
        current = tier;
      } else {
        next = tier;
        break;
      }
    }
    return BadgeProgress(
      family: family,
      currentValue: currentValue,
      currentTier: current,
      nextTier: next,
      bronzeUnlockedAt: unlockedAt?[GameBadgeTier.bronze],
      silverUnlockedAt: unlockedAt?[GameBadgeTier.silver],
      goldUnlockedAt: unlockedAt?[GameBadgeTier.gold],
      platinumUnlockedAt: unlockedAt?[GameBadgeTier.platinum],
    );
  }

  bool tierUnlocked(GameBadgeTier tier) {
    if (currentTier == null) return false;
    return tier.index <= currentTier!.index;
  }

  DateTime? unlockedAtFor(GameBadgeTier tier) {
    switch (tier) {
      case GameBadgeTier.bronze:
        return bronzeUnlockedAt;
      case GameBadgeTier.silver:
        return silverUnlockedAt;
      case GameBadgeTier.gold:
        return goldUnlockedAt;
      case GameBadgeTier.platinum:
        return platinumUnlockedAt;
    }
  }

  /// Soglia del tier corrente (0 se sotto bronze).
  double get currentTierThreshold {
    if (currentTier == null) return 0;
    return family.thresholdFor(currentTier!);
  }

  /// Soglia del prossimo tier (== currentValue se platinum raggiunto,
  /// così progressToNext rimane 1.0).
  double get nextTierThreshold {
    if (nextTier == null) return currentValue;
    return family.thresholdFor(nextTier!);
  }

  /// 0..1, frazione di avanzamento tra il tier corrente e il prossimo.
  double get progressToNext {
    if (nextTier == null) return 1.0;
    final lo = currentTierThreshold;
    final hi = nextTierThreshold;
    if (hi <= lo) return 1.0;
    final p = (currentValue - lo) / (hi - lo);
    return p.clamp(0.0, 1.0);
  }

  /// Quanto manca al prossimo tier (in unità della metrica).
  double get remainingToNext {
    if (nextTier == null) return 0;
    return (nextTierThreshold - currentValue).clamp(0, double.infinity);
  }

  /// Etichetta "8.2 / 50 km" per la UI.
  String get progressLabel {
    final unit = family.unit;
    if (nextTier == null) {
      // Platinum raggiunto.
      return '${_formatVal(currentValue)} $unit · max';
    }
    return '${_formatVal(currentValue)} / ${_formatVal(nextTierThreshold)} $unit';
  }

  static String _formatVal(double v) => formatValue(v);

  /// Helper pubblico per formattazione numerica delle soglie/valori
  /// (riusato da UI tier detail). 1234 → "1234", 8.0 → "8", 8.5 → "8.5".
  static String formatValue(double v) {
    if (v >= 1000) {
      return v.toStringAsFixed(0);
    }
    if (v >= 100) return v.toStringAsFixed(0);
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

/// Mappa legacy badge ID → famiglia + tier corrispondente.
/// Usata per preservare gli sblocchi pre-refactor (commit Epic 5 badges
/// rivisitati): se l'utente ha già `hiker_50km` su Firestore, lo
/// mostriamo come `totalDistance_silver` unlocked nella nuova UI.
class LegacyBadgeMapping {
  LegacyBadgeMapping._();

  static final Map<String, ({GameBadgeFamily family, GameBadgeTier tier})>
      _map = {
    'first_steps': (
      family: GameBadgeFamily.totalTracks,
      tier: GameBadgeTier.bronze
    ),
    'hiker_10km': (
      family: GameBadgeFamily.totalDistance,
      tier: GameBadgeTier.bronze
    ),
    'hiker_50km': (
      family: GameBadgeFamily.totalDistance,
      tier: GameBadgeTier.silver
    ),
    'hiker_100km': (
      family: GameBadgeFamily.totalDistance,
      tier: GameBadgeTier.silver
    ),
    'hiker_500km': (
      family: GameBadgeFamily.totalDistance,
      tier: GameBadgeTier.gold
    ),
    'climber_1000m': (
      family: GameBadgeFamily.totalElevation,
      tier: GameBadgeTier.bronze
    ),
    'climber_5000m': (
      family: GameBadgeFamily.totalElevation,
      tier: GameBadgeTier.silver
    ),
    'climber_10000m': (
      family: GameBadgeFamily.totalElevation,
      tier: GameBadgeTier.gold
    ),
    'social_5_followers': (
      family: GameBadgeFamily.followers,
      tier: GameBadgeTier.bronze
    ),
    'social_50_cheers': (
      family: GameBadgeFamily.cheersReceived,
      tier: GameBadgeTier.silver
    ),
    'streak_3': (
      family: GameBadgeFamily.streak,
      tier: GameBadgeTier.bronze
    ),
    'streak_7': (
      family: GameBadgeFamily.streak,
      tier: GameBadgeTier.silver
    ),
    'streak_30': (
      family: GameBadgeFamily.streak,
      tier: GameBadgeTier.gold
    ),
  };

  static ({GameBadgeFamily family, GameBadgeTier tier})? lookup(String id) =>
      _map[id];
}
