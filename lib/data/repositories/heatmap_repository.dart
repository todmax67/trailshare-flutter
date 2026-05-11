import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Una singola cella della heatmap "trail popolari" (Epic 3.4).
///
/// Aggregata dalla Cloud Function `aggregateHeatmapWeekly` partendo da
/// `published_tracks.startLat/startLng` raggruppate per geohash
/// precision 4 (~20km × 20km). Il centroide è la media dei punti di
/// partenza, non il centro geometrico della cella → rappresenta dove
/// l'attività è realmente concentrata.
class HeatmapCell {
  final String geohash;
  final int count;
  final LatLng center;
  final DateTime? updatedAt;

  const HeatmapCell({
    required this.geohash,
    required this.count,
    required this.center,
    this.updatedAt,
  });

  factory HeatmapCell.fromFirestore(String id, Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble() ?? 0;
    final lng = (data['lng'] as num?)?.toDouble() ?? 0;
    final updated = data['updatedAt'];
    return HeatmapCell(
      geohash: data['geohash']?.toString() ?? id,
      count: (data['count'] as num?)?.toInt() ?? 0,
      center: LatLng(lat, lng),
      updatedAt: updated is Timestamp ? updated.toDate() : null,
    );
  }
}

/// Read-only del bucket `heatmap_cells`. La collezione è piccola
/// (~50-100 doc per l'Italia in geohash p4), perciò fetchiamo tutto
/// in un colpo e filtriamo client-side per bounds quando serve.
class HeatmapRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Carica tutte le celle. Le scritture avvengono solo dalle Cloud
  /// Functions (admin SDK), quindi non serve stream real-time per la UI
  /// — l'utente comune non vedrà mai un update durante una sessione.
  Future<List<HeatmapCell>> getAll() async {
    try {
      final snap = await _firestore.collection('heatmap_cells').get();
      return snap.docs
          .map((d) => HeatmapCell.fromFirestore(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint('[HeatmapRepo] getAll error: $e');
      return const [];
    }
  }
}
