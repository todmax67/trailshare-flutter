import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Servizio per gestire foto delle tracce
/// Upload su Firebase Storage e gestione metadata
/// 
/// FIX: Ridotta qualità e dimensioni per prevenire crash di memoria
class TrackPhotosService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();

  // ⚠️ FIX: Dimensioni ridotte per prevenire OutOfMemory
  static const int _maxWidth = 1280;  // Era 1920
  static const int _maxHeight = 720;  // Era 1080
  static const int _imageQuality = 70; // Era 85

  /// Scatta una foto con la camera
  /// FIX: Aggiunto try-catch più robusto e dimensioni ridotte
  Future<TrackPhoto?> takePhoto({
    required double latitude,
    required double longitude,
    double? elevation,
  }) async {
    try {
      debugPrint('[TrackPhotos] Apertura camera...');
      
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxWidth.toDouble(),
        maxHeight: _maxHeight.toDouble(),
        imageQuality: _imageQuality,
        // FIX: Preferisci la camera posteriore (meno memoria)
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) {
        debugPrint('[TrackPhotos] Foto annullata dall\'utente');
        return null;
      }

      debugPrint('[TrackPhotos] Foto scattata: ${photo.path}');
      
      // FIX: Verifica che il file esista e sia accessibile
      final file = File(photo.path);
      if (!await file.exists()) {
        debugPrint('[TrackPhotos] ERRORE: File foto non trovato!');
        return null;
      }

      final fileSize = await file.length();
      debugPrint('[TrackPhotos] Dimensione foto: ${(fileSize / 1024).toStringAsFixed(1)} KB');

      return TrackPhoto(
        localPath: photo.path,
        latitude: latitude,
        longitude: longitude,
        elevation: elevation,
        timestamp: DateTime.now(),
      );
    } catch (e, stackTrace) {
      debugPrint('[TrackPhotos] ERRORE scatto foto: $e');
      debugPrint('[TrackPhotos] StackTrace: $stackTrace');
      return null;
    }
  }

  /// Seleziona foto dalla galleria
  /// FIX: Limitato numero massimo di foto selezionabili
  Future<List<TrackPhoto>> pickFromGallery({
    double? latitude,
    double? longitude,
    double? elevation,
    int maxImages = 5, // FIX: Limita selezione multipla
  }) async {
    try {
      debugPrint('[TrackPhotos] Apertura galleria...');
      
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: _maxWidth.toDouble(),
        maxHeight: _maxHeight.toDouble(),
        imageQuality: _imageQuality,
        limit: maxImages, // FIX: Limita numero immagini
      );

      if (images.isEmpty) {
        debugPrint('[TrackPhotos] Nessuna foto selezionata');
        return [];
      }

      debugPrint('[TrackPhotos] Selezionate ${images.length} foto');

      final photos = <TrackPhoto>[];
      for (final img in images) {
        // FIX: Verifica ogni file
        final file = File(img.path);
        if (await file.exists()) {
          photos.add(TrackPhoto(
            localPath: img.path,
            latitude: latitude,
            longitude: longitude,
            elevation: elevation,
            timestamp: DateTime.now(),
          ));
        }
      }

      return photos;
    } catch (e, stackTrace) {
      debugPrint('[TrackPhotos] ERRORE selezione foto: $e');
      debugPrint('[TrackPhotos] StackTrace: $stackTrace');
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
}

/// Modello per foto durante la registrazione (ancora da uplodare)
class TrackPhoto {
  final String localPath;
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final DateTime timestamp;

  TrackPhoto({
    required this.localPath,
    this.latitude,
    this.longitude,
    this.elevation,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'localPath': localPath,
    'latitude': latitude,
    'longitude': longitude,
    'elevation': elevation,
    'timestamp': timestamp.toIso8601String(),
  };

  factory TrackPhoto.fromJson(Map<String, dynamic> json) {
    return TrackPhoto(
      localPath: json['localPath'] as String,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      elevation: json['elevation'] as double?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Modello per foto già caricate su Firebase
class UploadedPhoto {
  final String url;
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final DateTime timestamp;

  UploadedPhoto({
    required this.url,
    this.latitude,
    this.longitude,
    this.elevation,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'latitude': latitude,
    'longitude': longitude,
    'elevation': elevation,
    'timestamp': timestamp.toIso8601String(),
  };

  factory UploadedPhoto.fromJson(Map<String, dynamic> json) {
    return UploadedPhoto(
      url: json['url'] as String,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      elevation: json['elevation'] as double?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
