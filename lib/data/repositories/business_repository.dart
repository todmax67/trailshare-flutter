import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/geohash_util.dart';
import '../models/business.dart';

/// Repository per Business (Spazio Pro). Gestisce CRUD su:
/// - businesses/{id}
/// - businesses/{id}/followers/{uid}
/// - businesses/{id}/posts/{postId}
/// - businesses/{id}/services/{serviceId}
class BusinessRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _businesses =>
      _db.collection('businesses');

  // ═══════════════════════════════════════════════════════════════════════════
  // CREATE / UPDATE / DELETE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Crea un nuovo business. ownerId = utente loggato.
  /// Lo slug viene generato dal nome; in caso di collisione viene aggiunto
  /// un suffisso numerico.
  Future<String> createBusiness({
    required String name,
    required BusinessType type,
    required double lat,
    required double lng,
    String? address,
    String? city,
    String? region,
    String? description,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utente non autenticato');

    final slug = await _generateUniqueSlug(name);
    final geohash = GeoHashUtil.encode(lat, lng);

    final business = Business(
      name: name,
      slug: slug,
      type: type,
      ownerId: user.uid,
      location: BusinessLocation(
        lat: lat,
        lng: lng,
        geohash: geohash,
        address: address,
        city: city,
        region: region,
      ),
      description: description,
      createdAt: DateTime.now(),
    );

    final ref = await _businesses.add(business.toMap());
    debugPrint('[BusinessRepo] Business creato: ${ref.id} ($slug)');
    return ref.id;
  }

  Future<Business?> getBusiness(String id) async {
    final snap = await _businesses.doc(id).get();
    if (!snap.exists) return null;
    return Business.fromMap(snap.id, snap.data()!);
  }

  Future<Business?> getBusinessBySlug(String slug) async {
    final snap = await _businesses
        .where('slug', isEqualTo: slug)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Business.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  /// Stream del business singolo (per detail page reattiva).
  Stream<Business?> watchBusiness(String id) {
    return _businesses.doc(id).snapshots().map(
        (s) => s.exists ? Business.fromMap(s.id, s.data()!) : null);
  }

  Future<void> updateBusiness(String id, Map<String, dynamic> patch) async {
    patch['updatedAt'] = Timestamp.fromDate(DateTime.now());
    await _businesses.doc(id).update(patch);
  }

  Future<void> deleteBusiness(String id) async {
    await _businesses.doc(id).delete();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMUNITY VIP — link bidirezionale con un Group esistente
  // ═══════════════════════════════════════════════════════════════════════════

  /// Linka un gruppo come Community VIP del Business. Setta il link
  /// bidirezionale: `businesses/{id}.linkedGroupId` e
  /// `groups/{groupId}.linkedBusinessId` + `linkedBusinessName`
  /// (denormalizzato per il badge).
  ///
  /// La chiamata DEVE essere fatta dall'owner del Business e dall'admin
  /// del gruppo (controllo lato UI; le rules sono più permissive ma
  /// l'utente ha bisogno di entrambi i ruoli per orchestrare).
  Future<void> linkGroupAsCommunity({
    required String businessId,
    required String groupId,
    required String businessName,
  }) async {
    final batch = _db.batch();
    batch.update(_businesses.doc(businessId), {
      'linkedGroupId': groupId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    batch.update(_db.collection('groups').doc(groupId), {
      'linkedBusinessId': businessId,
      'linkedBusinessName': businessName,
    });
    await batch.commit();
    debugPrint(
        '[BusinessRepo] linkGroupAsCommunity: $businessId ↔ $groupId');
  }

  /// Rimuove il link bidirezionale Business ↔ Group. Il gruppo torna
  /// gruppo normale (Free, salvo owner Pro o isBusinessGroup admin).
  Future<void> unlinkCommunityGroup({
    required String businessId,
    required String groupId,
  }) async {
    final batch = _db.batch();
    batch.update(_businesses.doc(businessId), {
      'linkedGroupId': FieldValue.delete(),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    batch.update(_db.collection('groups').doc(groupId), {
      'linkedBusinessId': FieldValue.delete(),
      'linkedBusinessName': FieldValue.delete(),
    });
    await batch.commit();
    debugPrint('[BusinessRepo] unlinkCommunityGroup: $businessId ↔ $groupId');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUERY DISCOVERY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tutti i business attivi nelle vicinanze del punto dato.
  /// Per MVP: prefiltra via geohash ranges, poi filtro distanza esatta in
  /// memoria. Volumi attesi bassi (decine di business per area). Quando
  /// supereremo le centinaia, valutare GeoFlutterFire o query server-side.
  Future<List<Business>> getNearby({
    required double lat,
    required double lng,
    double radiusKm = 50,
    BusinessType? type,
    int limit = 1000,
  }) async {
    final precision = GeoHashUtil.precisionForRadius(radiusKm);

    // Costruisce il set di geohash da coprire a partire dal CENTRO +
    // neighbors. Importante: NON uso GeoHashUtil.getNeighbors perché
    // il suo `delta` è circa metà-cella (180 / 2^(p*2.5)) → spesso
    // ritorna lo stesso hash del centro o un solo vicino. Bug
    // diagnosticato in produzione: getNearby(50km) restituiva solo
    // 47 schede invece di tutte quelle in raggio.
    //
    // Soluzione: uso `decodeBounds` per estrarre il bbox della cella
    // del centro e sposto di una CELLA INTERA per ogni vicino.
    //
    // Cell width approssimata per scelta del ring. Geohash precision
    // 5 ≈ 5km, precision 6 ≈ 1.2km, ecc.
    const cellWidthByPrecision = {
      1: 5000.0, 2: 1250.0, 3: 156.0, 4: 39.0,
      5: 4.9, 6: 1.22, 7: 0.153, 8: 0.0382, 9: 0.00477,
    };
    final cellWidthKm = cellWidthByPrecision[precision] ?? 5.0;

    // Quanti ring servono per coprire 'radiusKm'. 1-ring → ~1.5×cell,
    // 2-ring → ~2.5×cell. Margine 30%.
    final ringCount = (radiusKm / cellWidthKm * 1.3).ceil().clamp(1, 4);

    final centerHash = GeoHashUtil.encode(lat, lng, precision: precision);
    final centerBounds = GeoHashUtil.decodeBounds(centerHash);
    final cellLatSize = centerBounds.maxLat - centerBounds.minLat;
    final cellLngSize = centerBounds.maxLng - centerBounds.minLng;

    final hashes = <String>{};
    for (int dy = -ringCount; dy <= ringCount; dy++) {
      for (int dx = -ringCount; dx <= ringCount; dx++) {
        final neighborLat = centerBounds.latitude + dy * cellLatSize;
        final neighborLng = centerBounds.longitude + dx * cellLngSize;
        // Skip se fuori dal range valido di coordinate.
        if (neighborLat < -90 || neighborLat > 90) continue;
        // Wrap longitudine
        var wrappedLng = neighborLng;
        while (wrappedLng > 180) {
          wrappedLng -= 360;
        }
        while (wrappedLng < -180) {
          wrappedLng += 360;
        }
        hashes.add(GeoHashUtil.encode(
            neighborLat, wrappedLng, precision: precision));
      }
    }

    // Raggruppa per prefix(precision-1) per minimizzare query.
    final prefixMap = <String, List<String>>{};
    for (final h in hashes) {
      final p = h.substring(0, math.min(precision - 1, h.length));
      prefixMap.putIfAbsent(p, () => []).add(h);
    }
    final ranges = prefixMap.entries.map((e) {
      final sorted = e.value..sort();
      return (start: sorted.first, end: '${sorted.last}~');
    }).toList();

    debugPrint('[getNearby] center=($lat,$lng) radius=${radiusKm}km '
        'precision=$precision centerHash=$centerHash '
        'hashes=${hashes.length} ranges=${ranges.length} '
        'rangesList=${ranges.map((r) => "${r.start}-${r.end}").toList()}');

    // Esegue tante query quante sono le ranges (max 9), aggrega.
    final all = <String, Business>{};
    for (final range in ranges) {
      Query<Map<String, dynamic>> q = _businesses
          .where('status', isEqualTo: 'active')
          .where('location.geohash',
              isGreaterThanOrEqualTo: range.start)
          .where('location.geohash', isLessThan: range.end)
          .limit(limit);
      if (type != null) {
        q = q.where('type', isEqualTo: type.name);
      }
      final snap = await q.get();
      debugPrint('[getNearby] range ${range.start}-${range.end}: '
          '${snap.docs.length} docs');
      for (final d in snap.docs) {
        all[d.id] = Business.fromMap(d.id, d.data());
      }
    }
    debugPrint('[getNearby] total raw before haversine filter: ${all.length}');

    // Filtro radius preciso lato client (Haversine)
    final filtered = all.values.where((b) {
      final d = _haversineKm(lat, lng, b.location.lat, b.location.lng);
      return d <= radiusKm;
    }).toList();

    filtered.sort((a, b) {
      final da = _haversineKm(lat, lng, a.location.lat, a.location.lng);
      final db = _haversineKm(lat, lng, b.location.lat, b.location.lng);
      return da.compareTo(db);
    });

    return filtered.take(limit).toList();
  }

  /// Spazi Pro vicini a una polyline (percorso di una traccia).
  ///
  /// Usato per la sezione "Spazi lungo il percorso" sulle detail
  /// tracce: permette al fruitore di un trail di scoprire rifugi /
  /// bivacchi / Spazi Pro che si trovano lungo il tragitto.
  ///
  /// Implementazione: campiona la polyline ogni [sampleEveryKm] km
  /// (default 5 km), per ogni punto fa getNearby() con
  /// radius = [radiusKm], aggrega i risultati deduplicando per id.
  /// Il risultato è ordinato per "posizione lungo il percorso" (km
  /// progressivi dal primo vertice).
  ///
  /// Trade-off: con polyline di 30 km e sample ogni 5 km parte 6+
  /// query geohash (max 9 ranges l'una). Per polyline corte
  /// (< 5 km) prende solo i due estremi.
  Future<List<NearPolylineBusiness>> getNearPolyline(
    List<({double lat, double lng})> polyline, {
    double radiusKm = 2,
    double sampleEveryKm = 5,
    int limitPerSample = 50,
  }) async {
    if (polyline.length < 2) return const [];

    // Calcola distanza cumulativa e campiona ogni sampleEveryKm.
    final cumulative = <double>[0];
    for (int i = 1; i < polyline.length; i++) {
      final d = _haversineKm(
        polyline[i - 1].lat,
        polyline[i - 1].lng,
        polyline[i].lat,
        polyline[i].lng,
      );
      cumulative.add(cumulative.last + d);
    }
    final total = cumulative.last;

    // Sample indices: sempre primo + ultimo + N intermedi.
    final sampleIdx = <int>{0, polyline.length - 1};
    if (total > sampleEveryKm) {
      double target = sampleEveryKm;
      int j = 0;
      while (target < total) {
        while (j < cumulative.length - 1 && cumulative[j] < target) {
          j++;
        }
        sampleIdx.add(j);
        target += sampleEveryKm;
      }
    }

    final results = <String, _PendingBusiness>{};
    for (final i in sampleIdx) {
      final p = polyline[i];
      final near = await getNearby(
        lat: p.lat,
        lng: p.lng,
        radiusKm: radiusKm,
        limit: limitPerSample,
      );
      for (final b in near) {
        // Salva il km del sample più vicino a questo business
        final kmFromStart = cumulative[i];
        final existing = results[b.id];
        if (existing == null || kmFromStart < existing.kmFromStart) {
          // Distanza precisa punto-business (non sample center)
          final distM = _haversineKm(
                p.lat,
                p.lng,
                b.location.lat,
                b.location.lng,
              ) *
              1000;
          results[b.id!] = _PendingBusiness(
            business: b,
            kmFromStart: kmFromStart,
            distanceFromPathMeters: distM,
          );
        }
      }
    }

    final list = results.values
        .map((p) => NearPolylineBusiness(
              business: p.business,
              kmFromStart: p.kmFromStart,
              distanceFromPathMeters: p.distanceFromPathMeters,
            ))
        .toList()
      ..sort((a, b) => a.kmFromStart.compareTo(b.kmFromStart));

    return list;
  }

  /// Tutti gli Spazi Pro attivi (nazionale). Usato dalla discovery
  /// page quando l'utente passa al modo "Tutta Italia" per planning
  /// viaggio. Niente filtro geohash, solo status=active + optional type.
  ///
  /// [limit] default 2000: copre tutti i rifugi italiani da OSM
  /// (~2200 alpine_hut + noleggi/guide ~500 = ~2700). Sopra il limit
  /// la mappa nationwide è incompleta. Quando supereremo 3000 doc,
  /// paginiamo o spostiamo lato Cloud Function (aggregato precomputato).
  Future<List<Business>> getAllNationwide({
    BusinessType? type,
    int limit = 2000,
  }) async {
    Query<Map<String, dynamic>> q = _businesses
        .where('status', isEqualTo: 'active')
        .limit(limit);
    if (type != null) {
      q = q.where('type', isEqualTo: type.name);
    }
    final snap = await q.get();
    return snap.docs.map((d) => Business.fromMap(d.id, d.data())).toList();
  }

  /// Lista businesses dove l'utente corrente è owner.
  Future<List<Business>> getMyBusinesses() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _businesses
        .where('ownerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => Business.fromMap(d.id, d.data())).toList();
  }

  Stream<List<Business>> watchMyBusinesses() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);
    // NB: niente orderBy server-side per evitare di richiedere un indice
    // composito. Volumi attesi minimi (1-3 businesses per owner), ordino
    // client-side.
    return _businesses
        .where('ownerId', isEqualTo: uid)
        .snapshots()
        .map((s) {
      final list =
          s.docs.map((d) => Business.fromMap(d.id, d.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOLLOW
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> isFollowing(String businessId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _businesses
        .doc(businessId)
        .collection('followers')
        .doc(uid)
        .get();
    return doc.exists;
  }

  Stream<bool> watchIsFollowing(String businessId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _businesses
        .doc(businessId)
        .collection('followers')
        .doc(uid)
        .snapshots()
        .map((s) => s.exists);
  }

  Future<void> follow(String businessId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Non autenticato');
    final ref = _businesses.doc(businessId).collection('followers').doc(uid);
    await _db.runTransaction((tx) async {
      final exists = await tx.get(ref);
      if (exists.exists) return;
      tx.set(ref, {'followedAt': Timestamp.now()});
      tx.update(_businesses.doc(businessId), {
        'followerCount': FieldValue.increment(1),
      });
    });
  }

  Future<void> unfollow(String businessId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Non autenticato');
    final ref = _businesses.doc(businessId).collection('followers').doc(uid);
    await _db.runTransaction((tx) async {
      final exists = await tx.get(ref);
      if (!exists.exists) return;
      tx.delete(ref);
      tx.update(_businesses.doc(businessId), {
        'followerCount': FieldValue.increment(-1),
      });
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POSTS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> createPost({
    required String businessId,
    required String text,
    List<String> photoUrls = const [],
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Non autenticato');
    final post = BusinessPost(
      businessId: businessId,
      authorId: uid,
      text: text,
      photoUrls: photoUrls,
      createdAt: DateTime.now(),
    );
    final batch = _db.batch();
    final postRef =
        _businesses.doc(businessId).collection('posts').doc();
    batch.set(postRef, post.toMap());
    batch.update(_businesses.doc(businessId), {
      'postsCount': FieldValue.increment(1),
      'updatedAt': Timestamp.now(),
    });
    await batch.commit();
    return postRef.id;
  }

  Stream<List<BusinessPost>> watchPosts(String businessId, {int limit = 50}) {
    return _businesses
        .doc(businessId)
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => BusinessPost.fromMap(d.id, d.data()))
            .toList());
  }

  Future<void> deletePost(String businessId, String postId) async {
    final batch = _db.batch();
    batch.delete(
        _businesses.doc(businessId).collection('posts').doc(postId));
    batch.update(_businesses.doc(businessId), {
      'postsCount': FieldValue.increment(-1),
    });
    await batch.commit();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERVICES (listino)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> createService(
      String businessId, BusinessService service) async {
    final ref = await _businesses
        .doc(businessId)
        .collection('services')
        .add(service.toMap());
    return ref.id;
  }

  Future<void> updateService(
      String businessId, String serviceId, Map<String, dynamic> patch) async {
    await _businesses
        .doc(businessId)
        .collection('services')
        .doc(serviceId)
        .update(patch);
  }

  Future<void> deleteService(String businessId, String serviceId) async {
    await _businesses
        .doc(businessId)
        .collection('services')
        .doc(serviceId)
        .delete();
  }

  Stream<List<BusinessService>> watchServices(String businessId) {
    return _businesses
        .doc(businessId)
        .collection('services')
        .orderBy('order')
        .snapshots()
        .map((s) => s.docs
            .map((d) => BusinessService.fromMap(d.id, d.data()))
            .toList());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYTICS (profile views, contact clicks; aggregati totali + daily)
  // ═══════════════════════════════════════════════════════════════════════════

  String _todayKey() {
    final now = DateTime.now().toUtc();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// Tracking visita profilo: incrementa atomicamente totals + daily.
  /// Best-effort: errori vengono loggati ma non rilanciati (no UX impact).
  Future<void> recordProfileView(String businessId) async {
    try {
      final batch = _db.batch();
      batch.set(
        _businesses.doc(businessId).collection('analytics').doc('totals'),
        {
          'profileViews': FieldValue.increment(1),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      batch.set(
        _businesses
            .doc(businessId)
            .collection('analytics_daily')
            .doc(_todayKey()),
        {
          'profileViews': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (e) {
      debugPrint('[BusinessRepo] recordProfileView error: $e');
    }
  }

  /// Tracking tap su contatto/direzioni: incrementa per tipo.
  Future<void> recordContactClick(
      String businessId, BusinessContactType type) async {
    try {
      final batch = _db.batch();
      batch.set(
        _businesses.doc(businessId).collection('analytics').doc('totals'),
        {
          type.totalsField: FieldValue.increment(1),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      batch.set(
        _businesses
            .doc(businessId)
            .collection('analytics_daily')
            .doc(_todayKey()),
        {
          'contactClicks': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (e) {
      debugPrint('[BusinessRepo] recordContactClick error: $e');
    }
  }

  Stream<BusinessAnalyticsTotals> watchAnalyticsTotals(String businessId) {
    return _businesses
        .doc(businessId)
        .collection('analytics')
        .doc('totals')
        .snapshots()
        .map((s) => s.exists
            ? BusinessAnalyticsTotals.fromMap(s.data()!)
            : const BusinessAnalyticsTotals());
  }

  /// Daily breakdown per gli ultimi [days] giorni (default 14).
  /// Restituisce sempre un array di [days] elementi (zero-fill se manca).
  Future<List<BusinessAnalyticsDay>> getAnalyticsDaily(
    String businessId, {
    int days = 14,
  }) async {
    final now = DateTime.now().toUtc();
    final dates = <String>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final m = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      dates.add('${d.year}-$m-$dd');
    }
    final coll =
        _businesses.doc(businessId).collection('analytics_daily');
    final out = <BusinessAnalyticsDay>[];
    for (final dateKey in dates) {
      try {
        final snap = await coll.doc(dateKey).get();
        out.add(snap.exists
            ? BusinessAnalyticsDay.fromMap(dateKey, snap.data()!)
            : BusinessAnalyticsDay(dateKey: dateKey));
      } catch (e) {
        out.add(BusinessAnalyticsDay(dateKey: dateKey));
      }
    }
    return out;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REVIEWS (recensioni con rating aggregato transactional)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stream delle recensioni di un business, ordinate per data desc.
  Stream<List<BusinessReview>> watchReviews(String businessId,
      {int limit = 100}) {
    return _businesses
        .doc(businessId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => BusinessReview.fromMap(d.id, d.data()))
            .toList());
  }

  /// Recupera la review dell'utente corrente per il business (o null).
  Future<BusinessReview?> getMyReview(String businessId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _businesses
        .doc(businessId)
        .collection('reviews')
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    return BusinessReview.fromMap(doc.id, doc.data()!);
  }

  /// Crea/aggiorna review (idempotente: doc ID = userId, 1 review/utente).
  /// Aggiorna atomically `rating` e `reviewCount` sul business doc.
  Future<void> upsertReview({
    required String businessId,
    required int rating,
    String? comment,
    required String userDisplayName,
    String? userAvatarUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Non autenticato');
    if (rating < 1 || rating > 5) {
      throw ArgumentError('Rating deve essere 1-5');
    }
    final reviewRef =
        _businesses.doc(businessId).collection('reviews').doc(uid);
    final businessRef = _businesses.doc(businessId);

    await _db.runTransaction((tx) async {
      final bizSnap = await tx.get(businessRef);
      final existingReview = await tx.get(reviewRef);

      final oldCount =
          (bizSnap.data()?['reviewCount'] as num?)?.toInt() ?? 0;
      final oldAvg =
          (bizSnap.data()?['rating'] as num?)?.toDouble() ?? 0;

      int newCount;
      double newAvg;

      if (existingReview.exists) {
        // Update: sostituisci old rating con new
        final oldRating =
            (existingReview.data()?['rating'] as num?)?.toInt() ?? 0;
        newCount = oldCount;
        if (newCount == 0) {
          newAvg = rating.toDouble();
        } else {
          newAvg = oldAvg + (rating - oldRating) / newCount;
        }
      } else {
        // Create: incrementa count + ricalcola
        newCount = oldCount + 1;
        newAvg = (oldAvg * oldCount + rating) / newCount;
      }

      final review = BusinessReview(
        userId: uid,
        rating: rating,
        comment: comment,
        createdAt: existingReview.exists
            ? ((existingReview.data()?['createdAt'] as Timestamp?)
                    ?.toDate() ??
                DateTime.now())
            : DateTime.now(),
        editedAt: existingReview.exists ? DateTime.now() : null,
        userDisplayName: userDisplayName,
        userAvatarUrl: userAvatarUrl,
      );
      tx.set(reviewRef, review.toMap());
      tx.update(businessRef, {
        'reviewCount': newCount,
        'rating': double.parse(newAvg.toStringAsFixed(2)),
      });
    });
    debugPrint(
        '[BusinessRepo] Review upserted business=$businessId user=$uid rating=$rating');
  }

  /// Elimina la review dell'utente. Aggiorna aggregati transactional.
  Future<void> deleteReview(String businessId, String userId) async {
    final reviewRef =
        _businesses.doc(businessId).collection('reviews').doc(userId);
    final businessRef = _businesses.doc(businessId);

    await _db.runTransaction((tx) async {
      final bizSnap = await tx.get(businessRef);
      final reviewSnap = await tx.get(reviewRef);
      if (!reviewSnap.exists) return;

      final oldCount =
          (bizSnap.data()?['reviewCount'] as num?)?.toInt() ?? 0;
      final oldAvg =
          (bizSnap.data()?['rating'] as num?)?.toDouble() ?? 0;
      final deletedRating =
          (reviewSnap.data()?['rating'] as num?)?.toInt() ?? 0;

      final newCount = (oldCount - 1).clamp(0, double.maxFinite.toInt());
      final newAvg = newCount == 0
          ? 0.0
          : (oldAvg * oldCount - deletedRating) / newCount;

      tx.delete(reviewRef);
      tx.update(businessRef, {
        'reviewCount': newCount,
        'rating': double.parse(newAvg.toStringAsFixed(2)),
      });
    });
    debugPrint(
        '[BusinessRepo] Review deleted business=$businessId user=$userId');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECOMMENDED TRACKS (percorsi consigliati)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Aggiunge una traccia ai consigliati. Idempotente: doc ID = trackId.
  /// Se già presente, sovrascrive la nota.
  Future<void> addRecommendedTrack(
    String businessId,
    RecommendedTrack rec,
  ) async {
    final ref = _businesses
        .doc(businessId)
        .collection('recommended_tracks')
        .doc(rec.trackId);
    await ref.set(rec.toMap());
  }

  Future<void> removeRecommendedTrack(
    String businessId,
    String trackId,
  ) async {
    await _businesses
        .doc(businessId)
        .collection('recommended_tracks')
        .doc(trackId)
        .delete();
  }

  Future<void> updateRecommendedTrackNote(
    String businessId,
    String trackId,
    String? note,
  ) async {
    await _businesses
        .doc(businessId)
        .collection('recommended_tracks')
        .doc(trackId)
        .update({
      'note': note ?? FieldValue.delete(),
    });
  }

  /// Riordina i consigliati impostando il campo `order` in batch.
  Future<void> reorderRecommendedTracks(
    String businessId,
    List<String> trackIdsInOrder,
  ) async {
    final batch = _db.batch();
    for (var i = 0; i < trackIdsInOrder.length; i++) {
      final ref = _businesses
          .doc(businessId)
          .collection('recommended_tracks')
          .doc(trackIdsInOrder[i]);
      batch.update(ref, {'order': i});
    }
    await batch.commit();
  }

  Stream<List<RecommendedTrack>> watchRecommendedTracks(String businessId) {
    return _businesses
        .doc(businessId)
        .collection('recommended_tracks')
        .orderBy('order')
        .snapshots()
        .map((s) => s.docs
            .map((d) => RecommendedTrack.fromMap(d.id, d.data()))
            .toList());
  }

  Future<List<RecommendedTrack>> getRecommendedTracks(String businessId) async {
    final snap = await _businesses
        .doc(businessId)
        .collection('recommended_tracks')
        .orderBy('order')
        .get();
    return snap.docs
        .map((d) => RecommendedTrack.fromMap(d.id, d.data()))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _generateUniqueSlug(String name) async {
    final base = _slugify(name);
    String candidate = base;
    int suffix = 1;
    while (true) {
      final exists = await _businesses
          .where('slug', isEqualTo: candidate)
          .limit(1)
          .get();
      if (exists.docs.isEmpty) return candidate;
      suffix++;
      candidate = '$base-$suffix';
      if (suffix > 100) {
        // Safety net: aggiungi timestamp se troppo affollato
        return '$base-${DateTime.now().millisecondsSinceEpoch}';
      }
    }
  }

  String _slugify(String input) {
    final lower = input.toLowerCase().trim();
    final replaced = lower
        .replaceAll(RegExp(r'[àáâãä]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r"[^a-z0-9\s-]"), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final trimmed = replaced.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'spazio' : trimmed;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);
}

/// Risultato di [BusinessRepository.getNearPolyline]: ogni Business
/// con info di posizione lungo il percorso.
class NearPolylineBusiness {
  final Business business;

  /// Distanza progressiva dall'inizio della polyline al punto del
  /// percorso più vicino allo spazio (km).
  final double kmFromStart;

  /// Distanza puntuale tra il business e il percorso (metri).
  final double distanceFromPathMeters;

  const NearPolylineBusiness({
    required this.business,
    required this.kmFromStart,
    required this.distanceFromPathMeters,
  });
}

/// Helper interno per scegliere il sample più vicino in caso di
/// match multipli del business.
class _PendingBusiness {
  final Business business;
  final double kmFromStart;
  final double distanceFromPathMeters;
  const _PendingBusiness({
    required this.business,
    required this.kmFromStart,
    required this.distanceFromPathMeters,
  });
}
