import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/trail_photo.dart';

/// Repository per gestire le foto community dei sentieri pubblici.
///
/// Firestore schema:
/// ```
/// /trail_photos/{trailId}/items/{photoId}
/// ```
///
/// Firebase Storage:
/// ```
/// trail_photos/{trailId}/{photoId}.jpg
/// ```
class TrailPhotosRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Cache statica in memoria delle prime foto per trail.
  /// `null` come valore significa "già cercato, nessuna foto presente".
  static final Map<String, String?> _firstPhotoCache = {};

  CollectionReference<Map<String, dynamic>> _itemsCollection(String trailId) =>
      _firestore.collection('trail_photos').doc(trailId).collection('items');

  /// Restituisce la URL della prima foto di un sentiero, o `null` se non esistono.
  /// Risultato cachato staticamente per tutta la sessione.
  Future<String?> getFirstPhotoUrl(String trailId) async {
    if (_firstPhotoCache.containsKey(trailId)) {
      return _firstPhotoCache[trailId];
    }
    try {
      // Niente orderBy: evitiamo l'esclusione di doc con serverTimestamp ancora pending
      final snapshot = await _itemsCollection(trailId).limit(1).get();
      final url = snapshot.docs.isEmpty
          ? null
          : (snapshot.docs.first.data()['photoUrl'] as String?);
      _firstPhotoCache[trailId] = url;
      return url;
    } catch (e) {
      debugPrint('[TrailPhotos] Errore getFirstPhotoUrl: $e');
      return null;
    }
  }

  /// Invalida la cache per un trail (dopo upload/delete per riflettere il cambio).
  static void invalidatePreviewCache(String trailId) {
    _firstPhotoCache.remove(trailId);
  }

  /// Carica tutte le foto di un sentiero, dalle più recenti.
  Future<List<TrailPhoto>> getPhotosForTrail(String trailId) async {
    try {
      final snapshot = await _itemsCollection(trailId)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((d) => TrailPhoto.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint('[TrailPhotos] Errore caricamento: $e');
      return [];
    }
  }

  /// Carica una foto per un sentiero.
  Future<PhotoUploadResult> uploadPhoto({
    required String trailId,
    required File file,
    String caption = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return PhotoUploadResult.fail('Devi effettuare il login per caricare foto');
    }

    try {
      // Genera photoId preventivamente per usarlo sia in Storage che Firestore
      final docRef = _itemsCollection(trailId).doc();
      final photoId = docRef.id;
      final storagePath = 'trail_photos/$trailId/$photoId.jpg';

      // Upload su Firebase Storage
      final ref = _storage.ref(storagePath);
      await ref.putFile(
        file,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'userId': user.uid,
            'trailId': trailId,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );
      final downloadUrl = await ref.getDownloadURL();

      // Recupera username/avatar denormalizzati dal profilo
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

      // Salva su Firestore
      final photo = TrailPhoto(
        photoId: photoId,
        trailId: trailId,
        userId: user.uid,
        username: username,
        avatarUrl: avatarUrl,
        photoUrl: downloadUrl,
        storagePath: storagePath,
        caption: caption.trim(),
        createdAt: DateTime.now(),
      );
      await docRef.set(photo.toFirestoreCreate());

      // Invalida la cache della preview per mostrare subito la nuova foto
      invalidatePreviewCache(trailId);

      debugPrint('[TrailPhotos] Upload ok per trail $trailId, id $photoId');
      return PhotoUploadResult.ok(photo);
    } catch (e) {
      debugPrint('[TrailPhotos] Errore upload: $e');
      return PhotoUploadResult.fail('Errore durante il caricamento');
    }
  }

  /// Elimina una foto (solo se l'utente corrente è l'autore).
  Future<PhotoUploadResult> deletePhoto(TrailPhoto photo) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return PhotoUploadResult.fail('Devi effettuare il login');
    }
    if (photo.userId != uid) {
      return PhotoUploadResult.fail('Non puoi eliminare le foto di altri utenti');
    }

    try {
      // Elimina doc Firestore
      await _itemsCollection(photo.trailId).doc(photo.photoId).delete();

      // Elimina file Storage (best effort)
      try {
        await _storage.ref(photo.storagePath).delete();
      } catch (e) {
        debugPrint('[TrailPhotos] Warning: delete storage fallito: $e');
      }

      // Invalida la cache preview così la prossima query rileva la nuova prima foto
      invalidatePreviewCache(photo.trailId);

      return PhotoUploadResult.ok();
    } catch (e) {
      debugPrint('[TrailPhotos] Errore delete: $e');
      return PhotoUploadResult.fail('Errore durante l\'eliminazione');
    }
  }
}
