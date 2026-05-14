import 'dart:io';
import 'package:exif/exif.dart';
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

  // Configurazione retry
  static const int _maxRetries = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 2);

  /// Upload foto su Firebase Storage con retry automatico
  /// Path: /tracks/{userId}/{trackId}/{photoId}.jpg
  Future<String?> uploadPhoto({
    required String localPath,
    required String trackId,
    String? photoId,
    int retryCount = 0,
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
      debugPrint('[TrackPhotos] Upload in corso: $storagePath (tentativo ${retryCount + 1}/$_maxRetries)');
      final uploadTask = ref.putFile(file, metadata);
      
      await uploadTask.whenComplete(() {});

      // Ottieni URL download
      final downloadUrl = await ref.getDownloadURL();
      debugPrint('[TrackPhotos] Upload completato: $downloadUrl');
      
      return downloadUrl;
    } catch (e) {
      debugPrint('[TrackPhotos] Errore upload (tentativo ${retryCount + 1}): $e');
      
      // Retry con backoff esponenziale
      if (retryCount < _maxRetries - 1) {
        final delay = _initialRetryDelay * (retryCount + 1);
        debugPrint('[TrackPhotos] Retry tra ${delay.inSeconds}s...');
        await Future.delayed(delay);
        return uploadPhoto(
          localPath: localPath,
          trackId: trackId,
          photoId: photoId,
          retryCount: retryCount + 1,
        );
      }
      
      debugPrint('[TrackPhotos] Upload fallito dopo $_maxRetries tentativi');
      return null;
    }
  }

  /// Upload multiplo con progress callback e tracking fallimenti
  /// Ritorna le foto caricate con successo e logga quelle fallite
  Future<UploadResult> uploadPhotos({
    required List<TrackPhoto> photos,
    required String trackId,
    void Function(int current, int total)? onProgress,
  }) async {
    final uploaded = <UploadedPhoto>[];
    final failed = <TrackPhoto>[];
    
    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      onProgress?.call(i + 1, photos.length);

      final url = await uploadPhoto(
        localPath: photo.localPath,
        trackId: trackId,
      );

      if (url != null) {
        uploaded.add(UploadedPhoto(
          url: url,
          latitude: photo.latitude,
          longitude: photo.longitude,
          elevation: photo.elevation,
          timestamp: photo.timestamp,
        ));
      } else {
        failed.add(photo);
        debugPrint('[TrackPhotos] Foto fallita: ${photo.localPath}');
      }
    }

    if (failed.isNotEmpty) {
      debugPrint('[TrackPhotos] Upload completato: ${uploaded.length}/${photos.length} (${failed.length} fallite)');
    } else {
      debugPrint('[TrackPhotos] Upload completato: ${uploaded.length}/${photos.length}');
    }

    return UploadResult(uploaded: uploaded, failed: failed);
  }

  /// Estrae lat/lng/elevation/timestamp dai metadati EXIF di una
  /// foto. Ritorna null nei campi mancanti — sicuro da passare anche
  /// a foto senza GPS tag.
  ///
  /// Funziona su mobile e web: il package `exif` legge dai bytes,
  /// non dipende da dart:io.
  static Future<ExifGeoData> readExifGeoFromBytes(
      Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return const ExifGeoData();

      double? toDecimal(String key, {String? refKey}) {
        final tag = tags[key];
        if (tag == null) return null;
        final values = tag.values.toList();
        if (values.length < 3) return null;
        // Le coordinate GPS sono triple di Ratio (deg, min, sec).
        double rat(dynamic r) {
          if (r is Ratio) {
            return r.denominator == 0 ? 0 : r.toDouble();
          }
          return double.tryParse(r.toString()) ?? 0;
        }

        final deg = rat(values[0]);
        final min = rat(values[1]);
        final sec = rat(values[2]);
        double decimal = deg + min / 60 + sec / 3600;
        if (refKey != null) {
          final ref = tags[refKey]?.printable.trim().toUpperCase();
          if (ref == 'S' || ref == 'W') decimal = -decimal;
        }
        return decimal;
      }

      final lat = toDecimal('GPS GPSLatitude', refKey: 'GPS GPSLatitudeRef');
      final lng =
          toDecimal('GPS GPSLongitude', refKey: 'GPS GPSLongitudeRef');

      double? altitude;
      final altTag = tags['GPS GPSAltitude'];
      if (altTag != null) {
        final values = altTag.values.toList();
        if (values.isNotEmpty && values.first is Ratio) {
          final r = values.first as Ratio;
          if (r.denominator != 0) {
            altitude = r.toDouble();
            // ref 1 = below sea level
            final refTag = tags['GPS GPSAltitudeRef'];
            if (refTag != null && refTag.values.firstAsInt() == 1) {
              altitude = -altitude;
            }
          }
        }
      }

      // DateTimeOriginal: 'YYYY:MM:DD HH:MM:SS'
      DateTime? when;
      final dtTag = tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'];
      if (dtTag != null) {
        final s = dtTag.printable.trim();
        if (s.length >= 19) {
          final iso = s
              .replaceFirst(':', '-')
              .replaceFirst(':', '-')
              .replaceFirst(' ', 'T');
          when = DateTime.tryParse(iso);
        }
      }

      return ExifGeoData(
        latitude: lat,
        longitude: lng,
        elevation: altitude,
        takenAt: when,
      );
    } catch (e) {
      debugPrint('[TrackPhotos] EXIF parse error: $e');
      return const ExifGeoData();
    }
  }

  /// Variante di [pickFromGallery] che preserva l'EXIF.
  ///
  /// **Differenza chiave:** non passa `imageQuality` né `maxWidth`/
  /// `maxHeight` a image_picker — il re-encode strippa i tag GPS.
  /// Il resize per ridurre dimensione/banda dovrà essere fatto a
  /// monte di un upload se serve (per ora le storage rules ammettono
  /// 10MB, sufficiente per foto smartphone tipiche).
  ///
  /// Per ogni foto selezionata legge i bytes UNA SOLA VOLTA, ne
  /// estrae EXIF (lat/lng/altitude/timestamp) e li popola in
  /// [TrackPhoto]. I bytes vengono poi scartati: l'upload successivo
  /// li rilegge dal path.
  Future<List<TrackPhoto>> pickFromGalleryWithExif({
    int maxImages = 10,
  }) async {
    try {
      final images = await _picker.pickMultiImage(
        limit: maxImages,
      );
      if (images.isEmpty) return [];

      final photos = <TrackPhoto>[];
      for (final img in images) {
        final file = File(img.path);
        if (!await file.exists()) continue;
        // Read bytes per EXIF parsing (no double-read in seguito:
        // l'upload rilegge dal path che è già su disco).
        final bytes = await img.readAsBytes();
        final geo = await readExifGeoFromBytes(bytes);
        photos.add(TrackPhoto(
          localPath: img.path,
          latitude: geo.latitude,
          longitude: geo.longitude,
          elevation: geo.elevation,
          timestamp: geo.takenAt ?? DateTime.now(),
        ));
      }
      debugPrint(
          '[TrackPhotos] pickWithExif: ${photos.length} foto, '
          '${photos.where((p) => p.latitude != null).length} geo-taggate');
      return photos;
    } catch (e) {
      debugPrint('[TrackPhotos] pickFromGalleryWithExif errore: $e');
      return [];
    }
  }

  /// Upload variante **web-compatible**: accetta i bytes della foto
  /// invece di un path file (dart:io File non funziona su web).
  /// Stesso path Storage di [uploadPhoto] + stessi retry. Da usare
  /// dall'editor foto web e ovunque il source sia in memoria (XFile,
  /// drag&drop, paste, ecc.).
  Future<String?> uploadPhotoBytes({
    required Uint8List bytes,
    required String trackId,
    String? photoId,
    String extension = '.jpg',
    int retryCount = 0,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[TrackPhotos] uploadPhotoBytes: utente non autenticato');
      return null;
    }
    try {
      photoId ??= DateTime.now().millisecondsSinceEpoch.toString();
      final validExt =
          ['.jpg', '.jpeg', '.png'].contains(extension.toLowerCase())
              ? extension.toLowerCase()
              : '.jpg';
      final storagePath =
          'tracks/${user.uid}/$trackId/$photoId$validExt';
      final ref = _storage.ref().child(storagePath);
      final metadata = SettableMetadata(
        contentType: validExt == '.png' ? 'image/png' : 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      debugPrint(
          '[TrackPhotos] uploadBytes: $storagePath (tentativo ${retryCount + 1}/$_maxRetries)');
      await ref.putData(bytes, metadata).whenComplete(() {});
      final url = await ref.getDownloadURL();
      debugPrint('[TrackPhotos] uploadBytes ok: $url');
      return url;
    } catch (e) {
      debugPrint(
          '[TrackPhotos] uploadBytes errore (tentativo ${retryCount + 1}): $e');
      if (retryCount < _maxRetries - 1) {
        final delay = _initialRetryDelay * (retryCount + 1);
        await Future.delayed(delay);
        return uploadPhotoBytes(
          bytes: bytes,
          trackId: trackId,
          photoId: photoId,
          extension: extension,
          retryCount: retryCount + 1,
        );
      }
      return null;
    }
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

/// Risultato dell'upload multiplo
class UploadResult {
  final List<UploadedPhoto> uploaded;
  final List<TrackPhoto> failed;

  UploadResult({
    required this.uploaded,
    required this.failed,
  });

  bool get hasFailures => failed.isNotEmpty;
  bool get allSuccess => failed.isEmpty;
  int get totalCount => uploaded.length + failed.length;
}

/// Metadati GPS estratti dall'EXIF di una foto.
/// Tutti i campi sono nullable: una foto può avere solo timestamp,
/// solo GPS senza altitude, ecc.
class ExifGeoData {
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final DateTime? takenAt;

  const ExifGeoData({
    this.latitude,
    this.longitude,
    this.elevation,
    this.takenAt,
  });

  bool get hasLocation => latitude != null && longitude != null;
}

