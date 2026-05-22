import 'package:flutter/material.dart';

import '../../../data/models/business.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../discover/community_track_detail_page.dart';
import '../track_detail/track_detail_page.dart';

/// Apre la pagina dettaglio per una traccia consigliata, instradando verso
/// [TrackDetailPage] (private) o [CommunityTrackDetailPage] (community)
/// in base al [RecommendedTrack.sourceType]. Mostra un loader durante il
/// fetch della traccia completa (i preview hanno solo metadata).
Future<void> openRecommendedTrackDetail(
  BuildContext context,
  RecommendedTrack rec,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    if (rec.sourceType == RecommendedTrackSource.privateTrack) {
      final ownerId = rec.trackOwnerId;
      if (ownerId == null) throw Exception('Owner non disponibile');
      final track = await TracksRepository()
          .getTrackByOwnerAndId(ownerId, rec.trackId);
      if (!context.mounted) return;
      Navigator.pop(context);
      if (track == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Traccia non trovata')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TrackDetailPage(track: track)),
      );
    } else {
      final track =
          await CommunityTracksRepository().getTrackById(rec.trackId);
      if (!context.mounted) return;
      Navigator.pop(context);
      if (track == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Traccia non più disponibile')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommunityTrackDetailPage(track: track),
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Errore apertura traccia: $e')),
    );
  }
}
