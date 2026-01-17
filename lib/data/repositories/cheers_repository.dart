import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository per gestire i "cheers" (like) sulle tracce pubblicate
class CheersRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Verifica se l'utente corrente ha messo cheer a una traccia
  Future<bool> hasUserCheered(String trackId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final cheerDoc = await _firestore
          .collection('published_tracks')
          .doc(trackId)
          .collection('cheers')
          .doc(user.uid)
          .get();

      return cheerDoc.exists;
    } catch (e) {
      print('[CheersRepository] Errore hasUserCheered: $e');
      return false;
    }
  }

  /// Ottiene il conteggio cheers per una traccia
  Future<int> getCheersCount(String trackId) async {
    try {
      final cheersSnapshot = await _firestore
          .collection('published_tracks')
          .doc(trackId)
          .collection('cheers')
          .count()
          .get();

      return cheersSnapshot.count ?? 0;
    } catch (e) {
      print('[CheersRepository] Errore getCheersCount: $e');
      return 0;
    }
  }

  /// Ottiene stato cheer e conteggio insieme (più efficiente)
  Future<CheerStatus> getCheerStatus(String trackId) async {
    final user = FirebaseAuth.instance.currentUser;
    
    try {
      // Conteggio
      final countFuture = _firestore
          .collection('published_tracks')
          .doc(trackId)
          .collection('cheers')
          .count()
          .get();

      // Stato utente (se loggato)
      Future<bool> hasUserCheeredFuture = Future.value(false);
      if (user != null) {
        hasUserCheeredFuture = _firestore
            .collection('published_tracks')
            .doc(trackId)
            .collection('cheers')
            .doc(user.uid)
            .get()
            .then((doc) => doc.exists);
      }

      final results = await Future.wait([countFuture, hasUserCheeredFuture]);
      final count = (results[0] as AggregateQuerySnapshot).count ?? 0;
      final hasCheered = results[1] as bool;

      return CheerStatus(count: count, hasCheered: hasCheered);
    } catch (e) {
      print('[CheersRepository] Errore getCheerStatus: $e');
      return CheerStatus(count: 0, hasCheered: false);
    }
  }

  /// Toggle cheer (like/unlike)
  /// Ritorna il nuovo stato
  Future<CheerResult> toggleCheer(String trackId) async {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return CheerResult(
        success: false,
        error: 'Devi effettuare il login per mettere like',
      );
    }

    // Verifica email (opzionale, decommentare se richiesto)
    // if (!user.emailVerified) {
    //   return CheerResult(
    //     success: false,
    //     error: 'Verifica la tua email per poter mettere like',
    //   );
    // }

    try {
      final cheerRef = _firestore
          .collection('published_tracks')
          .doc(trackId)
          .collection('cheers')
          .doc(user.uid);

      final cheerDoc = await cheerRef.get();

      if (cheerDoc.exists) {
        // Rimuovi cheer (unlike)
        await cheerRef.delete();
        
        // Aggiorna contatore sulla traccia (opzionale, per query veloci)
        await _updateCheerCount(trackId, -1);
        
        return CheerResult(
          success: true,
          isNowCheered: false,
        );
      } else {
        // Aggiungi cheer (like)
        await cheerRef.set({
          'userId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        // Aggiorna contatore sulla traccia
        await _updateCheerCount(trackId, 1);
        
        return CheerResult(
          success: true,
          isNowCheered: true,
        );
      }
    } catch (e) {
      print('[CheersRepository] Errore toggleCheer: $e');
      return CheerResult(
        success: false,
        error: 'Errore durante l\'operazione. Riprova.',
      );
    }
  }

  /// Aggiorna il contatore cheers sulla traccia pubblicata
  Future<void> _updateCheerCount(String trackId, int delta) async {
    try {
      await _firestore
          .collection('published_tracks')
          .doc(trackId)
          .update({
        'cheersCount': FieldValue.increment(delta),
      });
    } catch (e) {
      // Non critico se fallisce, il conteggio può essere ricalcolato
      print('[CheersRepository] Errore aggiornamento contatore: $e');
    }
  }

  /// Stream per ascoltare cambiamenti in real-time
  Stream<CheerStatus> watchCheerStatus(String trackId) {
    final user = FirebaseAuth.instance.currentUser;

    return _firestore
        .collection('published_tracks')
        .doc(trackId)
        .collection('cheers')
        .snapshots()
        .map((snapshot) {
      final count = snapshot.docs.length;
      final hasCheered = user != null && 
          snapshot.docs.any((doc) => doc.id == user.uid);
      
      return CheerStatus(count: count, hasCheered: hasCheered);
    });
  }
}

/// Stato del cheer per una traccia
class CheerStatus {
  final int count;
  final bool hasCheered;

  const CheerStatus({
    required this.count,
    required this.hasCheered,
  });
}

/// Risultato dell'operazione toggle cheer
class CheerResult {
  final bool success;
  final bool? isNowCheered;
  final String? error;

  const CheerResult({
    required this.success,
    this.isNowCheered,
    this.error,
  });
}
