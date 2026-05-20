import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/utils/geohash_util.dart';

/// Tipo di POI (Point of Interest) supportato da TrailShare.
///
/// Ogni tipo ha una etichetta italiana, un'icona emoji e un'icona Material
/// per rendering in contesti che non supportano emoji.
enum PoiType {
  water('water', '💧', 'Fontana', Icons.water_drop,
      'Fonte d\'acqua potabile o rifornimento idrico'),
  shelter('shelter', '🏠', 'Rifugio', Icons.cabin,
      'Rifugio, bivacco o ricovero di emergenza'),
  viewpoint('viewpoint', '👁️', 'Panorama', Icons.landscape,
      'Punto panoramico'),
  danger('danger', '⚠️', 'Pericolo', Icons.warning_amber,
      'Tratto pericoloso, esposto o sconsigliato'),
  parking('parking', '🅿️', 'Parcheggio', Icons.local_parking,
      'Punto di partenza/arrivo raggiungibile in auto'),
  food('food', '🍽️', 'Ristoro', Icons.restaurant,
      'Bar, ristorante, malga aperta'),
  toilet('toilet', '🚻', 'Bagno', Icons.wc,
      'Servizi igienici disponibili'),
  camping('camping', '⛺', 'Campeggio', Icons.holiday_village,
      'Area attrezzata per tende autorizzata'),
  historical('historical', '🗿', 'Storico', Icons.account_balance,
      'Chiesa, rudere, monumento'),
  nature('nature', '🌲', 'Natura', Icons.park,
      'Cascata, albero monumentale, elemento naturalistico');

  /// Valore persistito su Firestore (stringa stabile, NON cambiare).
  final String firestoreKey;

  /// Icona emoji compatta (UI compatta, cluster su mappa).
  final String emoji;

  /// Nome leggibile italiano.
  final String displayName;

  /// Icona Material fallback per contesti senza emoji.
  final IconData materialIcon;

  /// Descrizione breve mostrata nel picker al momento della creazione.
  final String description;

  const PoiType(
    this.firestoreKey,
    this.emoji,
    this.displayName,
    this.materialIcon,
    this.description,
  );

  /// Colore distintivo per il pin sulla mappa.
  Color get pinColor {
    switch (this) {
      case PoiType.water:
        return const Color(0xFF1E88E5); // blu
      case PoiType.shelter:
        return const Color(0xFF6D4C41); // marrone
      case PoiType.viewpoint:
        return const Color(0xFF8E24AA); // viola
      case PoiType.danger:
        return const Color(0xFFE53935); // rosso
      case PoiType.parking:
        return const Color(0xFF546E7A); // grigio
      case PoiType.food:
        return const Color(0xFFE67E22); // arancio
      case PoiType.toilet:
        return const Color(0xFF00ACC1); // ciano
      case PoiType.camping:
        return const Color(0xFF2E7D32); // verde
      case PoiType.historical:
        return const Color(0xFFFFB300); // ocra
      case PoiType.nature:
        return const Color(0xFF558B2F); // verde muschio
    }
  }

  static PoiType fromKey(String? key) {
    if (key == null) return PoiType.nature;
    for (final t in values) {
      if (t.firestoreKey == key) return t;
    }
    return PoiType.nature;
  }

  /// Tipi di POI "critici" annunciati vocalmente durante la registrazione
  /// guidata (soglie 500/200/50 m). Gli altri tipi restano visibili sulla
  /// mappa ma non interrompono la navigazione con annunci.
  ///
  /// Criterio: è utile sapere in anticipo? Fontana (rifornimento acqua),
  /// rifugio (riparo), pericolo (sicurezza), ristoro (pausa), panorama
  /// (non perdere la vista). Parcheggio/bagno/camping/storico/natura sono
  /// "nice to know" ma non richiedono annuncio sonoro.
  bool get isDefaultAnnounceable {
    switch (this) {
      case PoiType.water:
      case PoiType.shelter:
      case PoiType.danger:
      case PoiType.food:
      case PoiType.viewpoint:
        return true;
      default:
        return false;
    }
  }
}

/// Punto di interesse (POI) sulla mappa o lungo un percorso.
///
/// Modello:
/// - POI "globali": visibili a chiunque abbia il raggio di query geografica
///   (senza `relatedTrailId` né `relatedTrackId`)
/// - POI "legati a trail OSM": `relatedTrailId` != null, evidenziati sulla
///   pagina del trail (trail pubblico)
/// - POI "legati a track community": `relatedTrackId` != null, visibili sul
///   dettaglio della track community. Se la track diventa pubblica, tutti i
///   suoi POI privati diventano automaticamente pubblici (cascata gestita
///   lato repository).
///
/// Default visibilità: `isPublic = false` per utenti normali (il creatore
/// può poi renderlo pubblico). Admin crea direttamente pubblici.
class TrailPoi {
  final String id;
  final PoiType type;
  final String title;
  final String? description;

  /// Coordinate del POI. Il `geohash` precisione 7 viene derivato e
  /// salvato per query proximity rapide via Firestore range queries.
  final double latitude;
  final double longitude;
  final String geohash;

  final String? photoUrl;

  final String createdBy;
  final String? createdByUsername;
  final DateTime? createdAt;

  final int upvotes;
  final int downvotes;
  final bool verifiedByAdmin;

  /// Legato a un trail OSM (collection public_trails).
  final String? relatedTrailId;

  /// Legato a una track community (collection published_tracks).
  final String? relatedTrackId;

  /// Visibilità: se false, solo l'autore lo vede.
  final bool isPublic;

  /// Komoot K1a — Highlight con link a Spazio Pro.
  ///
  /// Quando un autore di track collega un POI a uno Spazio Pro (rifugio,
  /// noleggio, guida, ecc.), il POI diventa un "highlight" della traccia:
  /// pill cliccabile che apre la scheda business. Resta un POI a tutti
  /// gli effetti (tipo, mappa, voting), ma con il valore aggiunto del
  /// link B2B.
  ///
  /// Denormalizziamo `linkedBusinessName` e `linkedBusinessSlug` per
  /// permettere il rendering delle pill senza una read extra per POI.
  /// Sync via Cloud Function quando il business cambia nome/slug.
  final String? linkedBusinessId;
  final String? linkedBusinessName;
  final String? linkedBusinessSlug;

  TrailPoi({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    required this.latitude,
    required this.longitude,
    String? geohash,
    this.photoUrl,
    required this.createdBy,
    this.createdByUsername,
    this.createdAt,
    this.upvotes = 0,
    this.downvotes = 0,
    this.verifiedByAdmin = false,
    this.relatedTrailId,
    this.relatedTrackId,
    this.isPublic = false,
    this.linkedBusinessId,
    this.linkedBusinessName,
    this.linkedBusinessSlug,
  }) : geohash = geohash ?? GeoHashUtil.encode(latitude, longitude);

  int get score => upvotes - downvotes;

  /// Komoot K1a — true se il POI è anche un highlight (linkato a Spazio Pro).
  bool get isHighlight => linkedBusinessId != null && linkedBusinessId!.isNotEmpty;

  TrailPoi copyWith({
    String? id,
    PoiType? type,
    String? title,
    String? description,
    double? latitude,
    double? longitude,
    String? photoUrl,
    String? createdBy,
    String? createdByUsername,
    DateTime? createdAt,
    int? upvotes,
    int? downvotes,
    bool? verifiedByAdmin,
    String? relatedTrailId,
    String? relatedTrackId,
    bool? isPublic,
    String? linkedBusinessId,
    String? linkedBusinessName,
    String? linkedBusinessSlug,
  }) {
    return TrailPoi(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      photoUrl: photoUrl ?? this.photoUrl,
      createdBy: createdBy ?? this.createdBy,
      createdByUsername: createdByUsername ?? this.createdByUsername,
      createdAt: createdAt ?? this.createdAt,
      upvotes: upvotes ?? this.upvotes,
      downvotes: downvotes ?? this.downvotes,
      verifiedByAdmin: verifiedByAdmin ?? this.verifiedByAdmin,
      relatedTrailId: relatedTrailId ?? this.relatedTrailId,
      relatedTrackId: relatedTrackId ?? this.relatedTrackId,
      isPublic: isPublic ?? this.isPublic,
      linkedBusinessId: linkedBusinessId ?? this.linkedBusinessId,
      linkedBusinessName: linkedBusinessName ?? this.linkedBusinessName,
      linkedBusinessSlug: linkedBusinessSlug ?? this.linkedBusinessSlug,
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'type': type.firestoreKey,
        'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'geohash': geohash,
        if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
        'createdBy': createdBy,
        if (createdByUsername != null) 'createdByUsername': createdByUsername,
        'createdAt': FieldValue.serverTimestamp(),
        'upvotes': upvotes,
        'downvotes': downvotes,
        'verifiedByAdmin': verifiedByAdmin,
        if (relatedTrailId != null) 'relatedTrailId': relatedTrailId,
        if (relatedTrackId != null) 'relatedTrackId': relatedTrackId,
        'isPublic': isPublic,
        if (linkedBusinessId != null) 'linkedBusinessId': linkedBusinessId,
        if (linkedBusinessName != null) 'linkedBusinessName': linkedBusinessName,
        if (linkedBusinessSlug != null) 'linkedBusinessSlug': linkedBusinessSlug,
      };

  /// Solo i campi modificabili dopo la creazione (no createdBy, no createdAt,
  /// no voti che passano per transazione separata).
  Map<String, dynamic> toFirestoreUpdate() => {
        'type': type.firestoreKey,
        'title': title,
        'description': description ?? FieldValue.delete(),
        'latitude': latitude,
        'longitude': longitude,
        'geohash': geohash,
        'photoUrl': photoUrl ?? FieldValue.delete(),
        'relatedTrailId': relatedTrailId ?? FieldValue.delete(),
        'relatedTrackId': relatedTrackId ?? FieldValue.delete(),
        'isPublic': isPublic,
        'linkedBusinessId': linkedBusinessId ?? FieldValue.delete(),
        'linkedBusinessName': linkedBusinessName ?? FieldValue.delete(),
        'linkedBusinessSlug': linkedBusinessSlug ?? FieldValue.delete(),
      };

  factory TrailPoi.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return TrailPoi(
      id: doc.id,
      type: PoiType.fromKey(data['type'] as String?),
      title: (data['title'] as String?) ?? '',
      description: data['description'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      geohash: data['geohash'] as String?,
      photoUrl: data['photoUrl'] as String?,
      createdBy: (data['createdBy'] as String?) ?? '',
      createdByUsername: data['createdByUsername'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      upvotes: (data['upvotes'] as num?)?.toInt() ?? 0,
      downvotes: (data['downvotes'] as num?)?.toInt() ?? 0,
      verifiedByAdmin: data['verifiedByAdmin'] == true,
      relatedTrailId: data['relatedTrailId'] as String?,
      relatedTrackId: data['relatedTrackId'] as String?,
      isPublic: data['isPublic'] != false, // default true per retrocompatibilità
      linkedBusinessId: data['linkedBusinessId'] as String?,
      linkedBusinessName: data['linkedBusinessName'] as String?,
      linkedBusinessSlug: data['linkedBusinessSlug'] as String?,
    );
  }
}
