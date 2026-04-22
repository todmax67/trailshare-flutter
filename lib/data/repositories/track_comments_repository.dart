import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/track_comment.dart';

/// CRUD per i [TrackComment] su una traccia community.
class TrackCommentsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String trackId) =>
      _firestore.collection('published_tracks').doc(trackId).collection('comments');

  /// Stream real-time dei commenti (ordine cronologico, piu' recenti prima).
  /// Usato dalla UI per aggiornamento live quando un utente commenta.
  Stream<List<TrackComment>> watchComments(String trackId, {int limit = 50}) {
    return _col(trackId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TrackComment.fromFirestore(d.id, d.data()))
            .toList());
  }

  Future<List<TrackComment>> getRecent(String trackId, {int limit = 50}) async {
    final snap = await _col(trackId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => TrackComment.fromFirestore(d.id, d.data()))
        .toList();
  }

  /// Conteggio totale dei commenti su una traccia. Usato per il badge
  /// "N commenti" nella card community.
  Future<int> countComments(String trackId) async {
    try {
      final snap = await _col(trackId).count().get();
      return snap.count ?? 0;
    } catch (e) {
      debugPrint('[TrackComments] count error: $e');
      return 0;
    }
  }

  /// Aggiunge un commento. Richiede utente autenticato.
  /// Denormalizza `username` e `avatarUrl` dal profilo.
  Future<TrackComment?> addComment({
    required String trackId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Username + avatar dal profilo utente, con fallback graceful.
    String username = user.displayName ?? user.email?.split('@').first ?? 'Utente';
    String? avatarUrl = user.photoURL;
    try {
      final prof = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();
      if (prof.exists && prof.data() != null) {
        username = prof.data()!['username']?.toString() ?? username;
        final a = prof.data()!['avatarUrl']?.toString();
        if (a != null && a.isNotEmpty) avatarUrl = a;
      }
    } catch (_) {
      // profilo non obbligatorio; procediamo con i fallback.
    }

    final docRef = _col(trackId).doc();
    final now = DateTime.now();
    final comment = TrackComment(
      id: docRef.id,
      userId: user.uid,
      username: username,
      avatarUrl: avatarUrl,
      text: trimmed,
      createdAt: now,
    );
    await docRef.set(comment.toFirestore());
    debugPrint('[TrackComments] commento aggiunto su $trackId da $username');
    return comment;
  }

  /// Cancella un commento. Permessi gestiti lato regole Firestore:
  /// - autore del commento (userId == auth.uid)
  /// - autore della traccia (originalOwnerId della track)
  /// - admin
  Future<bool> deleteComment({
    required String trackId,
    required String commentId,
  }) async {
    try {
      await _col(trackId).doc(commentId).delete();
      return true;
    } catch (e) {
      debugPrint('[TrackComments] delete error: $e');
      return false;
    }
  }
}
