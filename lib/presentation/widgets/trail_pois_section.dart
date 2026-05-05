import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/osm_poi.dart';
import '../../data/models/trail_poi.dart';
import '../../data/repositories/osm_pois_repository.dart';
import '../../data/repositories/poi_repository.dart';
import '../pages/poi/poi_location_picker_page.dart';
import 'osm_poi_detail_sheet.dart';
import 'poi_detail_sheet.dart';
import 'poi_editor_sheet.dart';
import '../../core/extensions/theme_colors_extension.dart';

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

  /// Se true (e [polyline] non vuoto), arricchisce la sezione con i POI
  /// statici da OpenStreetMap che cadono entro [osmRadiusMeters] dalla
  /// traccia: rifugi, bivacchi, fontane, sorgenti, panorami, croci.
  /// Da abilitare sulle pagine dettaglio trail/track per "vedere subito
  /// cosa trovi lungo il percorso" senza dipendere da segnalazioni
  /// community.
  final bool loadOsmPois;

  /// Raggio (m) dalla polyline entro cui includere POI OSM. Default 200m.
  final double osmRadiusMeters;

  const TrailPoisSection({
    super.key,
    this.trailId,
    this.trackId,
    this.isOwner = false,
    this.allowAdd = false,
    this.defaultLatitude,
    this.defaultLongitude,
    this.polyline,
    this.loadOsmPois = false,
    this.osmRadiusMeters = 200,
  }) : assert(trailId != null || trackId != null,
            'Passa almeno trailId o trackId');

  @override
  State<TrailPoisSection> createState() => _TrailPoisSectionState();
}

class _TrailPoisSectionState extends State<TrailPoisSection> {
  final _repo = PoiRepository();
  final _osmRepo = OsmPoisRepository();
  List<TrailPoi> _pois = [];
  List<OsmPoi> _osmPois = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      _loadCommunity(),
      _loadOsm(),
    ]);
    if (!mounted) return;
    setState(() {
      _pois = results[0] as List<TrailPoi>;
      _osmPois = results[1] as List<OsmPoi>;
      _loading = false;
    });
  }

  Future<List<TrailPoi>> _loadCommunity() async {
    List<TrailPoi> pois;
    if (widget.trailId != null) {
      pois = await _repo.getPoisForTrail(widget.trailId!);
    } else {
      pois = await _repo.getPoisForTrack(
        widget.trackId!,
        includePrivate: widget.isOwner,
      );
    }
    pois.sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      return (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000));
    });
    return pois;
  }

  Future<List<OsmPoi>> _loadOsm() async {
    final poly = widget.polyline;
    if (!widget.loadOsmPois || poly == null || poly.isEmpty) {
      return const [];
    }
    await _osmRepo.ensureLoaded();
    final found = _osmRepo.findNearPolyline(
      poly,
      radiusMeters: widget.osmRadiusMeters,
    );
    // Ordina: prima rifugi/bivacchi (alta utilità), poi water, poi resto
    found.sort((a, b) {
      int rank(OsmPoiType t) {
        switch (t) {
          case OsmPoiType.alpineHut:
            return 0;
          case OsmPoiType.wildernessHut:
            return 1;
          case OsmPoiType.shelter:
            return 2;
          case OsmPoiType.spring:
            return 3;
          case OsmPoiType.drinkingWater:
            return 4;
          case OsmPoiType.viewpoint:
            return 5;
          case OsmPoiType.picnicSite:
            return 6;
          case OsmPoiType.waysideCross:
            return 7;
          case OsmPoiType.cairn:
            return 8;
        }
      }

      final r = rank(a.type).compareTo(rank(b.type));
      if (r != 0) return r;
      return a.name.compareTo(b.name);
    });
    return found;
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

  Future<void> _openOsmPoiDetail(OsmPoi poi) async {
    await showOsmPoiDetailSheet(context, poi: poi);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_pois.isEmpty && _osmPois.isEmpty && !widget.allowAdd) {
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
                _osmPois.isEmpty
                    ? 'Nessun POI segnalato al momento.'
                    : 'Nessun POI segnalato dalla community su questo percorso.',
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

          // ── Subsection POI OpenStreetMap ──────────────────────────
          if (_osmPois.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.public,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Anche nella zona',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_osmPois.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._osmPois.take(8).map(_buildOsmPoiTile),
            if (_osmPois.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+ ${_osmPois.length - 8} altri',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Dati © OpenStreetMap contributors',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOsmPoiTile(OsmPoi poi) {
    return InkWell(
      onTap: () => _openOsmPoiDetail(poi),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(poi.type.icon, color: AppColors.info, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poi.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        poi.type.displayName,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (poi.elevation != null) ...[
                        Text(
                          ' · ${poi.elevation!.round()} m',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: context.textMuted),
          ],
        ),
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
                      ? AppColors.success.withValues(alpha: 0.15)
                      : poi.score < 0
                          ? AppColors.danger.withValues(alpha: 0.15)
                          : Colors.grey.withValues(alpha: 0.15),
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
              Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.person_outline,
                    size: 14, color: context.textMuted),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 18, color: context.textMuted),
          ],
        ),
      ),
    );
  }
}

