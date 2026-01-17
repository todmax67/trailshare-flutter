import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository per gestire la wishlist (percorsi da fare)
class WishlistRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Verifica se una traccia è nella wishlist dell'utente
  Future<bool> isInWishlist(String trackId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();

      if (!profileDoc.exists) return false;

      final wishlist = List<String>.from(profileDoc.data()?['wishlist'] ?? []);
      return wishlist.contains(trackId);
    } catch (e) {
      print('[WishlistRepository] Errore isInWishlist: $e');
      return false;
    }
  }

  /// Ottiene la lista completa dei trackId nella wishlist
  Future<List<String>> getWishlistIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();

      if (!profileDoc.exists) return [];

      return List<String>.from(profileDoc.data()?['wishlist'] ?? []);
    } catch (e) {
      print('[WishlistRepository] Errore getWishlistIds: $e');
      return [];
    }
  }

  /// Toggle wishlist (aggiungi/rimuovi)
  Future<WishlistResult> toggleWishlist(String trackId) async {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return WishlistResult(
        success: false,
        error: 'Devi effettuare il login per salvare i percorsi',
      );
    }

    try {
      final profileRef = _firestore.collection('user_profiles').doc(user.uid);
      final profileDoc = await profileRef.get();
      
      final wishlist = List<String>.from(profileDoc.data()?['wishlist'] ?? []);
      final isCurrentlyInWishlist = wishlist.contains(trackId);

      if (isCurrentlyInWishlist) {
        // Rimuovi
        await profileRef.update({
          'wishlist': FieldValue.arrayRemove([trackId]),
        });
        return WishlistResult(
          success: true,
          isNowInWishlist: false,
          message: 'Rimosso dai percorsi da fare',
        );
      } else {
        // Aggiungi (usa set con merge per creare il documento se non esiste)
        await profileRef.set({
          'wishlist': FieldValue.arrayUnion([trackId]),
        }, SetOptions(merge: true));
        return WishlistResult(
          success: true,
          isNowInWishlist: true,
          message: 'Aggiunto ai percorsi da fare!',
        );
      }
    } catch (e) {
      print('[WishlistRepository] Errore toggleWishlist: $e');
      return WishlistResult(
        success: false,
        error: 'Operazione non riuscita. Riprova.',
      );
    }
  }

  /// Aggiungi alla wishlist
  Future<bool> addToWishlist(String trackId) async {
    final result = await toggleWishlist(trackId);
    return result.success && (result.isNowInWishlist ?? false);
  }

  /// Rimuovi dalla wishlist
  Future<bool> removeFromWishlist(String trackId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      await _firestore.collection('user_profiles').doc(user.uid).update({
        'wishlist': FieldValue.arrayRemove([trackId]),
      });
      return true;
    } catch (e) {
      print('[WishlistRepository] Errore removeFromWishlist: $e');
      return false;
    }
  }

  /// Stream per ascoltare cambiamenti alla wishlist
  Stream<List<String>> watchWishlist() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('user_profiles')
        .doc(user.uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return <String>[];
      return List<String>.from(doc.data()?['wishlist'] ?? []);
    });
  }

  /// Conta elementi nella wishlist
  Future<int> getWishlistCount() async {
    final ids = await getWishlistIds();
    return ids.length;
  }
}

/// Risultato operazione wishlist
class WishlistResult {
  final bool success;
  final bool? isNowInWishlist;
  final String? message;
  final String? error;

  const WishlistResult({
    required this.success,
    this.isNowInWishlist,
    this.message,
    this.error,
  });
}
