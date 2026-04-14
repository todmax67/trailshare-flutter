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

  CollectionReference<Map<String, dynamic>> _itemsCollection(String trailId) =>
      _firestore.collection('trail_photos').doc(trailId).collection('items');

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

      return PhotoUploadResult.ok();
    } catch (e) {
      debugPrint('[TrailPhotos] Errore delete: $e');
      return PhotoUploadResult.fail('Errore durante l\'eliminazione');
    }
  }
}
