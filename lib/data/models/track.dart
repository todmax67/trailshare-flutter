import 'dart:math';

/// Rappresenta un singolo punto GPS della traccia
class TrackPoint {
  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime timestamp;
  final double? speed;
  final double? accuracy;
  final double? heading;

  const TrackPoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    required this.timestamp,
    this.speed,
    this.accuracy,
    this.heading,
  });

  /// CopyWith — usato principalmente dalla correzione DEM delle quote.
  TrackPoint copyWith({
    double? latitude,
    double? longitude,
    double? elevation,
    DateTime? timestamp,
    double? speed,
    double? accuracy,
    double? heading,
  }) {
    return TrackPoint(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      elevation: elevation ?? this.elevation,
      timestamp: timestamp ?? this.timestamp,
      speed: speed ?? this.speed,
      accuracy: accuracy ?? this.accuracy,
      heading: heading ?? this.heading,
    );
  }

  /// Distanza in metri verso un altro punto (Haversine)
  double distanceTo(TrackPoint other) {
    const R = 6371000.0;
    final dLat = _toRad(other.latitude - latitude);
    final dLon = _toRad(other.longitude - longitude);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(latitude)) * cos(_toRad(other.latitude)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  Map<String, dynamic> toMap() {
    return {
      'lat': latitude,
      'lng': longitude,
      'ele': elevation,
      'time': timestamp.toIso8601String(),
      'speed': speed,
      'accuracy': accuracy,
      'heading': heading,
    };
  }

  /// Crea da Map - ROBUSTO per gestire diversi formati dal JS
  factory TrackPoint.fromMap(Map<String, dynamic> map) {
    // Latitude - prova diversi nomi campo
    double lat = 0;
    if (map['lat'] != null) {
      lat = (map['lat'] as num).toDouble();
    } else if (map['latitude'] != null) {
      lat = (map['latitude'] as num).toDouble();
    }

    // Longitude - prova diversi nomi campo
    double lng = 0;
    if (map['lng'] != null) {
      lng = (map['lng'] as num).toDouble();
    } else if (map['lon'] != null) {
      lng = (map['lon'] as num).toDouble();
    } else if (map['longitude'] != null) {
      lng = (map['longitude'] as num).toDouble();
    }

    // Elevation - prova diversi nomi campo
    double? ele;
    if (map['ele'] != null) {
      ele = (map['ele'] as num).toDouble();
    } else if (map['elevation'] != null) {
      ele = (map['elevation'] as num).toDouble();
    } else if (map['altitude'] != null) {
      ele = (map['altitude'] as num).toDouble();
    }

    // Timestamp
    DateTime timestamp = DateTime.now();
    if (map['time'] != null) {
      timestamp = DateTime.tryParse(map['time'].toString()) ?? DateTime.now();
    } else if (map['timestamp'] != null) {
      if (map['timestamp'] is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(map['timestamp']);
      } else {
        timestamp = DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now();
      }
    }

    return TrackPoint(
      latitude: lat,
      longitude: lng,
      elevation: ele,
      timestamp: timestamp,
      speed: (map['speed'] as num?)?.toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() => 'TrackPoint($latitude, $longitude, ele: $elevation)';
}


/// Tipo di attività
// ============================================================
// NUOVO ENUM ActivityType per track.dart
// 
// ISTRUZIONI: Sostituire SOLO l'enum ActivityType nel file
// lib/data/models/track.dart (righe 108-140 circa)
// NON toccare il resto del file (TrackPoint, Track, TrackStats)
// ============================================================

// IMPORTANTE: i primi 4 valori (trekking, trailRunning, walking, cycling)
// DEVONO restare nello stesso ordine perché recording_persistence_service
// usa l'indice numerico (ActivityType.values[index]) per deserializzare.
// I nuovi valori vanno SEMPRE aggiunti IN FONDO.

enum ActivityType {
  // === Esistenti (NON cambiare ordine! index 0-3) ===
  trekking,       // 0
  trailRunning,   // 1
  walking,        // 2
  cycling,        // 3

  // === Nuovi - Corsa ===
  running,        // 4

  // === Nuovi - Bicicletta ===
  mountainBiking, // 5
  gravelBiking,   // 6
  eBike,          // 7
  eMountainBike,  // 8

  // === Nuovi - Sport invernali ===
  alpineSkiing,   // 9
  skiTouring,     // 10 (scialpinismo)
  nordicSkiing,   // 11
  snowshoeing,    // 12
  snowboarding;   // 13

  /// Nome visualizzato
  String get displayName {
    switch (this) {
      case ActivityType.trekking:
        return 'Trekking';
      case ActivityType.trailRunning:
        return 'Trail Running';
      case ActivityType.walking:
        return 'Camminata';
      case ActivityType.cycling:
        return 'Ciclismo';
      case ActivityType.running:
        return 'Corsa';
      case ActivityType.mountainBiking:
        return 'Mountain Bike';
      case ActivityType.gravelBiking:
        return 'Gravel Bike';
      case ActivityType.eBike:
        return 'E-Bike';
      case ActivityType.eMountainBike:
        return 'E-Mountain Bike';
      case ActivityType.alpineSkiing:
        return 'Sci Alpino';
      case ActivityType.skiTouring:
        return 'Scialpinismo';
      case ActivityType.nordicSkiing:
        return 'Sci Nordico';
      case ActivityType.snowshoeing:
        return 'Racchette da Neve';
      case ActivityType.snowboarding:
        return 'Snowboard';
    }
  }

  /// Emoji icona
  String get icon {
    switch (this) {
      case ActivityType.trekking:
        return '🥾';
      case ActivityType.trailRunning:
        return '🏃';
      case ActivityType.walking:
        return '🚶';
      case ActivityType.cycling:
        return '🚴';
      case ActivityType.running:
        return '🏃‍♂️';
      case ActivityType.mountainBiking:
        return '🚵';
      case ActivityType.gravelBiking:
        return '🚴‍♂️';
      case ActivityType.eBike:
        return '⚡';
      case ActivityType.eMountainBike:
        return '⚡';
      case ActivityType.alpineSkiing:
        return '⛷️';
      case ActivityType.skiTouring:
        return '🎿';
      case ActivityType.nordicSkiing:
        return '🎿';
      case ActivityType.snowshoeing:
        return '❄️';
      case ActivityType.snowboarding:
        return '🏂';
    }
  }

  /// Categoria sport (per raggruppamento nel selettore)
  String get category {
    switch (this) {
      case ActivityType.trekking:
      case ActivityType.trailRunning:
      case ActivityType.walking:
      case ActivityType.running:
        return 'A piedi';
      case ActivityType.cycling:
      case ActivityType.mountainBiking:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
      case ActivityType.eMountainBike:
        return 'In bicicletta';
      case ActivityType.alpineSkiing:
      case ActivityType.skiTouring:
      case ActivityType.nordicSkiing:
      case ActivityType.snowshoeing:
      case ActivityType.snowboarding:
        return 'Sport invernali';
    }
  }

  /// Profilo elevazione da usare per il filtraggio GPS
  /// Mappa le nuove attività ai profili esistenti di ElevationProcessor
  String get elevationProfile {
    switch (this) {
      case ActivityType.trekking:
      case ActivityType.skiTouring:
      case ActivityType.snowshoeing:
        return 'trekking';
      case ActivityType.trailRunning:
      case ActivityType.running:
        return 'trailRunning';
      case ActivityType.walking:
      case ActivityType.nordicSkiing:
        return 'walking';
      case ActivityType.cycling:
      case ActivityType.mountainBiking:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
      case ActivityType.eMountainBike:
        return 'cycling';
      case ActivityType.alpineSkiing:
      case ActivityType.snowboarding:
        return 'cycling'; // Discese veloci, simile a ciclismo
    }
  }
}

/// Statistiche della traccia
class TrackStats {
  final double distance;
  final double elevationGain;
  final double elevationLoss;
  final double maxElevation;
  final double minElevation;
  final Duration duration;
  final Duration movingTime;
  final double currentSpeed;
  final double avgSpeed;
  final double maxSpeed;

  const TrackStats({
    this.distance = 0,
    this.elevationGain = 0,
    this.elevationLoss = 0,
    this.maxElevation = 0,
    this.minElevation = 0,
    this.duration = Duration.zero,
    this.movingTime = Duration.zero,
    this.currentSpeed = 0,
    this.avgSpeed = 0,
    this.maxSpeed = 0,
  });

  double get distanceKm => distance / 1000;
  String get durationFormatted {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  TrackStats copyWith({
    double? distance,
    double? elevationGain,
    double? elevationLoss,
    double? maxElevation,
    double? minElevation,
    Duration? duration,
    Duration? movingTime,
    double? currentSpeed,
    double? avgSpeed,
    double? maxSpeed,
  }) {
    return TrackStats(
      distance: distance ?? this.distance,
      elevationGain: elevationGain ?? this.elevationGain,
      elevationLoss: elevationLoss ?? this.elevationLoss,
      maxElevation: maxElevation ?? this.maxElevation,
      minElevation: minElevation ?? this.minElevation,
      duration: duration ?? this.duration,
      movingTime: movingTime ?? this.movingTime,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      maxSpeed: maxSpeed ?? this.maxSpeed,
    );
  }
}


/// 📸 NUOVO: Metadata foto traccia
class TrackPhotoMetadata {
  final String url;
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final DateTime timestamp;
  final String? caption;

  const TrackPhotoMetadata({
    required this.url,
    this.latitude,
    this.longitude,
    this.elevation,
    required this.timestamp,
    this.caption,
  });

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'latitude': latitude,
      'longitude': longitude,
      'elevation': elevation,
      'timestamp': timestamp.toIso8601String(),
      'caption': caption,
    };
  }

  factory TrackPhotoMetadata.fromMap(Map<String, dynamic> map) {
    return TrackPhotoMetadata(
      url: map['url'] as String,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      elevation: map['elevation'] as double?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      caption: map['caption'] as String?,
    );
  }
}


/// Un giro chiuso DAL DISPOSITIVO durante la registrazione.
///
/// Diverso dai giri che la scheda calcola da sola ogni chilometro: questi sono
/// i giri veri, quelli che hai segnato col tasto o che l'orologio ha chiuso
/// all'auto-giro. In un allenamento a ripetute è la differenza fra vedere i
/// tuoi intervalli e vedere dei chilometri qualsiasi.
///
/// Non porta indici di punto di proposito: il buffer dell'orologio si dimezza
/// sulle uscite lunghe e un indice registrato prima indicherebbe un altro
/// punto. Gli indici li ricava chi disegna, camminando sui punti fino alla
/// distanza cumulata — così restano giusti anche se la traccia viene
/// risalvata e i punti decimati.
class TrackLap {
  final double distance; // metri
  final Duration duration;
  final double elevationGain; // metri
  final int? avgHeartRate;

  const TrackLap({
    required this.distance,
    required this.duration,
    this.elevationGain = 0,
    this.avgHeartRate,
  });

  Map<String, dynamic> toMap() => {
        'distance': distance,
        'duration': duration.inSeconds,
        'elevationGain': elevationGain,
        if (avgHeartRate != null && avgHeartRate! > 0) 'avgHeartRate': avgHeartRate,
      };

  factory TrackLap.fromMap(Map<String, dynamic> map) {
    final hr = (map['avgHeartRate'] as num?)?.toInt();
    return TrackLap(
      distance: (map['distance'] as num?)?.toDouble() ?? 0,
      duration: Duration(seconds: (map['duration'] as num?)?.toInt() ?? 0),
      elevationGain: (map['elevationGain'] as num?)?.toDouble() ?? 0,
      avgHeartRate: (hr != null && hr > 0) ? hr : null,
    );
  }
}

/// Un tratto in cui la registrazione ha smesso di ricevere punti.
///
/// Il watchdog di [LocationService] se ne accorge e lo dice all'utente mentre
/// cammina, ma finora quell'informazione moriva con la schermata: la traccia
/// salvata non sapeva di avere un buco. Il risultato e' che la mappa collega i
/// due estremi con una **retta identica al resto del percorso**, e chi la
/// guarda — o la riceve condivisa — legge come strada percorsa un tratto dove
/// non e' mai passato nessuno.
///
/// Non si puo' impedire del tutto (quando il sistema congela il processo non
/// gira una riga di codice nostro, e non ci riesce nemmeno la concorrenza), ma
/// si puo' smettere di presentarlo come se non fosse successo.
///
/// Gli estremi vengono dal watchdog, che misura la deriva dell'orologio: sono
/// precisi al tick, non al secondo. Meglio dichiarare "circa dodici minuti"
/// che fingere una precisione che non abbiamo.
class TrackGap {
  /// Il watchdog ha visto il sistema sospendere il processo.
  static const String causeAppFrozen = 'appFrozen';

  /// L'app era viva ma lo stream di posizioni aveva smesso di consegnare.
  static const String causeStreamStalled = 'streamStalled';

  /// Dichiarato dal proprietario a posteriori: "quel tratto dritto non e'
  /// strada che ho percorso". Va tenuto distinto dagli altri due perche' e'
  /// l'unico che il proprietario puo' anche RIMUOVERE — una dichiarazione si
  /// puo' ritirare, una misura del watchdog no.
  static const String causeOwnerDeclared = 'ownerDeclared';

  /// Ultimo istante con dati validi.
  final DateTime startedAt;

  /// Istante in cui la registrazione e' ripartita.
  final DateTime endedAt;

  /// Vedi le costanti `cause*` qui sopra. Stringa libera per tollerare valori
  /// futuri senza rompere la deserializzazione.
  final String cause;

  const TrackGap({
    required this.startedAt,
    required this.endedAt,
    required this.cause,
  });

  Duration get duration => endedAt.difference(startedAt);

  bool get isOwnerDeclared => cause == causeOwnerDeclared;

  Map<String, dynamic> toMap() => {
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
        'cause': cause,
      };

  factory TrackGap.fromMap(Map<String, dynamic> map) {
    final start = DateTime.tryParse(map['startedAt']?.toString() ?? '');
    final end = DateTime.tryParse(map['endedAt']?.toString() ?? '');
    final safeStart = start ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return TrackGap(
      startedAt: safeStart,
      // Un buco senza fine leggibile resta un buco: si tiene, con durata zero,
      // invece di sparire e far tornare la traccia "completa".
      endedAt: end ?? safeStart,
      cause: map['cause']?.toString() ?? 'unknown',
    );
  }
}

/// Traccia completa (CON FOTO)
class Track {
  final String? id;
  final String name;
  final String? description;
  final List<TrackPoint> points;
  final ActivityType activityType;
  final DateTime? recordedAt;
  final DateTime createdAt;
  final String? userId;
  final bool isPublic;

  /// Pubblicata ma tenuta fuori dal feed cronologico della Community
  /// ("Pubblica solo nel tour"). Denormalizzato qui dalla copia in
  /// published_tracks per sapere lo stato senza rileggere quel doc,
  /// che contiene i punti GPS ed è pesante.
  final bool hiddenFromFeed;
  final bool isPlanned;
  final TrackStats stats;

  /// Lista degli ID dei gruppi in cui questa traccia è "consigliata"
  /// (visibile come percorso nel tab Percorsi del gruppo). Vuota = non
  /// condivisa con nessun gruppo.
  ///
  /// Una traccia può essere consigliata in più gruppi
  /// contemporaneamente (es. l'admin di un noleggio ebike la condivide
  /// sia nel gruppo "Stagione 2026" sia in "Tour panoramici").
  /// Le query lato gruppo usano `array-contains`.
  final List<String> groupIds;
  
  // 📸 NUOVO: Lista foto
  final List<TrackPhotoMetadata> photos;

  /// Giri chiusi dal dispositivo durante la registrazione (orologio Garmin).
  /// Vuota su tutte le tracce che non arrivano da un device che li segna: in
  /// quel caso la scheda continua a calcolarli ogni chilometro.
  final List<TrackLap> laps;

  /// I tratti in cui la registrazione si e' fermata. Vuota quando e' filata
  /// liscia — che e' anche il caso di tutte le tracce salvate prima che questo
  /// campo esistesse, per le quali un elenco vuoto non significa "nessun buco"
  /// ma "non lo sappiamo".
  final List<TrackGap> gaps;

  // ❤️ Dati battito cardiaco da Health Connect/Apple Health
  // Mappa: timestamp -> BPM
  final Map<DateTime, int>? heartRateData;
  // 🔥 Calorie reali da Health Connect/Apple Health
  final double? healthCalories;
  // 👣 Passi da Health Connect/Apple Health
  final int? healthSteps;
  // Traccia importata automaticamente da Strava (es. attività Garmin via Strava)
  final bool importedFromStrava;
  // ID dell'attività Strava da cui questa traccia è stata importata
  final String? stravaSourceActivityId;

  /// 5.5 — Tag personalizzati creati dall'utente (es. "vacanze 2026",
  /// "test scarpe nuove", "con cane"). Salvati lowercase per ricerca
  /// case-insensitive coerente. Filtrabili in "Le mie tracce".
  final List<String> tags;

  /// Komoot K1a Step 2 — difficoltà computata dalla formula
  /// `DifficultyCalculator`. Persistita per evitare ricalcolo a ogni
  /// render e per consentire filtri Firestore (es. tracce T3+).
  /// Storage: stringa "t1".."t5" via `ComputedDifficulty.firestoreKey`.
  /// null = non ancora calcolata (tracce legacy o stats insufficienti).
  final String? computedDifficulty;

  /// `true` se le quote dei TrackPoint sono state corrette via DEM
  /// (AWS Open Terrain Tiles, vedi `ElevationDemCorrector`). Le tracce
  /// pre-2026-05-27 sono `false` (quote GPS grezze): possono essere
  /// corrette retroattivamente dal menu di TrackDetail.
  final bool elevationCorrectedFromDem;

  /// Override manuale della difficoltà impostato dall'utente nel detail.
  /// Se non-null, prevale su [computedDifficulty] in tutte le UI e nei
  /// filtri. Permette di correggere casi limite dove l'algoritmo
  /// sotto/sovrastima (es. via ferrata breve, ebike con dislivello
  /// percepito alto, terreno tecnico).
  /// Aggiunto 2026-05-27 dopo feedback utente.
  final String? manualDifficulty;

  /// `true` se il documento Firestore da cui arriva questa traccia ha
  /// ancora scritture in coda (`snapshot.metadata.hasPendingWrites`): la
  /// traccia esiste in locale ma il server non l'ha ancora confermata.
  /// Campo **transiente**: vive solo in memoria, non viene serializzato
  /// (non ha senso persistere lo stato di sync dentro il doc stesso).
  final bool pendingSync;

  /// Difficoltà effettiva = override manuale se presente, altrimenti
  /// quella computata. Usare questa nelle UI per visualizzazione e
  /// nei filtri community (no distinzione fra auto/manual).
  String? get effectiveDifficulty => manualDifficulty ?? computedDifficulty;

  /// `true` se la difficoltà mostrata è stata impostata manualmente
  /// dall'utente (non calcolata automaticamente). Usato per mostrare
  /// un piccolo indicatore "✏️" nel badge.
  bool get hasManualDifficulty => manualDifficulty != null;

  /// `true` se la traccia è un'attività **realmente svolta** che deve
  /// contare in dashboard, classifiche, badge e XP. Esclude i percorsi
  /// pianificati col Planner (`isPlanned`) e le tracce vuote/annullate
  /// (distanza 0). Regola canonica UNICA: usarla ovunque si aggreghino
  /// statistiche, così la definizione di "attività reale" vive in un solo
  /// posto (lato server l'equivalente è `isPlanned !== true && distance > 0`).
  bool get countsAsActivity => !isPlanned && stats.distance > 0;

  const Track({
    this.id,
    required this.name,
    this.description,
    required this.points,
    this.activityType = ActivityType.trekking,
    this.recordedAt,
    required this.createdAt,
    this.userId,
    this.isPublic = false,
    this.hiddenFromFeed = false,
    this.isPlanned = false,
    this.stats = const TrackStats(),
    this.groupIds = const [],
    this.photos = const [], // 📸 Default: nessuna foto
    this.laps = const [], // giri dal dispositivo, se li manda
    this.gaps = const [], // buchi di registrazione, se ce ne sono stati
    this.heartRateData, // ❤️ Battito cardiaco (opzionale)
    this.healthCalories, // 🔥 Calorie reali (opzionale)
    this.healthSteps, // 👣 Passi (opzionale)
    this.importedFromStrava = false,
    this.stravaSourceActivityId,
    this.tags = const [],
    this.computedDifficulty,
    this.manualDifficulty,
    this.elevationCorrectedFromDem = false,
    this.pendingSync = false,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'description': description,
      'points': points.map((p) => p.toMap()).toList(),
      'activityType': activityType.name,
      'recordedAt': recordedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'userId': userId,
      'isPublic': isPublic,
      'hiddenFromFeed': hiddenFromFeed,
      'isPlanned': isPlanned,
      'groupIds': groupIds,
      'distance': stats.distance,
      'elevationGain': stats.elevationGain,
      'elevationLoss': stats.elevationLoss,
      'duration': stats.duration.inSeconds,
      'movingTime': stats.movingTime.inSeconds,
      // 📸 NUOVO
      'photos': photos.map((p) => p.toMap()).toList(),
      // Solo se ci sono: l'assenza del campo e' gia' il segnale per tornare
      // ai giri calcolati al chilometro.
      if (laps.isNotEmpty) 'laps': laps.map((l) => l.toMap()).toList(),
      // Come per i giri: si scrive solo se c'e' qualcosa da dire. La differenza
      // e' che qui l'assenza del campo non e' neutra — vuol dire che di quella
      // traccia non sappiamo se sia intera, non che lo sia.
      if (gaps.isNotEmpty) 'gaps': gaps.map((g) => g.toMap()).toList(),
    };

    // ❤️ Battito cardiaco (aggiunto separatamente per chiarezza)
    if (heartRateData != null && heartRateData!.isNotEmpty) {
      map['heartRateData'] = heartRateData!.map(
        (key, value) => MapEntry(key.millisecondsSinceEpoch.toString(), value),
      );
    }
    if (healthCalories != null) {
      map['healthCalories'] = healthCalories;
    }
    if (healthSteps != null) {
      map['healthSteps'] = healthSteps;
    }
    if (importedFromStrava) {
      map['importedFromStrava'] = true;
    }
    if (stravaSourceActivityId != null) {
      map['stravaSourceActivityId'] = stravaSourceActivityId;
    }
    // 5.5 — Salviamo i tag solo se non vuoti per non sporcare il doc.
    if (tags.isNotEmpty) {
      map['tags'] = tags;
    }
    if (computedDifficulty != null) {
      map['computedDifficulty'] = computedDifficulty;
    }
    if (manualDifficulty != null) {
      map['manualDifficulty'] = manualDifficulty;
    }
    if (elevationCorrectedFromDem) {
      map['elevationCorrectedFromDem'] = true;
    }

    return map;
  }

  Track copyWith({
    String? id,
    String? name,
    String? description,
    List<TrackPoint>? points,
    ActivityType? activityType,
    DateTime? recordedAt,
    DateTime? createdAt,
    String? userId,
    bool? isPublic,
    bool? hiddenFromFeed,
    bool? isPlanned,
    TrackStats? stats,
    List<String>? groupIds,
    List<TrackPhotoMetadata>? photos, // 📸 NUOVO
    List<TrackLap>? laps,
    List<TrackGap>? gaps,
    Map<DateTime, int>? heartRateData, // ❤️
    double? healthCalories, // 🔥
    int? healthSteps, // 👣
    bool? importedFromStrava,
    String? stravaSourceActivityId,
    List<String>? tags,
    String? computedDifficulty,
    String? manualDifficulty,
    bool clearManualDifficulty = false,
    bool? elevationCorrectedFromDem,
    bool? pendingSync,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      points: points ?? this.points,
      activityType: activityType ?? this.activityType,
      recordedAt: recordedAt ?? this.recordedAt,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      isPublic: isPublic ?? this.isPublic,
      hiddenFromFeed: hiddenFromFeed ?? this.hiddenFromFeed,
      isPlanned: isPlanned ?? this.isPlanned,
      stats: stats ?? this.stats,
      groupIds: groupIds ?? this.groupIds,
      photos: photos ?? this.photos, // 📸 NUOVO
      laps: laps ?? this.laps,
      gaps: gaps ?? this.gaps,
      heartRateData: heartRateData ?? this.heartRateData, // ❤️
      healthCalories: healthCalories ?? this.healthCalories, // 🔥
      healthSteps: healthSteps ?? this.healthSteps, // 👣
      importedFromStrava: importedFromStrava ?? this.importedFromStrava,
      stravaSourceActivityId: stravaSourceActivityId ?? this.stravaSourceActivityId,
      tags: tags ?? this.tags,
      computedDifficulty: computedDifficulty ?? this.computedDifficulty,
      manualDifficulty: clearManualDifficulty
          ? null
          : (manualDifficulty ?? this.manualDifficulty),
      elevationCorrectedFromDem:
          elevationCorrectedFromDem ?? this.elevationCorrectedFromDem,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
}
