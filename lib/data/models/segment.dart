import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// Segmento cronometrato creato da un admin su un sentiero pubblico.
/// Gli utenti vengono cronometrati automaticamente quando lo attraversano.
class Segment {
  final String id;
  final String name;
  final String description;
  final String trailId;
  final String createdBy;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final List<LatLng> polyline;
  final double distance; // metri
  final double elevationGain; // metri
  final String? activityType;
  final DateTime createdAt;

  /// True solo se creato da un admin da un sentiero pubblico OSM.
  final bool isOfficial;

  /// Visibilità pubblica (leaderboard condivisa + matching per altri utenti).
  /// Admin-created è sempre pubblico; user-created è scelta dell'utente.
  final bool isPublic;

  /// ID della traccia personale da cui è stato creato (solo user-created).
  /// `null` per admin-created.
  final String? sourceTrackId;

  const Segment({
    required this.id,
    required this.name,
    this.description = '',
    required this.trailId,
    required this.createdBy,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.polyline,
    required this.distance,
    this.elevationGain = 0,
    this.activityType,
    required this.createdAt,
    this.isOfficial = false,
    this.isPublic = true,
    this.sourceTrackId,
  });

  LatLng get startPoint => LatLng(startLat, startLng);
  LatLng get endPoint => LatLng(endLat, endLng);

  factory Segment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final polyRaw = data['polyline'] as List? ?? const [];
    final polyline = polyRaw
        .map((e) {
          final m = e as Map<String, dynamic>;
          return LatLng(
            (m['lat'] as num).toDouble(),
            (m['lng'] as num).toDouble(),
          );
        })
        .toList();
    return Segment(
      id: doc.id,
      name: data['name'] ?? 'Segmento',
      description: data['description'] ?? '',
      trailId: data['trailId'] ?? '',
      createdBy: data['createdBy'] ?? '',
      startLat: (data['startLat'] as num?)?.toDouble() ?? 0,
      startLng: (data['startLng'] as num?)?.toDouble() ?? 0,
      endLat: (data['endLat'] as num?)?.toDouble() ?? 0,
      endLng: (data['endLng'] as num?)?.toDouble() ?? 0,
      polyline: polyline,
      distance: (data['distance'] as num?)?.toDouble() ?? 0,
      elevationGain: (data['elevationGain'] as num?)?.toDouble() ?? 0,
      activityType: data['activityType'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isOfficial: data['isOfficial'] == true,
      isPublic: data['isPublic'] != false, // default true per retrocompatibilità
      sourceTrackId: data['sourceTrackId'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'name': name,
        'description': description,
        'trailId': trailId,
        'createdBy': createdBy,
        'startLat': startLat,
        'startLng': startLng,
        'endLat': endLat,
        'endLng': endLng,
        'polyline': polyline
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'distance': distance,
        'elevationGain': elevationGain,
        'activityType': activityType,
        'createdAt': FieldValue.serverTimestamp(),
        'isOfficial': isOfficial,
        'isPublic': isPublic,
        if (sourceTrackId != null) 'sourceTrackId': sourceTrackId,
      };
}

/// Un tentativo cronometrato su un segmento da parte di un utente.
class SegmentEffort {
  final String id;
  final String userId;
  final String username;
  final String? avatarUrl;
  final String trackId;
  final int durationSeconds;
  final double distance; // metri (quella del segmento, denormalizzata)
  final double averageSpeedKmh;
  final DateTime completedAt;

  /// Indice del punto di partenza dentro la traccia.
  ///
  /// LO SCRIVE SOLO IL LATO SERVER (Cloud Function e recupero storico), che
  /// legge la traccia COME E' SALVATA. L'app confronta invece sui punti in
  /// memoria a piena risoluzione, mentre su Firestore ne finiscono al massimo
  /// mille (`_downsamplePoints`): lo stesso passaggio ha quindi due indici
  /// diversi, e un indice del client non combacerebbe mai con quello del
  /// server. Per distinguere i giri fra le due sponde si usa [passIndex],
  /// che e' un ordinale e non dipende da quanti punti sono rimasti.
  final int? trackStartIdx;

  /// Quale giro e', dentro quella uscita: 0 il primo. GEMELLO di
  /// `indicePassaggio` in functions/segment_matching.js. E' la chiave con cui
  /// il recupero storico riconosce i passaggi gia' scritti.
  /// Assente sugli sforzi scritti prima della 2.9.1.
  final int? passIndex;

  const SegmentEffort({
    required this.id,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.trackId,
    required this.durationSeconds,
    required this.distance,
    required this.averageSpeedKmh,
    required this.completedAt,
    this.trackStartIdx,
    this.passIndex,
  });

  factory SegmentEffort.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SegmentEffort(
      id: doc.id,
      userId: data['userId'] ?? '',
      username: data['username'] ?? 'Utente',
      avatarUrl: data['avatarUrl'],
      trackId: data['trackId'] ?? '',
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      distance: (data['distance'] as num?)?.toDouble() ?? 0,
      averageSpeedKmh: (data['averageSpeedKmh'] as num?)?.toDouble() ?? 0,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      trackStartIdx: (data['trackStartIdx'] as num?)?.toInt(),
      passIndex: (data['passIndex'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'userId': userId,
        'username': username,
        'avatarUrl': avatarUrl,
        'trackId': trackId,
        'durationSeconds': durationSeconds,
        'distance': distance,
        'averageSpeedKmh': averageSpeedKmh,
        // L'ORA DEL PASSAGGIO, non quella della scrittura. Con
        // FieldValue.serverTimestamp() i giri di una stessa uscita finivano
        // tutti allo stesso istante e lo storico personale non poteva piu'
        // dire quale venisse prima — cioe' proprio il confronto fra un giro
        // e l'altro. Su una traccia sincronizzata dall'orologio a fine
        // giornata l'ora del server e' anche l'ora sbagliata.
        'completedAt': Timestamp.fromDate(completedAt),
        if (trackStartIdx != null) 'trackStartIdx': trackStartIdx,
        if (passIndex != null) 'passIndex': passIndex,
      };

  String get durationFormatted {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

/// Risultato di un match "segmento + nuovo record" per il dialog post-save.
class SegmentMatchResult {
  final Segment segment;
  final int durationSeconds;
  final double distance;
  final bool isNewRecord; // primato assoluto del segmento
  final bool isNewPB; // record personale dell'utente
  final int? previousPBSeconds;

  /// Quanti giri su questo segmento in questa uscita. UNO risultato per
  /// segmento, non uno per giro: otto ripetute sulla stessa salita sono un
  /// segmento fatto otto volte, e il riepilogo che diceva "8 segmenti
  /// completati" elencando otto volte lo stesso nome era semplicemente falso.
  /// [durationSeconds] e' il MIGLIORE dei giri.
  final int passCount;

  const SegmentMatchResult({
    required this.segment,
    required this.durationSeconds,
    required this.distance,
    this.isNewRecord = false,
    this.isNewPB = false,
    this.passCount = 1,
    this.previousPBSeconds,
  });

  String get durationFormatted {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}
