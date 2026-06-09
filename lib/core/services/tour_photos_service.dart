import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

/// Tipo di foto associata a un Tour. Determina il path Firebase
/// Storage e l'aspect ratio della UI.
enum TourPhotoKind {
  cover, // foto in cima alla scheda, 16:9
  gallery; // foto extra mostrate in carosello/grid

  String get pathSegment => name;
}

/// Epic 11 — Upload foto cover e gallery di un Tour. Stesso pattern
/// di BusinessPhotosService: pick + upload + retry + Firebase Storage
/// path strutturato `tours/{tourId}/{kind}/{photoId}.jpg`.
///
/// Il tour deve esistere su Firestore prima dell'upload (l'ID viene
/// generato al primo create vuoto). Il flow tipico nell'edit page:
/// 1. createTour(...) → ottieni tourId
/// 2. uploadPhoto / pickAndUpload(tourId, kind)
/// 3. updateTour(tourId, coverPhotoUrl: ..., galleryUrls: [...])
class TourPhotosService {
  TourPhotosService({FirebaseStorage? storage, FirebaseAuth? auth})
      : _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final ImagePicker _picker = ImagePicker();

  static const int _maxWidth = 2400;
  static const int _maxHeight = 2400;
  static const int _quality = 85;
  static const int _maxRetries = 3;
  static const Duration _initialRetry = Duration(seconds: 2);

  /// Pick foto + upload in un solo passo. Cross-platform (web bytes
  /// + mobile file path). Ritorna URL pubblico o null se cancellato/fail.
  Future<String?> pickAndUpload({
    required String tourId,
    required TourPhotoKind kind,
  }) async {
    if (kIsWeb) {
      try {
        final picked = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: _maxWidth.toDouble(),
          maxHeight: _maxHeight.toDouble(),
          imageQuality: _quality,
        );
        if (picked == null) return null;
        final bytes = await picked.readAsBytes();
        final name = picked.name.toLowerCase();
        final ext = name.endsWith('.png')
            ? '.png'
            : name.endsWith('.webp')
                ? '.webp'
                : '.jpg';
        return _uploadBytes(
          bytes: bytes,
          tourId: tourId,
          kind: kind,
          extension: ext,
        );
      } catch (e) {
        debugPrint('[TourPhotos] pickAndUpload web error: $e');
        return null;
      }
    }
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _maxWidth.toDouble(),
        maxHeight: _maxHeight.toDouble(),
        imageQuality: _quality,
      );
      if (picked == null) return null;
      return _uploadFile(
        localPath: picked.path,
        tourId: tourId,
        kind: kind,
      );
    } catch (e) {
      debugPrint('[TourPhotos] pickAndUpload mobile error: $e');
      return null;
    }
  }

  Future<String?> _uploadFile({
    required String localPath,
    required String tourId,
    required TourPhotoKind kind,
    int retryCount = 0,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final file = File(localPath);
      if (!await file.exists()) return null;
      final photoId = DateTime.now().millisecondsSinceEpoch.toString();
      final ext = path.extension(localPath).toLowerCase();
      final validExt =
          ['.jpg', '.jpeg', '.png', '.webp'].contains(ext) ? ext : '.jpg';
      final storagePath =
          'tours/$tourId/${kind.pathSegment}/$photoId$validExt';
      final ref = _storage.ref().child(storagePath);
      await ref.putFile(file).whenComplete(() {});
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('[TourPhotos] uploadFile error (try ${retryCount + 1}): $e');
      if (retryCount < _maxRetries - 1) {
        await Future.delayed(_initialRetry * (retryCount + 1));
        return _uploadFile(
          localPath: localPath,
          tourId: tourId,
          kind: kind,
          retryCount: retryCount + 1,
        );
      }
      return null;
    }
  }

  Future<String?> _uploadBytes({
    required Uint8List bytes,
    required String tourId,
    required TourPhotoKind kind,
    String extension = '.jpg',
    int retryCount = 0,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final photoId = DateTime.now().millisecondsSinceEpoch.toString();
      final storagePath =
          'tours/$tourId/${kind.pathSegment}/$photoId$extension';
      final ref = _storage.ref().child(storagePath);
      // Sul web putData senza metadata carica come application/octet-stream:
      // le Storage rules richiedono contentType image/* → 403. Esplicitiamo.
      final contentType = extension == '.png'
          ? 'image/png'
          : extension == '.webp'
              ? 'image/webp'
              : 'image/jpeg';
      await ref
          .putData(bytes, SettableMetadata(contentType: contentType))
          .whenComplete(() {});
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('[TourPhotos] uploadBytes error (try ${retryCount + 1}): $e');
      if (retryCount < _maxRetries - 1) {
        await Future.delayed(_initialRetry * (retryCount + 1));
        return _uploadBytes(
          bytes: bytes,
          tourId: tourId,
          kind: kind,
          extension: extension,
          retryCount: retryCount + 1,
        );
      }
      return null;
    }
  }
}
