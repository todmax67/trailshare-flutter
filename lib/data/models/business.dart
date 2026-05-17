import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo di business (Spazio Pro). Granularità voluta minimale per MVP;
/// nuovi tipi si aggiungono qui senza migrazioni dati.
enum BusinessType {
  rifugio,
  noleggio,
  guidaAlpina,
  scuolaAlpinismo,
  shop,
  tourOperator,
  consorzioTurismo,
  altro;

  String get displayName {
    switch (this) {
      case BusinessType.rifugio:
        return 'Rifugio';
      case BusinessType.noleggio:
        return 'Noleggio';
      case BusinessType.guidaAlpina:
        return 'Guida alpina';
      case BusinessType.scuolaAlpinismo:
        return 'Scuola alpinismo';
      case BusinessType.shop:
        return 'Negozio outdoor';
      case BusinessType.tourOperator:
        return 'Tour operator';
      case BusinessType.consorzioTurismo:
        return 'Consorzio turismo';
      case BusinessType.altro:
        return 'Altro';
    }
  }

  String get icon {
    switch (this) {
      case BusinessType.rifugio:
        return '🏔️';
      case BusinessType.noleggio:
        return '🚲';
      case BusinessType.guidaAlpina:
        return '🧗';
      case BusinessType.scuolaAlpinismo:
        return '🎓';
      case BusinessType.shop:
        return '🛒';
      case BusinessType.tourOperator:
        return '🧭';
      case BusinessType.consorzioTurismo:
        return '🗺️';
      case BusinessType.altro:
        return '📍';
    }
  }
}

/// Tier di abbonamento + stato di "ownership" della scheda.
///
/// I tre tier pagati sono: verified, pro, enterprise (vedi pricing).
///
/// 7.H1 — `unclaimed` non è un piano pagato: indica una scheda
/// pre-popolata da TrailShare (da OSM, registro pubblico, scoperta
/// manuale) che non è ancora stata rivendicata dal vero gestore.
/// Visivamente porta banner "Sei il gestore? Rivendica" e ha alcune
/// sezioni in read-only (no aggiornamenti, no listino) finché non
/// viene reclamata, momento in cui passa a `verified`.
enum BusinessTier {
  unclaimed,
  verified,
  pro,
  enterprise;

  String get displayName {
    switch (this) {
      case BusinessTier.unclaimed:
        return 'Non rivendicata';
      case BusinessTier.verified:
        return 'Verificato';
      case BusinessTier.pro:
        return 'Pro';
      case BusinessTier.enterprise:
        return 'Enterprise';
    }
  }

  /// True se la scheda è stata pre-popolata ma non ancora rivendicata
  /// dal gestore reale. Driver del banner pubblico claim.
  bool get isUnclaimed => this == BusinessTier.unclaimed;
}

enum BusinessStatus {
  pending, // creato ma non ancora attivato (es. attesa pagamento)
  active,
  suspended,
}

class BusinessLocation {
  final double lat;
  final double lng;
  final String geohash;
  final String? address;
  final String? city;
  final String? region;
  final double? elevation;

  const BusinessLocation({
    required this.lat,
    required this.lng,
    required this.geohash,
    this.address,
    this.city,
    this.region,
    this.elevation,
  });

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'geohash': geohash,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
        if (region != null) 'region': region,
        if (elevation != null) 'elevation': elevation,
      };

  factory BusinessLocation.fromMap(Map<String, dynamic> m) => BusinessLocation(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        geohash: m['geohash']?.toString() ?? '',
        address: m['address']?.toString(),
        city: m['city']?.toString(),
        region: m['region']?.toString(),
        elevation: (m['elevation'] as num?)?.toDouble(),
      );
}

class BusinessBranding {
  final String? logoUrl;
  final String? heroPhotoUrl;
  final List<String> galleryUrls;
  final String? primaryColor; // hex es. "#FC4C02"

  const BusinessBranding({
    this.logoUrl,
    this.heroPhotoUrl,
    this.galleryUrls = const [],
    this.primaryColor,
  });

  Map<String, dynamic> toMap() => {
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (heroPhotoUrl != null) 'heroPhotoUrl': heroPhotoUrl,
        if (galleryUrls.isNotEmpty) 'galleryUrls': galleryUrls,
        if (primaryColor != null) 'primaryColor': primaryColor,
      };

  factory BusinessBranding.fromMap(Map<String, dynamic> m) => BusinessBranding(
        logoUrl: m['logoUrl']?.toString(),
        heroPhotoUrl: m['heroPhotoUrl']?.toString(),
        galleryUrls: (m['galleryUrls'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        primaryColor: m['primaryColor']?.toString(),
      );
}

class BusinessContacts {
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? website;
  final String? instagram;
  final String? facebook;

  const BusinessContacts({
    this.phone,
    this.whatsapp,
    this.email,
    this.website,
    this.instagram,
    this.facebook,
  });

  bool get isEmpty =>
      phone == null &&
      whatsapp == null &&
      email == null &&
      website == null &&
      instagram == null &&
      facebook == null;

  Map<String, dynamic> toMap() => {
        if (phone != null) 'phone': phone,
        if (whatsapp != null) 'whatsapp': whatsapp,
        if (email != null) 'email': email,
        if (website != null) 'website': website,
        if (instagram != null) 'instagram': instagram,
        if (facebook != null) 'facebook': facebook,
      };

  factory BusinessContacts.fromMap(Map<String, dynamic> m) => BusinessContacts(
        phone: m['phone']?.toString(),
        whatsapp: m['whatsapp']?.toString(),
        email: m['email']?.toString(),
        website: m['website']?.toString(),
        instagram: m['instagram']?.toString(),
        facebook: m['facebook']?.toString(),
      );
}

/// Orari di apertura per giorno.
/// Map: 'monday' → DayHours | null (chiuso) | DayHours.open24h
class DayHours {
  final String open; // 'HH:mm'
  final String close;
  final bool open24h;
  final bool closed;

  const DayHours({
    this.open = '',
    this.close = '',
    this.open24h = false,
    this.closed = false,
  });

  Map<String, dynamic> toMap() {
    if (closed) return {'closed': true};
    if (open24h) return {'open24h': true};
    return {'open': open, 'close': close};
  }

  factory DayHours.fromMap(Map<String, dynamic> m) => DayHours(
        open: m['open']?.toString() ?? '',
        close: m['close']?.toString() ?? '',
        open24h: m['open24h'] == true,
        closed: m['closed'] == true,
      );
}

class Business {
  final String? id;
  final String name;
  final String slug;
  final BusinessType type;
  final BusinessTier tier;
  final BusinessStatus status;

  final String? description;
  final String? shortDescription;

  final BusinessLocation location;
  final BusinessBranding branding;
  final BusinessContacts contacts;
  final Map<String, DayHours> openingHours;

  final String ownerId;
  final List<String> adminUserIds;
  final String? linkedGroupId;

  // Denormalized counters
  final int followerCount;
  final int postsCount;
  final double? rating;
  final int reviewCount;

  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? claimedAt;

  /// Epic 7.H1 — self-claim flow.
  ///
  /// `pendingSelfManagement` = true quando il team TrailShare ha
  /// inserito la scheda **per conto** del gestore reale (rifugista,
  /// noleggiatore...) che non è ancora autonomo. La scheda è già
  /// `verified` e gestita dal team, ma il vero gestore può subentrare
  /// in qualunque momento cliccando il link self-claim ricevuto via
  /// WhatsApp/email.
  ///
  /// Il token NON è salvato qui (sarebbe esposto dalla read pubblica
  /// del doc): vive in `business_self_claims/{token}`, collection con
  /// rule `allow read: false` accessibile solo dalle Cloud Function
  /// `generateSelfClaimToken` / `acceptSelfClaim`.
  ///
  /// Diverso da Epic 7.H4-7.H5 (claim *pubblico* via OSM pre-seed):
  /// qui non c'è verifica P.IVA, perché hai già verificato la persona
  /// di persona prima di inviare il link. Il token è il secret
  /// condiviso uno-a-uno.
  final bool pendingSelfManagement;

  /// 7.H1 — Sorgente dei dati di una scheda `unclaimed` pre-popolata
  /// da TrailShare. Esempi: `https://www.openstreetmap.org/node/123`,
  /// `https://www.cai.it/rifugio/123`. Per le schede inserite a mano
  /// dal team o dal vero gestore può restare null.
  final String? sourceUrl;

  /// 7.H4 — Se true, mostriamo banner big "Scheda generata da fonti
  /// pubbliche, sei il gestore?" + CTA Rivendica/Segnala. Default true
  /// per i doc creati con tier=unclaimed; va su false al claim
  /// approvato. Tenuto separato da `tier` per casi edge (es. scheda
  /// claimed che vuole comunque mostrare il disclaimer perché in
  /// transizione, o test A/B sul copy del banner).
  final bool disclaimerVisible;

  /// 7.H12 — Contatori funnel mantenuti server-side dalla Cloud
  /// Function `trackFunnelEvent`. Chiavi note:
  /// `unclaimed_view`, `claim_started`, `claim_completed`,
  /// `claim_approved`, `claim_rejected`. Aggiornati con
  /// FieldValue.increment(1). Lettura pubblica (read businesses è
  /// pubblica) → ok mostrare anche all'owner.
  final Map<String, int> funnelCounters;

  const Business({
    this.id,
    required this.name,
    required this.slug,
    required this.type,
    this.tier = BusinessTier.verified,
    this.status = BusinessStatus.active,
    this.description,
    this.shortDescription,
    required this.location,
    this.branding = const BusinessBranding(),
    this.contacts = const BusinessContacts(),
    this.openingHours = const {},
    required this.ownerId,
    this.adminUserIds = const [],
    this.linkedGroupId,
    this.followerCount = 0,
    this.postsCount = 0,
    this.rating,
    this.reviewCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.claimedAt,
    this.pendingSelfManagement = false,
    this.sourceUrl,
    this.disclaimerVisible = false,
    this.funnelCounters = const {},
  });

  bool get isOwnedBy => false; // placeholder, l'owner check è nel repo

  /// Vero se [uid] può gestire questo Business.
  ///
  /// Tre vie:
  /// 1. **owner** del business (`ownerId == uid`)
  /// 2. **co-admin** del business (rientra in `adminUserIds`)
  /// 3. **platform admin TrailShare** ([isPlatformAdmin] = true).
  ///    Il team interno gestisce schede di rifugi/noleggi non
  ///    tech-savvy che hanno delegato (vedi Epic 7.H pre-seeding
  ///    & support).
  bool isOwnerOrAdmin(String? uid, {bool isPlatformAdmin = false}) {
    if (uid == null) return false;
    if (uid == ownerId) return true;
    if (adminUserIds.contains(uid)) return true;
    if (isPlatformAdmin) return true;
    return false;
  }

  Map<String, dynamic> toMap() {
    final hoursMap = <String, dynamic>{};
    openingHours.forEach((day, h) {
      hoursMap[day] = h.toMap();
    });
    return {
      'name': name,
      'slug': slug,
      'type': type.name,
      'tier': tier.name,
      'status': status.name,
      if (description != null) 'description': description,
      if (shortDescription != null) 'shortDescription': shortDescription,
      'location': location.toMap(),
      if (branding.toMap().isNotEmpty) 'branding': branding.toMap(),
      if (!contacts.isEmpty) 'contacts': contacts.toMap(),
      if (hoursMap.isNotEmpty) 'openingHours': hoursMap,
      'ownerId': ownerId,
      if (adminUserIds.isNotEmpty) 'adminUserIds': adminUserIds,
      if (linkedGroupId != null) 'linkedGroupId': linkedGroupId,
      'followerCount': followerCount,
      'postsCount': postsCount,
      if (rating != null) 'rating': rating,
      'reviewCount': reviewCount,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      if (claimedAt != null) 'claimedAt': Timestamp.fromDate(claimedAt!),
      // 7.H1 — self-claim. Default false → non serializzato per i doc
      // legacy senza il campo (resta assente). Il token vive in
      // collection separata `business_self_claims/{token}`.
      if (pendingSelfManagement) 'pendingSelfManagement': true,
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
      if (disclaimerVisible) 'disclaimerVisible': true,
    };
  }

  factory Business.fromMap(String id, Map<String, dynamic> m) {
    final hoursRaw = m['openingHours'] as Map<String, dynamic>?;
    final hours = <String, DayHours>{};
    hoursRaw?.forEach((day, value) {
      if (value is Map<String, dynamic>) {
        hours[day] = DayHours.fromMap(value);
      }
    });

    DateTime ts(dynamic v, {DateTime? fallback}) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? (fallback ?? DateTime.now());
      return fallback ?? DateTime.now();
    }

    return Business(
      id: id,
      name: m['name']?.toString() ?? '',
      slug: m['slug']?.toString() ?? '',
      type: BusinessType.values.firstWhere(
        (t) => t.name == m['type'],
        orElse: () => BusinessType.altro,
      ),
      tier: BusinessTier.values.firstWhere(
        (t) => t.name == m['tier'],
        orElse: () => BusinessTier.verified,
      ),
      status: BusinessStatus.values.firstWhere(
        (s) => s.name == m['status'],
        orElse: () => BusinessStatus.active,
      ),
      description: m['description']?.toString(),
      shortDescription: m['shortDescription']?.toString(),
      location: BusinessLocation.fromMap(
        Map<String, dynamic>.from(m['location'] as Map? ?? {}),
      ),
      branding: BusinessBranding.fromMap(
        Map<String, dynamic>.from(m['branding'] as Map? ?? {}),
      ),
      contacts: BusinessContacts.fromMap(
        Map<String, dynamic>.from(m['contacts'] as Map? ?? {}),
      ),
      openingHours: hours,
      ownerId: m['ownerId']?.toString() ?? '',
      adminUserIds: (m['adminUserIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      linkedGroupId: m['linkedGroupId']?.toString(),
      followerCount: (m['followerCount'] as num?)?.toInt() ?? 0,
      postsCount: (m['postsCount'] as num?)?.toInt() ?? 0,
      rating: (m['rating'] as num?)?.toDouble(),
      reviewCount: (m['reviewCount'] as num?)?.toInt() ?? 0,
      createdAt: ts(m['createdAt']),
      updatedAt: m['updatedAt'] != null ? ts(m['updatedAt']) : null,
      claimedAt: m['claimedAt'] != null ? ts(m['claimedAt']) : null,
      pendingSelfManagement: m['pendingSelfManagement'] == true,
      sourceUrl: m['sourceUrl']?.toString(),
      disclaimerVisible: m['disclaimerVisible'] == true,
      funnelCounters: (m['funnelCounters'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          ) ??
          const {},
    );
  }

  Business copyWith({
    String? name,
    String? slug,
    BusinessType? type,
    BusinessTier? tier,
    BusinessStatus? status,
    String? description,
    String? shortDescription,
    BusinessLocation? location,
    BusinessBranding? branding,
    BusinessContacts? contacts,
    Map<String, DayHours>? openingHours,
    String? ownerId,
    List<String>? adminUserIds,
    String? linkedGroupId,
    int? followerCount,
    int? postsCount,
    double? rating,
    int? reviewCount,
    DateTime? updatedAt,
    DateTime? claimedAt,
    bool? pendingSelfManagement,
    String? sourceUrl,
    bool? disclaimerVisible,
  }) {
    return Business(
      id: id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      type: type ?? this.type,
      tier: tier ?? this.tier,
      status: status ?? this.status,
      description: description ?? this.description,
      shortDescription: shortDescription ?? this.shortDescription,
      location: location ?? this.location,
      branding: branding ?? this.branding,
      contacts: contacts ?? this.contacts,
      openingHours: openingHours ?? this.openingHours,
      ownerId: ownerId ?? this.ownerId,
      adminUserIds: adminUserIds ?? this.adminUserIds,
      linkedGroupId: linkedGroupId ?? this.linkedGroupId,
      followerCount: followerCount ?? this.followerCount,
      postsCount: postsCount ?? this.postsCount,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      claimedAt: claimedAt ?? this.claimedAt,
      pendingSelfManagement:
          pendingSelfManagement ?? this.pendingSelfManagement,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      disclaimerVisible: disclaimerVisible ?? this.disclaimerVisible,
    );
  }
}

/// Post di un business (aggiornamenti, condizioni meteo, news).
class BusinessPost {
  final String? id;
  final String businessId;
  final String authorId;
  final String text;
  final List<String> photoUrls;
  final DateTime createdAt;
  final DateTime? editedAt;

  const BusinessPost({
    this.id,
    required this.businessId,
    required this.authorId,
    required this.text,
    this.photoUrls = const [],
    required this.createdAt,
    this.editedAt,
  });

  Map<String, dynamic> toMap() => {
        'businessId': businessId,
        'authorId': authorId,
        'text': text,
        if (photoUrls.isNotEmpty) 'photoUrls': photoUrls,
        'createdAt': Timestamp.fromDate(createdAt),
        if (editedAt != null) 'editedAt': Timestamp.fromDate(editedAt!),
      };

  factory BusinessPost.fromMap(String id, Map<String, dynamic> m) =>
      BusinessPost(
        id: id,
        businessId: m['businessId']?.toString() ?? '',
        authorId: m['authorId']?.toString() ?? '',
        text: m['text']?.toString() ?? '',
        photoUrls: (m['photoUrls'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        createdAt: (m['createdAt'] is Timestamp)
            ? (m['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
        editedAt: m['editedAt'] is Timestamp
            ? (m['editedAt'] as Timestamp).toDate()
            : null,
      );
}

/// Snapshot delle metriche aggregate di uno Spazio Pro.
/// Contatori cumulativi life-time, salvati in
/// `businesses/{id}/analytics/totals` (singleton doc).
class BusinessAnalyticsTotals {
  final int profileViews;
  final int contactClicksWhatsApp;
  final int contactClicksPhone;
  final int contactClicksEmail;
  final int contactClicksWebsite;
  final int contactClicksDirections;
  final DateTime? lastUpdatedAt;

  const BusinessAnalyticsTotals({
    this.profileViews = 0,
    this.contactClicksWhatsApp = 0,
    this.contactClicksPhone = 0,
    this.contactClicksEmail = 0,
    this.contactClicksWebsite = 0,
    this.contactClicksDirections = 0,
    this.lastUpdatedAt,
  });

  int get totalContactClicks =>
      contactClicksWhatsApp +
      contactClicksPhone +
      contactClicksEmail +
      contactClicksWebsite +
      contactClicksDirections;

  factory BusinessAnalyticsTotals.fromMap(Map<String, dynamic> m) =>
      BusinessAnalyticsTotals(
        profileViews: (m['profileViews'] as num?)?.toInt() ?? 0,
        contactClicksWhatsApp:
            (m['contactClicksWhatsApp'] as num?)?.toInt() ?? 0,
        contactClicksPhone:
            (m['contactClicksPhone'] as num?)?.toInt() ?? 0,
        contactClicksEmail:
            (m['contactClicksEmail'] as num?)?.toInt() ?? 0,
        contactClicksWebsite:
            (m['contactClicksWebsite'] as num?)?.toInt() ?? 0,
        contactClicksDirections:
            (m['contactClicksDirections'] as num?)?.toInt() ?? 0,
        lastUpdatedAt: m['lastUpdatedAt'] is Timestamp
            ? (m['lastUpdatedAt'] as Timestamp).toDate()
            : null,
      );
}

/// Aggregato giornaliero: doc ID = "YYYY-MM-DD" UTC.
class BusinessAnalyticsDay {
  final String dateKey; // YYYY-MM-DD
  final int profileViews;
  final int contactClicks;

  const BusinessAnalyticsDay({
    required this.dateKey,
    this.profileViews = 0,
    this.contactClicks = 0,
  });

  factory BusinessAnalyticsDay.fromMap(
          String dateKey, Map<String, dynamic> m) =>
      BusinessAnalyticsDay(
        dateKey: dateKey,
        profileViews: (m['profileViews'] as num?)?.toInt() ?? 0,
        contactClicks: (m['contactClicks'] as num?)?.toInt() ?? 0,
      );

  DateTime get date {
    final parts = dateKey.split('-');
    if (parts.length != 3) return DateTime.now();
    return DateTime.utc(
      int.tryParse(parts[0]) ?? 1970,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
  }
}

/// Tipo di click contatto tracciato.
enum BusinessContactType {
  whatsapp('whatsapp'),
  phone('phone'),
  email('email'),
  website('website'),
  directions('directions');

  final String wireName;
  const BusinessContactType(this.wireName);

  String get totalsField => 'contactClicks${_pascal(wireName)}';
  static String _pascal(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Recensione di uno Spazio Pro lasciata da un utente.
/// Una recensione per utente per business (doc ID = userId).
class BusinessReview {
  /// ID Firestore del doc. Coincide con [userId] per garantire 1 review/utente.
  final String? id;
  final String userId;
  final int rating; // 1-5
  final String? comment;
  final DateTime createdAt;
  final DateTime? editedAt;

  // Denormalizzati al momento del create per evitare N query in lista
  final String userDisplayName;
  final String? userAvatarUrl;

  const BusinessReview({
    this.id,
    required this.userId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.editedAt,
    required this.userDisplayName,
    this.userAvatarUrl,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'rating': rating,
        if (comment != null && comment!.isNotEmpty) 'comment': comment,
        'createdAt': Timestamp.fromDate(createdAt),
        if (editedAt != null) 'editedAt': Timestamp.fromDate(editedAt!),
        'userDisplayName': userDisplayName,
        if (userAvatarUrl != null) 'userAvatarUrl': userAvatarUrl,
      };

  factory BusinessReview.fromMap(String id, Map<String, dynamic> m) =>
      BusinessReview(
        id: id,
        userId: m['userId']?.toString() ?? id,
        rating: (m['rating'] as num?)?.toInt() ?? 0,
        comment: m['comment']?.toString(),
        createdAt: m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
        editedAt: m['editedAt'] is Timestamp
            ? (m['editedAt'] as Timestamp).toDate()
            : null,
        userDisplayName:
            m['userDisplayName']?.toString() ?? 'Utente',
        userAvatarUrl: m['userAvatarUrl']?.toString(),
      );
}

/// Sorgente di una traccia consigliata.
enum RecommendedTrackSource {
  /// Traccia privata di un utente (path: users/{ownerId}/tracks/{trackId}).
  /// Tipicamente è una traccia dell'owner del business o di un suo collaboratore.
  privateTrack('private'),

  /// Traccia pubblicata in community (path: community_tracks/{trackId}).
  /// Visibile a tutti, può essere di qualsiasi utente.
  communityTrack('community');

  final String wireName;
  const RecommendedTrackSource(this.wireName);

  static RecommendedTrackSource fromWire(String? s) {
    return RecommendedTrackSource.values.firstWhere(
      (v) => v.wireName == s,
      orElse: () => RecommendedTrackSource.communityTrack,
    );
  }
}

/// Traccia consigliata sul profilo di uno Spazio Pro.
/// L'owner del business cura una lista di percorsi (proprie + community)
/// che ritiene rilevanti per i suoi clienti. I metadati sono
/// denormalizzati al momento dell'add per evitare N query in lettura.
class RecommendedTrack {
  /// ID Firestore del documento. Coincide con [trackId] (dedup automatico).
  final String? id;

  /// ID della traccia originale (in users/{ownerId}/tracks o community_tracks).
  final String trackId;
  final RecommendedTrackSource sourceType;

  /// Owner della traccia originale (utile per costruire il path private).
  /// Per community track, è il `ownerId` denormalizzato dal doc community.
  final String? trackOwnerId;
  final String? trackOwnerUsername;

  /// Owner del business che ha aggiunto la voce.
  final String addedBy;
  final DateTime addedAt;
  final int order;
  final String? note;

  // Metadati denormalizzati per preview rapida
  final String trackName;
  final double trackDistance; // metri
  final double trackElevationGain; // metri
  final String trackActivityType;
  final int? trackDurationSec;
  final String? trackPhotoUrl;

  /// 7.D3 — Punto di partenza denormalizzato per mostrare il marker
  /// sulla mappa aggregata della landing pubblica senza dover fetchare
  /// la traccia originale per ognuna. Optional per back-compat.
  final double? trackStartLat;
  final double? trackStartLng;

  const RecommendedTrack({
    this.id,
    required this.trackId,
    required this.sourceType,
    this.trackOwnerId,
    this.trackOwnerUsername,
    required this.addedBy,
    required this.addedAt,
    this.order = 0,
    this.note,
    required this.trackName,
    required this.trackDistance,
    required this.trackElevationGain,
    required this.trackActivityType,
    this.trackDurationSec,
    this.trackPhotoUrl,
    this.trackStartLat,
    this.trackStartLng,
  });

  Map<String, dynamic> toMap() => {
        'trackId': trackId,
        'sourceType': sourceType.wireName,
        if (trackOwnerId != null) 'trackOwnerId': trackOwnerId,
        if (trackOwnerUsername != null) 'trackOwnerUsername': trackOwnerUsername,
        'addedBy': addedBy,
        'addedAt': Timestamp.fromDate(addedAt),
        'order': order,
        if (note != null && note!.isNotEmpty) 'note': note,
        'trackName': trackName,
        'trackDistance': trackDistance,
        'trackElevationGain': trackElevationGain,
        'trackActivityType': trackActivityType,
        if (trackDurationSec != null) 'trackDurationSec': trackDurationSec,
        if (trackPhotoUrl != null) 'trackPhotoUrl': trackPhotoUrl,
        if (trackStartLat != null) 'trackStartLat': trackStartLat,
        if (trackStartLng != null) 'trackStartLng': trackStartLng,
      };

  factory RecommendedTrack.fromMap(String id, Map<String, dynamic> m) =>
      RecommendedTrack(
        id: id,
        trackId: m['trackId']?.toString() ?? id,
        sourceType: RecommendedTrackSource.fromWire(m['sourceType']?.toString()),
        trackOwnerId: m['trackOwnerId']?.toString(),
        trackOwnerUsername: m['trackOwnerUsername']?.toString(),
        addedBy: m['addedBy']?.toString() ?? '',
        addedAt: m['addedAt'] is Timestamp
            ? (m['addedAt'] as Timestamp).toDate()
            : DateTime.now(),
        order: (m['order'] as num?)?.toInt() ?? 0,
        note: m['note']?.toString(),
        trackName: m['trackName']?.toString() ?? 'Senza nome',
        trackDistance: (m['trackDistance'] as num?)?.toDouble() ?? 0,
        trackElevationGain:
            (m['trackElevationGain'] as num?)?.toDouble() ?? 0,
        trackActivityType: m['trackActivityType']?.toString() ?? 'trekking',
        trackDurationSec: (m['trackDurationSec'] as num?)?.toInt(),
        trackPhotoUrl: m['trackPhotoUrl']?.toString(),
        trackStartLat: (m['trackStartLat'] as num?)?.toDouble(),
        trackStartLng: (m['trackStartLng'] as num?)?.toDouble(),
      );

  String get distanceKmFormatted =>
      '${(trackDistance / 1000).toStringAsFixed(1)} km';

  String get elevationFormatted =>
      '+${trackElevationGain.toStringAsFixed(0)} m';
}

/// Voce di listino (servizio/prodotto offerto dal business).
enum PriceUnit {
  day,
  hour,
  week,
  piece,
  fixed,
  night;

  String get displayName {
    switch (this) {
      case PriceUnit.day:
        return 'al giorno';
      case PriceUnit.hour:
        return 'all\'ora';
      case PriceUnit.week:
        return 'a settimana';
      case PriceUnit.piece:
        return 'a pezzo';
      case PriceUnit.fixed:
        return 'totale';
      case PriceUnit.night:
        return 'a notte';
    }
  }
}

class BusinessService {
  final String? id;
  final String name;
  final String? description;
  final double? price;
  final PriceUnit priceUnit;
  final String? photoUrl;
  final int order;
  final bool isActive;

  const BusinessService({
    this.id,
    required this.name,
    this.description,
    this.price,
    this.priceUnit = PriceUnit.fixed,
    this.photoUrl,
    this.order = 0,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        if (description != null) 'description': description,
        if (price != null) 'price': price,
        'priceUnit': priceUnit.name,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'order': order,
        'isActive': isActive,
      };

  factory BusinessService.fromMap(String id, Map<String, dynamic> m) =>
      BusinessService(
        id: id,
        name: m['name']?.toString() ?? '',
        description: m['description']?.toString(),
        price: (m['price'] as num?)?.toDouble(),
        priceUnit: PriceUnit.values.firstWhere(
          (u) => u.name == m['priceUnit'],
          orElse: () => PriceUnit.fixed,
        ),
        photoUrl: m['photoUrl']?.toString(),
        order: (m['order'] as num?)?.toInt() ?? 0,
        isActive: m['isActive'] != false,
      );
}
