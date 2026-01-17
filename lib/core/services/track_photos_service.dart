import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Servizio per gestire foto delle tracce
/// Upload su Firebase Storage e gestione metadata
class TrackPhotosService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();

  /// Scatta una foto con la camera
  Future<TrackPhoto?> takePhoto({
    required double latitude,
    required double longitude,
    double? elevation,
  }) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo == null) return null;

      return TrackPhoto(
        localPath: photo.path,
        latitude: latitude,
        longitude: longitude,
        elevation: elevation,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[TrackPhotos] Errore scatto foto: $e');
      return null;
    }
  }

  /// Seleziona foto dalla galleria
  Future<List<TrackPhoto>> pickFromGallery({
    double? latitude,
    double? longitude,
    double? elevation,
  }) async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (images.isEmpty) return [];

      return images.map((img) => TrackPhoto(
        localPath: img.path,
        latitude: latitude,
        longitude: longitude,
        elevation: elevation,
        timestamp: DateTime.now(),
      )).toList();
    } catch (e) {
      debugPrint('[TrackPhotos] Errore selezione foto: $e');
      return [];
    }
  }

  /// Upload foto su Firebase Storage
  /// Path: /tracks/{userId}/{trackId}/{photoId}.jpg
  Future<String?> uploadPhoto({
    required String localPath,
    required String trackId,
    String? photoId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[TrackPhotos] Utente non autenticato');
      return null;
    }

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('[TrackPhotos] File non trovato: $localPath');
        return null;
      }

      // Genera ID univoco se non fornito
      photoId ??= DateTime.now().millisecondsSinceEpoch.toString();
      
      // Estensione file
      final ext = path.extension(localPath).toLowerCase();
      final validExt = ['.jpg', '.jpeg', '.png'].contains(ext) ? ext : '.jpg';

      // Path Storage
      final storagePath = 'tracks/${user.uid}/$trackId/$photoId$validExt';
      final ref = _storage.ref().child(storagePath);

      // Metadata
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      // Upload
      debugPrint('[TrackPhotos] Upload in corso: $storagePath');
      final uploadTask = ref.putFile(file, metadata);
      
      await uploadTask.whenComplete(() {});

      // Ottieni URL download
      final downloadUrl = await ref.getDownloadURL();
      debugPrint('[TrackPhotos] Upload completato: $downloadUrl');
      
      return downloadUrl;
    } catch (e) {
      debugPrint('[TrackPhotos] Errore upload: $e');
      return null;
    }
  }

  /// Upload multiplo con progress callback
  Future<List<UploadedPhoto>> uploadPhotos({
    required List<TrackPhoto> photos,
    required String trackId,
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <UploadedPhoto>[];
    
    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      onProgress?.call(i + 1, photos.length);

      final url = await uploadPhoto(
        localPath: photo.localPath,
        trackId: trackId,
      );

      if (url != null) {
        results.add(UploadedPhoto(
          url: url,
          latitude: photo.latitude,
          longitude: photo.longitude,
          elevation: photo.elevation,
          timestamp: photo.timestamp,
        ));
      }
    }

    return results;
  }

  /// Elimina foto da Storage
  Future<bool> deletePhoto(String photoUrl) async {
    try {
      final ref = _storage.refFromURL(photoUrl);
      await ref.delete();
      debugPrint('[TrackPhotos] Foto eliminata: $photoUrl');
      return true;
    } catch (e) {
      debugPrint('[TrackPhotos] Errore eliminazione: $e');
      return false;
    }
  }

  /// Elimina tutte le foto di una traccia
  Future<void> deleteTrackPhotos({
    required String trackId,
    required List<String> photoUrls,
  }) async {
    for (final url in photoUrls) {
      await deletePhoto(url);
    }
  }

  /// Comprimi immagine (opzionale, per risparmiare storage)
  Future<File?> compressImage(File file, {int quality = 85}) async {
    try {
      // Qui potresti usare flutter_image_compress se necessario
      // Per ora ritorniamo il file originale
      return file;
    } catch (e) {
      debugPrint('[TrackPhotos] Errore compressione: $e');
      return null;
    }
  }
}

/// Modello per foto durante la registrazione (ancora da uplodare)
class TrackPhoto {
  final String localPath;
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final DateTime timestamp;
  final String? caption;

  const TrackPhoto({
    required this.localPath,
    this.latitude,
    this.longitude,
    this.elevation,
    required this.timestamp,
    this.caption,
  });

  TrackPhoto copyWith({
    String? localPath,
    double? latitude,
    double? longitude,
    double? elevation,
    DateTime? timestamp,
    String? caption,
  }) {
    return TrackPhoto(
      localPath: localPath ?? this.localPath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      elevation: elevation ?? this.elevation,
      timestamp: timestamp ?? this.timestamp,
      caption: caption ?? this.caption,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'localPath': localPath,
      'latitude': latitude,
      'longitude': longitude,
      'elevation': elevation,
      'timestamp': timestamp.toIso8601String(),
      'caption': caption,
    };
  }
}

/// Modello per foto già uploadata
class UploadedPhoto {
  final String url;
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final DateTime timestamp;
  final String? caption;

  const UploadedPhoto({
    required this.url,
    this.latitude,
    this.longitude,
    this.elevation,
    required this.timestamp,
    this.caption,
  });

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'latitude': latitude,
      'longitude': longitude,
      'elevation': elevation,
      'timestamp': timestamp.toIso8601String(),
      'caption': caption,
    };
  }

  factory UploadedPhoto.fromMap(Map<String, dynamic> map) {
    return UploadedPhoto(
      url: map['url'] as String,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      elevation: map['elevation'] as double?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      caption: map['caption'] as String?,
    );
  }
}

/// Risultato upload batch
class BatchUploadResult {
  final List<UploadedPhoto> successful;
  final List<TrackPhoto> failed;

  const BatchUploadResult({
    required this.successful,
    required this.failed,
  });

  int get successCount => successful.length;
  int get failedCount => failed.length;
  bool get hasFailures => failed.isNotEmpty;
}
