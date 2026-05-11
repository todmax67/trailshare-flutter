import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/mention_parser.dart';
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

    // Epic 3.6 — risolvi le menzioni @username → uid prima di salvare.
    // La mappa è denormalizzata sul commento per evitare query ai client
    // quando renderizzano gli span tappabili. La Cloud Function
    // `onCommentCreated` (futura) la userà per FCM ai menzionati.
    final mentions = await _resolveMentions(trimmed);

    final docRef = _col(trackId).doc();
    final now = DateTime.now();
    final comment = TrackComment(
      id: docRef.id,
      userId: user.uid,
      username: username,
      avatarUrl: avatarUrl,
      text: trimmed,
      createdAt: now,
      mentions: mentions,
    );
    await docRef.set(comment.toFirestore());
    debugPrint(
        '[TrackComments] commento aggiunto su $trackId da $username '
        '(mentions: ${mentions.length})');
    return comment;
  }

  /// Per ogni @username citato in [text] cerca l'uid corrispondente su
  /// `user_profiles` (lookup case-insensitive su `username` lowercase).
  /// Usernames non trovati vengono silenziosamente ignorati (resta il
  /// testo @username nel commento, senza tap-link).
  Future<Map<String, String>> _resolveMentions(String text) async {
    final usernames = MentionParser.extractUsernames(text);
    if (usernames.isEmpty) return const {};
    final Map<String, String> result = {};
    // Limitiamo a 10 lookup in parallelo per non sprecare query su un
    // commento con troppe menzioni (caso patologico, raro).
    final capped = usernames.take(10).toList();
    final futures = capped.map((uname) async {
      try {
        final snap = await _firestore
            .collection('user_profiles')
            .where('username', isEqualTo: uname)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          result[uname] = snap.docs.first.id;
        }
      } catch (e) {
        debugPrint('[TrackComments] mention lookup error for $uname: $e');
      }
    });
    await Future.wait(futures);
    return result;
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
