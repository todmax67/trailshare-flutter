import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/trail_review.dart';

/// Repository per gestire recensioni e rating dei sentieri pubblici.
///
/// Firestore schema:
/// ```
/// /trail_reviews/{trailId}/items/{userId}
/// ```
class ReviewsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _itemsCollection(String trailId) =>
      _firestore.collection('trail_reviews').doc(trailId).collection('items');

  /// Carica tutte le recensioni di un sentiero, ordinate dalla più recente.
  Future<List<TrailReview>> getReviewsForTrail(String trailId) async {
    try {
      final snapshot = await _itemsCollection(trailId)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((d) => TrailReview.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint('[Reviews] Errore caricamento recensioni: $e');
      return [];
    }
  }

  /// Recensione dell'utente corrente su un sentiero (o null).
  Future<TrailReview?> getUserReview(String trailId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final doc = await _itemsCollection(trailId).doc(uid).get();
      if (!doc.exists) return null;
      return TrailReview.fromFirestore(doc);
    } catch (e) {
      debugPrint('[Reviews] Errore caricamento recensione utente: $e');
      return null;
    }
  }

  /// Crea o aggiorna la recensione dell'utente corrente.
  Future<ReviewResult> saveReview({
    required String trailId,
    required int rating,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return ReviewResult.fail('Devi effettuare il login per lasciare una recensione');
    }
    if (rating < 1 || rating > 5) {
      return ReviewResult.fail('Rating non valido');
    }

    try {
      // Recupera username e avatar dal profilo utente per denormalizzazione
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();
      final profileData = profileDoc.data() ?? {};
      final username = (profileData['username'] as String?) ??
          user.displayName ??
          user.email?.split('@').first ??
          'Utente';
      final avatarUrl = (profileData['avatarUrl'] as String?) ?? user.photoURL;

      final docRef = _itemsCollection(trailId).doc(user.uid);
      final existing = await docRef.get();

      final review = TrailReview(
        userId: user.uid,
        username: username,
        avatarUrl: avatarUrl,
        rating: rating,
        text: text.trim(),
        createdAt: DateTime.now(),
      );

      if (existing.exists) {
        await docRef.update(review.toFirestoreUpdate());
      } else {
        await docRef.set(review.toFirestoreCreate());
      }

      debugPrint('[Reviews] Recensione salvata per trail $trailId');
      return ReviewResult.ok(review);
    } catch (e) {
      debugPrint('[Reviews] Errore salvataggio: $e');
      return ReviewResult.fail('Errore durante il salvataggio');
    }
  }

  /// Elimina la recensione dell'utente corrente.
  Future<ReviewResult> deleteReview(String trailId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return ReviewResult.fail('Devi effettuare il login');
    }
    try {
      await _itemsCollection(trailId).doc(uid).delete();
      debugPrint('[Reviews] Recensione eliminata per trail $trailId');
      return ReviewResult.ok();
    } catch (e) {
      debugPrint('[Reviews] Errore eliminazione: $e');
      return ReviewResult.fail('Errore durante l\'eliminazione');
    }
  }

  /// Calcola la media dei rating da una lista di recensioni.
  static double computeAverage(List<TrailReview> reviews) {
    if (reviews.isEmpty) return 0;
    final sum = reviews.fold<int>(0, (acc, r) => acc + r.rating);
    return sum / reviews.length;
  }
}
