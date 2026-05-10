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
    int limit = 100,
  }) async {
    final precision = GeoHashUtil.precisionForRadius(radiusKm);
    // Bounding box approssimato dal raggio (1° lat ≈ 111km).
    final dLat = radiusKm / 111.0;
    final dLng = radiusKm / (111.0 * math.cos(_deg2rad(lat)).abs() + 0.0001);
    final ranges = GeoHashUtil.getQueryRanges(
      minLat: lat - dLat,
      maxLat: lat + dLat,
      minLng: lng - dLng,
      maxLng: lng + dLng,
      precision: precision,
    );

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
      for (final d in snap.docs) {
        all[d.id] = Business.fromMap(d.id, d.data());
      }
    }

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
