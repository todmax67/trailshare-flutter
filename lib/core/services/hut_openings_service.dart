import 'dart:convert';

import 'package:flutter/services.dart';

import '../../data/models/hut_opening.dart';

/// Legge il seed delle aperture di rifugi e bivacchi da
/// `assets/data/hut_openings.json`, generato da `scripts/build_hut_openings.py`.
///
/// E' volutamente un asset e non Firestore: sono dati derivati da OSM,
/// rigenerabili in qualunque momento, uguali per tutti e consultati mentre si
/// e' in montagna senza rete. Farli pagare come letture Firestore sarebbe
/// spendere per un dato che non cambia.
///
/// L'architettura prevista e' a due livelli: **questo asset e' la base**, e le
/// aperture dichiarate dai gestori — l'unica fonte che sappia davvero quando un
/// rifugio apre — arriveranno da Firestore e vinceranno su questa. Vedi
/// docs/rifugi_aperture.md.
///
/// L'assenza di una voce non e' un errore: significa che non sappiamo, che e'
/// [OpeningVerdict.ignoto], ed e' un'informazione onesta come le altre.
class HutOpeningsService {
  HutOpeningsService._();
  static final HutOpeningsService _instance = HutOpeningsService._();
  factory HutOpeningsService() => _instance;

  static const String _assetPath = 'assets/data/hut_openings.json';

  Map<String, HutOpening>? _cache;
  Future<void>? _loading;

  /// Data di generazione del seed, per poterla mostrare.
  String? generatedAt;

  /// Carica l'asset una volta sola. Chiamate concorrenti condividono la stessa
  /// Future invece di rileggere il file in parallelo.
  Future<void> ensureLoaded() {
    if (_cache != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final doc = json.decode(raw) as Map<String, dynamic>;
      generatedAt = doc['generatedAt'] as String?;
      final openings = (doc['openings'] as Map<String, dynamic>?) ?? const {};
      _cache = openings.map(
        (id, v) => MapEntry(
          id,
          HutOpening.fromMap(Map<String, dynamic>.from(v as Map)),
        ),
      );
    } catch (_) {
      // Un seed illeggibile non deve impedire di aprire una scheda: si resta
      // senza informazioni sulle aperture, che e' uno stato previsto.
      _cache = const {};
    } finally {
      _loading = null;
    }
  }

  /// L'apertura nota per un POI, o `null` se non ne sappiamo niente.
  ///
  /// [poiId] e' l'id del dataset POI (`w541501364`, `n8659360017`).
  /// Richiede che [ensureLoaded] sia gia' stata attesa.
  HutOpening? forPoi(String poiId) => _cache?[poiId];

  /// Comodita': carica se serve e risolve in un colpo solo.
  Future<OpeningStatus?> statusFor(String poiId, {DateTime? now}) async {
    await ensureLoaded();
    return _cache?[poiId]?.resolve(now: now);
  }

  /// Quante voci contiene il seed. Utile in diagnostica.
  int get count => _cache?.length ?? 0;

  /// Solo per i test.
  void resetForTest() {
    _cache = null;
    _loading = null;
    generatedAt = null;
  }
}
