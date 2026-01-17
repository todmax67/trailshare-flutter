import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/track.dart';

/// Servizio per persistere lo stato della registrazione su disco.
/// Previene la perdita di dati in caso di crash o kill dell'app.
class RecordingPersistenceService {
  static const String _fileName = 'recording_backup.json';
  static RecordingPersistenceService? _instance;
  
  RecordingPersistenceService._();
  
  static RecordingPersistenceService get instance {
    _instance ??= RecordingPersistenceService._();
    return _instance!;
  }

  File? _backupFile;

  Future<File> get _file async {
    if (_backupFile != null) return _backupFile!;
    final dir = await getApplicationDocumentsDirectory();
    _backupFile = File('${dir.path}/$_fileName');
    return _backupFile!;
  }

  /// Salva lo stato corrente della registrazione
  Future<void> saveState(RecordingBackup backup) async {
    try {
      final file = await _file;
      final json = jsonEncode(backup.toMap());
      await file.writeAsString(json);
      debugPrint('[RecordingPersistence] Stato salvato: ${backup.points.length} punti');
    } catch (e) {
      debugPrint('[RecordingPersistence] Errore salvataggio: $e');
    }
  }

  /// Carica lo stato salvato (se esiste)
  Future<RecordingBackup?> loadState() async {
    try {
      final file = await _file;
      if (!await file.exists()) {
        debugPrint('[RecordingPersistence] Nessun backup trovato');
        return null;
      }

      final json = await file.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      final backup = RecordingBackup.fromMap(data);
      
      debugPrint('[RecordingPersistence] Backup caricato: ${backup.points.length} punti');
      return backup;
    } catch (e) {
      debugPrint('[RecordingPersistence] Errore caricamento: $e');
      return null;
    }
  }

  /// Elimina il backup (dopo salvataggio completato)
  Future<void> clearState() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        await file.delete();
        debugPrint('[RecordingPersistence] Backup eliminato');
      }
    } catch (e) {
      debugPrint('[RecordingPersistence] Errore eliminazione: $e');
    }
  }

  /// Verifica se esiste un backup
  Future<bool> hasBackup() async {
    final file = await _file;
    return file.exists();
  }
}

/// Modello per il backup della registrazione
class RecordingBackup {
  final List<TrackPoint> points;
  final DateTime startTime;
  final Duration pausedDuration;
  final ActivityType activityType;
  final List<PhotoBackup> photos;
  final DateTime lastSaveTime;

  RecordingBackup({
    required this.points,
    required this.startTime,
    required this.pausedDuration,
    required this.activityType,
    required this.photos,
    DateTime? lastSaveTime,
  }) : lastSaveTime = lastSaveTime ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'points': points.map((p) => p.toMap()).toList(),
    'startTime': startTime.toIso8601String(),
    'pausedDuration': pausedDuration.inSeconds,
    'activityType': activityType.index,
    'photos': photos.map((p) => p.toMap()).toList(),
    'lastSaveTime': lastSaveTime.toIso8601String(),
  };

  factory RecordingBackup.fromMap(Map<String, dynamic> map) {
    return RecordingBackup(
      points: (map['points'] as List)
          .map((p) => TrackPoint.fromMap(p as Map<String, dynamic>))
          .toList(),
      startTime: DateTime.parse(map['startTime'] as String),
      pausedDuration: Duration(seconds: map['pausedDuration'] as int),
      activityType: ActivityType.values[map['activityType'] as int],
      photos: (map['photos'] as List?)
          ?.map((p) => PhotoBackup.fromMap(p as Map<String, dynamic>))
          .toList() ?? [],
      lastSaveTime: DateTime.parse(map['lastSaveTime'] as String),
    );
  }
}

/// Backup minimo per le foto (solo path locale e coordinate)
class PhotoBackup {
  final String localPath;
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final DateTime timestamp;

  PhotoBackup({
    required this.localPath,
    this.latitude,
    this.longitude,
    this.elevation,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'localPath': localPath,
    'latitude': latitude,
    'longitude': longitude,
    'elevation': elevation,
    'timestamp': timestamp.toIso8601String(),
  };

  factory PhotoBackup.fromMap(Map<String, dynamic> map) {
    return PhotoBackup(
      localPath: map['localPath'] as String,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      elevation: map['elevation'] as double?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
