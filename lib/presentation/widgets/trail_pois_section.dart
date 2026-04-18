import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/trail_poi.dart';
import '../../data/repositories/poi_repository.dart';
import '../pages/poi/poi_location_picker_page.dart';
import 'poi_detail_sheet.dart';
import 'poi_editor_sheet.dart';

/// Sezione "POI" nelle pagine di dettaglio trail/track.
///
/// Modalità:
/// - `trailId` != null: carica POI associati a un trail OSM pubblico
/// - `trackId` != null: carica POI associati a una track community
///   (con `includePrivate=true` se l'utente è owner della track, così
///   vede anche i suoi POI non ancora pubblici)
///
/// Quando `allowAdd=true` mostra un pulsante "Aggiungi POI" che apre
/// il bottom sheet di creazione. Dopo la creazione ricarica la lista.
class TrailPoisSection extends StatefulWidget {
  final String? trailId;
  final String? trackId;

  /// Se la pagina è mostrata al proprietario della traccia — in tal caso
  /// mostriamo anche i suoi POI privati e permettiamo di aggiungerne.
  final bool isOwner;

  /// Se true (e trackId != null) mostra il pulsante "Aggiungi POI".
  /// Richiede che il chiamante fornisca anche le coordinate della traccia
  /// per stimare dove posizionare il nuovo POI (di solito il punto medio).
  final bool allowAdd;

  /// Coordinate di fallback del trail/track per centrare il picker POI
  /// quando la polyline non è disponibile. Non viene usato come posizione
  /// finale del POI (l'utente sceglie sempre sulla mappa).
  final double? defaultLatitude;
  final double? defaultLongitude;

  /// Polyline completa del trail/track. Se presente viene mostrata sul
  /// picker posizione come riferimento visivo per piazzare il POI lungo
  /// il percorso.
  final List<LatLng>? polyline;

  const TrailPoisSection({
    super.key,
    this.trailId,
    this.trackId,
    this.isOwner = false,
    this.allowAdd = false,
    this.defaultLatitude,
    this.defaultLongitude,
    this.polyline,
  }) : assert(trailId != null || trackId != null,
            'Passa almeno trailId o trackId');

  @override
  State<TrailPoisSection> createState() => _TrailPoisSectionState();
}

class _TrailPoisSectionState extends State<TrailPoisSection> {
  final _repo = PoiRepository();
  List<TrailPoi> _pois = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    List<TrailPoi> pois;
    if (widget.trailId != null) {
      pois = await _repo.getPoisForTrail(widget.trailId!);
    } else {
      pois = await _repo.getPoisForTrack(
        widget.trackId!,
        includePrivate: widget.isOwner,
      );
    }
    if (!mounted) return;
    // Ordina per score discendente (top POI prima), poi per data recente
    pois.sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      return (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000));
    });
    setState(() {
      _pois = pois;
      _loading = false;
    });
  }

  Future<void> _openAddPoiSheet() async {
    // 1. Prima apre il picker posizione: mappa con polyline del trail/track
    //    dove l'utente tocca per scegliere il punto esatto del POI.
    final initialCenter = widget.defaultLatitude != null &&
            widget.defaultLongitude != null
        ? LatLng(widget.defaultLatitude!, widget.defaultLongitude!)
        : null;
    final picked = await Navigator.push<LatLng?>(
      context,
      MaterialPageRoute(
        builder: (_) => PoiLocationPickerPage(
          polyline: widget.polyline ?? const [],
          initialCenter: initialCenter,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    // 2. Con la posizione scelta, apre l'editor POI.
    final poi = await showPoiEditorSheet(
      context,
      latitude: picked.latitude,
      longitude: picked.longitude,
      relatedTrailId: widget.trailId,
      relatedTrackId: widget.trackId,
    );
    if (poi != null && mounted) _load();
  }

  Future<void> _openPoiDetail(TrailPoi poi) async {
    final result = await showPoiDetailSheet(context, poi: poi);
    if ((result == PoiDetailResult.deleted ||
            result == PoiDetailResult.updated) &&
        mounted) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_pois.isEmpty && !widget.allowAdd) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.place, size: 18, color: AppColors.info),
              const SizedBox(width: 6),
              Text(
                'POI lungo il percorso',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                _pois.isEmpty ? '—' : '${_pois.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_pois.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nessun POI segnalato al momento.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._pois.map(_buildPoiTile),
          if (widget.allowAdd) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openAddPoiSheet,
                icon: const Icon(Icons.add_location_alt, size: 18),
                label: const Text('Aggiungi POI'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.info,
                  side: const BorderSide(color: AppColors.info),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPoiTile(TrailPoi poi) {
    final isMine =
        FirebaseAuth.instance.currentUser?.uid == poi.createdBy;
    return InkWell(
      onTap: () => _openPoiDetail(poi),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // Icona tipo
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: poi.type.pinColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(poi.type.emoji,
                  style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          poi.title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!poi.isPublic) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.lock_outline,
                            size: 12,
                            color:
                                Theme.of(context).colorScheme.outline),
                      ],
                      if (poi.verifiedByAdmin) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified,
                            size: 12, color: AppColors.info),
                      ],
                    ],
                  ),
                  Text(
                    poi.type.displayName,
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Score
            if (poi.upvotes + poi.downvotes > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: poi.score > 0
                      ? AppColors.success.withOpacity(0.15)
                      : poi.score < 0
                          ? AppColors.danger.withOpacity(0.15)
                          : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  poi.score > 0 ? '+${poi.score}' : '${poi.score}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: poi.score > 0
                        ? AppColors.success
                        : poi.score < 0
                            ? AppColors.danger
                            : Colors.grey,
                  ),
                ),
              ),
            if (isMine)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.person_outline,
                    size: 14, color: AppColors.textMuted),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

