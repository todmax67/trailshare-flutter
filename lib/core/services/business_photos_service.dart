import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

/// Sotto-categoria di foto business, mappa al sotto-path Storage.
enum BusinessPhotoKind {
  logo,
  hero,
  gallery,
  posts,
  services;

  String get pathSegment => name;
}

/// Upload foto per Spazio Pro su Firebase Storage.
/// Pattern parallelo a TrackPhotosService:
/// - max 1280×720, qualità 70 → previene OOM
/// - retry con backoff
/// - path: businesses/{businessId}/{kind}/{photoId}.jpg
class BusinessPhotosService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();

  static const int _maxWidth = 1280;
  static const int _maxHeight = 720;
  static const int _quality = 70;
  static const int _maxRetries = 3;
  static const Duration _initialRetry = Duration(seconds: 2);

  // ─── PICK ────────────────────────────────────────────────────────────

  /// Apre la galleria del device. Ritorna il path locale o null.
  Future<String?> pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _maxWidth.toDouble(),
        maxHeight: _maxHeight.toDouble(),
        imageQuality: _quality,
      );
      return picked?.path;
    } catch (e) {
      debugPrint('[BusinessPhotos] Errore picker galleria: $e');
      return null;
    }
  }

  /// Apre la camera. Ritorna il path locale o null.
  Future<String?> takePhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxWidth.toDouble(),
        maxHeight: _maxHeight.toDouble(),
        imageQuality: _quality,
        preferredCameraDevice: CameraDevice.rear,
      );
      return picked?.path;
    } catch (e) {
      debugPrint('[BusinessPhotos] Errore picker camera: $e');
      return null;
    }
  }

  // ─── UPLOAD ──────────────────────────────────────────────────────────

  /// Carica una foto presa con [pickFromGallery] o [takePhoto].
  /// Ritorna l'URL pubblico Storage, o null se fallisce.
  Future<String?> uploadPhoto({
    required String localPath,
    required String businessId,
    required BusinessPhotoKind kind,
    String? photoId,
    int retryCount = 0,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[BusinessPhotos] non autenticato');
      return null;
    }
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('[BusinessPhotos] file non trovato: $localPath');
        return null;
      }

      photoId ??= DateTime.now().millisecondsSinceEpoch.toString();
      final ext = path.extension(localPath).toLowerCase();
      final validExt =
          ['.jpg', '.jpeg', '.png', '.webp'].contains(ext) ? ext : '.jpg';
      final storagePath =
          'businesses/$businessId/${kind.pathSegment}/$photoId$validExt';
      final ref = _storage.ref().child(storagePath);

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
          'uploadedBy': user.uid,
          'kind': kind.name,
        },
      );

      debugPrint(
          '[BusinessPhotos] upload $storagePath (tentativo ${retryCount + 1}/$_maxRetries)');
      final task = ref.putFile(file, metadata);
      await task.whenComplete(() {});
      final url = await ref.getDownloadURL();
      debugPrint('[BusinessPhotos] uploaded: $url');
      return url;
    } catch (e) {
      debugPrint('[BusinessPhotos] errore upload (try ${retryCount + 1}): $e');
      if (retryCount < _maxRetries - 1) {
        await Future.delayed(_initialRetry * (retryCount + 1));
        return uploadPhoto(
          localPath: localPath,
          businessId: businessId,
          kind: kind,
          photoId: photoId,
          retryCount: retryCount + 1,
        );
      }
      return null;
    }
  }

  /// Variante **web-compatible** di [uploadPhoto]: accetta i bytes
  /// della foto invece di un path file. dart:io File non funziona su
  /// web (errore 'Unsupported operation: _Namespace'), quindi tutti
  /// i caller web (es. WebBusinessDashboardPage upload cover/logo)
  /// devono passare da qui.
  Future<String?> uploadPhotoBytes({
    required Uint8List bytes,
    required String businessId,
    required BusinessPhotoKind kind,
    String? photoId,
    String extension = '.jpg',
    int retryCount = 0,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[BusinessPhotos] uploadBytes: non autenticato');
      return null;
    }
    try {
      photoId ??= DateTime.now().millisecondsSinceEpoch.toString();
      final validExt =
          ['.jpg', '.jpeg', '.png', '.webp'].contains(extension.toLowerCase())
              ? extension.toLowerCase()
              : '.jpg';
      final storagePath =
          'businesses/$businessId/${kind.pathSegment}/$photoId$validExt';
      final ref = _storage.ref().child(storagePath);

      final mime = validExt == '.png'
          ? 'image/png'
          : validExt == '.webp'
              ? 'image/webp'
              : 'image/jpeg';
      final metadata = SettableMetadata(
        contentType: mime,
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
          'uploadedBy': user.uid,
          'kind': kind.name,
        },
      );

      debugPrint(
          '[BusinessPhotos] uploadBytes $storagePath (tentativo ${retryCount + 1}/$_maxRetries)');
      await ref.putData(bytes, metadata).whenComplete(() {});
      final url = await ref.getDownloadURL();
      debugPrint('[BusinessPhotos] uploadBytes ok: $url');
      return url;
    } catch (e) {
      debugPrint(
          '[BusinessPhotos] uploadBytes errore (try ${retryCount + 1}): $e');
      if (retryCount < _maxRetries - 1) {
        await Future.delayed(_initialRetry * (retryCount + 1));
        return uploadPhotoBytes(
          bytes: bytes,
          businessId: businessId,
          kind: kind,
          photoId: photoId,
          extension: extension,
          retryCount: retryCount + 1,
        );
      }
      return null;
    }
  }

  /// Cancella una foto da Storage dato il suo URL pubblico.
  /// Best-effort: se fallisce non blocchiamo l'UX.
  Future<void> deletePhotoByUrl(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      debugPrint('[BusinessPhotos] deleted: $url');
    } catch (e) {
      debugPrint('[BusinessPhotos] delete errore: $e');
    }
  }

  // ─── HELPERS COMBINATI ───────────────────────────────────────────────

  /// Pick gallery + upload in un singolo passo. Ritorna URL o null.
  ///
  /// **Web-aware**: su web (`kIsWeb`) salta dart:io File (che dà
  /// `Unsupported operation: _Namespace`) e usa
  /// XFile.readAsBytes() + [uploadPhotoBytes]. Su mobile resta il
  /// vecchio flow basato su path + putFile.
  Future<String?> pickAndUpload({
    required String businessId,
    required BusinessPhotoKind kind,
    bool fromCamera = false,
  }) async {
    if (kIsWeb) {
      // Su web non esiste 'camera' come abstract image_picker source:
      // pickImage(camera) apre comunque un selector. Default a gallery.
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
        return uploadPhotoBytes(
          bytes: bytes,
          businessId: businessId,
          kind: kind,
          extension: ext,
        );
      } catch (e) {
        debugPrint('[BusinessPhotos] pickAndUpload web errore: $e');
        return null;
      }
    }

    final localPath =
        fromCamera ? await takePhoto() : await pickFromGallery();
    if (localPath == null) return null;
    return uploadPhoto(
      localPath: localPath,
      businessId: businessId,
      kind: kind,
    );
  }
}
