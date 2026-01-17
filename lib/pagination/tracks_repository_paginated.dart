// ═══════════════════════════════════════════════════════════════════════════
// FIX MEMORIA: TracksRepository con Paginazione
// File: lib/data/repositories/tracks_repository.dart
// ═══════════════════════════════════════════════════════════════════════════
//
// Aggiungi questi metodi al TracksRepository esistente
// 

import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════════════════════
// METODO 1: getUserTracks con paginazione
// Sostituisci il metodo esistente con questo:
// ═══════════════════════════════════════════════════════════════════════════

  /// Ottiene le tracce dell'utente con paginazione
  /// [limit] - Numero di tracce per pagina (default 10)
  /// [lastDocument] - Ultimo documento della pagina precedente (per paginazione)
  Future<TracksPage> getUserTracksPaginated(
    String userId, {
    int limit = 10,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _tracksCollection(userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      // Se c'è un documento precedente, parti da lì
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snapshot = await query.get();
      
      final tracks = snapshot.docs
          .map((doc) => _trackFromFirestore(doc.id, doc.data()))
          .toList();

      print('[TracksRepository] Caricate ${tracks.length} tracce (pagina)');

      return TracksPage(
        tracks: tracks,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length >= limit,
      );
    } catch (e) {
      print('[TracksRepository] Errore getUserTracksPaginated: $e');
      return TracksPage(tracks: [], lastDocument: null, hasMore: false);
    }
  }

  /// Versione originale con limite fisso (per retrocompatibilità)
  Future<List<Track>> getUserTracks(String userId) async {
    try {
      final snapshot = await _tracksCollection(userId)
          .orderBy('createdAt', descending: true)
          .limit(20) // FIX: Aggiunto limite!
          .get();

      print('[TracksRepository] Trovate ${snapshot.docs.length} tracce per utente $userId');

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return _trackFromFirestore(doc.id, data);
      }).toList();
    } catch (e) {
      print('[TracksRepository] Errore getUserTracks: $e');
      return [];
    }
  }


// ═══════════════════════════════════════════════════════════════════════════
// CLASSE HELPER: TracksPage
// Aggiungi questa classe alla fine del file (o in un file separato)
// ═══════════════════════════════════════════════════════════════════════════

/// Risultato paginato delle tracce
class TracksPage {
  final List<Track> tracks;
  final DocumentSnapshot? lastDocument;
  final bool hasMore;

  const TracksPage({
    required this.tracks,
    this.lastDocument,
    required this.hasMore,
  });
}
