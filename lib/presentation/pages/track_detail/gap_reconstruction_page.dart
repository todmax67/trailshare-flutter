import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/map_styles.dart';
import '../../../core/services/map_style_prefs.dart';
import '../../../core/services/offline_tile_provider.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/utils/map_bounds.dart';
import '../../../data/models/track.dart';
import '../../widgets/osm_attribution.dart';

/// Il proprietario disegna il tratto percorso mentre la registrazione era
/// ferma. Fase 2 di docs/tracce_ricostruite.md.
///
/// Il percorso proposto arriva dal motore di routing gia' usato dal
/// pianificatore, agganciato ai due estremi del buco. Chi ha camminato puo'
/// aggiungere punti intermedi se la proposta ha preso la strada sbagliata: e'
/// il motivo per cui questa funzione e' aperta solo a lui, e non a un
/// algoritmo che indovina.
///
/// Ritorna la lista dei punti confermati, oppure `null` se si annulla.
class GapReconstructionPage extends StatefulWidget {
  final TrackGap gap;
  final ActivityType activityType;

  /// Estremi del buco, presi dalla traccia: l'ultimo punto registrato prima e
  /// il primo dopo.
  final LatLng from;
  final LatLng to;

  const GapReconstructionPage({
    super.key,
    required this.gap,
    required this.activityType,
    required this.from,
    required this.to,
  });

  @override
  State<GapReconstructionPage> createState() => _GapReconstructionPageState();
}

class _GapReconstructionPageState extends State<GapReconstructionPage> {
  final MapController _map = MapController();
  final OfflineFallbackTileProvider _tiles = OfflineFallbackTileProvider();
  late final RoutingService _routing;

  /// Punti intermedi aggiunti a mano, fra [widget.from] e [widget.to].
  final List<LatLng> _vie = [];

  List<LatLng> _route = const [];
  double _routeMeters = 0;
  bool _loading = true;
  String? _error;

  /// Contatore delle richieste di percorso partite.
  ///
  /// Ogni tocco ne fa partire una nuova senza poter annullare quella in volo,
  /// e le risposte non tornano nell'ordine in cui sono state chieste: una
  /// richiesta piu' vecchia che arriva dopo sovrascriveva il percorso giusto
  /// con quello che ignorava l'ultima correzione — e il pannello, i
  /// chilometri e il salvataggio riguardavano tutti quel percorso vecchio,
  /// mentre sulla mappa restava il marker del punto appena aggiunto. Nessun
  /// segnale che qualcosa fosse andato storto: si salvava un tratto diverso
  /// da quello disegnato.
  int _richiesta = 0;

  @override
  void initState() {
    super.initState();
    _routing = RoutingService(proxyBaseUrl: AppConfig.orsProxyBaseUrl);
    // Se il buco e' gia' stato ricostruito, si riparte da li' invece che da
    // capo: correggere e' piu' facile che rifare.
    if (widget.gap.hasReconstruction) {
      _route = widget.gap.reconstruction;
      _routeMeters = _lengthOf(_route);
      _loading = false;
    } else {
      _calcola();
    }
  }

  RoutingProfile get _profile => switch (widget.activityType) {
        ActivityType.cycling ||
        ActivityType.mountainBiking ||
        ActivityType.gravelBiking ||
        ActivityType.eBike ||
        ActivityType.eMountainBike =>
          RoutingProfile.cycling,
        _ => RoutingProfile.hiking,
      };

  Future<void> _calcola() async {
    final mia = ++_richiesta;
    setState(() {
      _loading = true;
      _error = null;
    });
    final waypoints = [widget.from, ..._vie, widget.to];
    final outcome = await _routing.calculateRouteWithDetails(
      waypoints,
      profile: _profile,
    );
    if (!mounted) return;
    // Scaduta: nel frattempo l'utente ha aggiunto o tolto un punto. Vale la
    // risposta piu' recente, anche quando questa e' andata a buon fine — e
    // soprattutto quando e' fallita, o un errore vecchio bloccherebbe il
    // salvataggio di un percorso valido.
    if (mia != _richiesta) return;
    final res = outcome.result;
    if (res == null || res.points.length < 2) {
      setState(() {
        _loading = false;
        _route = const [];
        _routeMeters = 0;
        // Il messaggio del servizio e' piu' utile del nostro: sa dire quale
        // punto non si aggancia a un sentiero.
        _error = outcome.failure?.userMessage ??
            'Non sono riuscito a trovare un percorso fra i due punti.';
      });
      return;
    }
    setState(() {
      _loading = false;
      _route = res.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
      _routeMeters = res.distance;
    });
  }

  double _lengthOf(List<LatLng> pts) {
    const d = Distance();
    var m = 0.0;
    for (var i = 1; i < pts.length; i++) {
      m += d.as(LengthUnit.Meter, pts[i - 1], pts[i]);
    }
    return m;
  }

  void _onTap(LatLng p) {
    setState(() => _vie.add(p));
    _calcola();
  }

  void _annullaUltimoPunto() {
    if (_vie.isEmpty) return;
    setState(() => _vie.removeLast());
    _calcola();
  }

  @override
  Widget build(BuildContext context) {
    final style = mapStyles[MapStylePrefs().index];
    final bounds = safeBounds([widget.from, ..._vie, ..._route, widget.to]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Il tratto che hai fatto'),
        actions: [
          if (_vie.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Togli l\'ultimo punto',
              onPressed: _annullaUltimoPunto,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCameraFit: bounds == null
                    ? null
                    : CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(48),
                      ),
                initialCenter: widget.from,
                initialZoom: 13,
                onTap: (_, p) => _onTap(p),
              ),
              children: [
                TileLayer(
                  urlTemplate: style.urlTemplate,
                  userAgentPackageName: 'com.trailshare.app',
                  tileProvider: _tiles,
                ),
                PolylineLayer(polylines: [
                  // La retta di riferimento resta visibile: e' cio' che la
                  // traccia mostra oggi, e serve a capire quanto il percorso
                  // proposto se ne discosta.
                  Polyline(
                    points: [widget.from, widget.to],
                    strokeWidth: 2,
                    color: Colors.grey.withValues(alpha: 0.6),
                    pattern: StrokePattern.dashed(segments: const [6, 6]),
                  ),
                  if (_route.length >= 2)
                    Polyline(
                      points: _route,
                      strokeWidth: 5,
                      color: AppColors.primary,
                    ),
                ]),
                MarkerLayer(markers: [
                  _marker(widget.from, Icons.play_arrow, AppColors.success),
                  _marker(widget.to, Icons.flag, AppColors.danger),
                  for (final v in _vie)
                    _marker(v, Icons.circle, AppColors.primary, size: 18),
                ]),
                const OsmAttribution(),
              ],
            ),
          ),
          _pannello(),
        ],
      ),
    );
  }

  Marker _marker(LatLng p, IconData icon, Color color, {double size = 30}) =>
      Marker(
        point: p,
        width: size + 8,
        height: size + 8,
        child: Icon(icon, color: color, size: size),
      );

  Widget _pannello() {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              // Con "Riprova": se il primo calcolo falliva la pagina restava
              // un vicolo cieco, perche' l'unico modo di far ripartire il
              // routing era aggiungere un punto — e senza percorso disegnato
              // non si capiva nemmeno dove metterlo. Un servizio di routing
              // che non risponde una volta spesso risponde alla seconda.
              Row(
                children: [
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(color: AppColors.danger)),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _calcola,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Riprova'),
                  ),
                ],
              )
            else
              Text(
                '≈ ${(_routeMeters / 1000).toStringAsFixed(1)} km lungo i sentieri. '
                'Tocca la mappa per aggiungere un punto se il percorso proposto '
                'non è quello che hai fatto.',
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 8),
            // Detto qui e non dopo: chi salva deve sapere COSA sta salvando.
            // Detto nel momento della decisione, quindi dev'essere esatto: la
            // corda in linea retta fra i due estremi resta dentro la distanza
            // della traccia — ricostruire aggiunge un disegno, non toglie la
            // corda. Dire "quelli restano solo ciò che il GPS ha misurato"
            // sarebbe la stessa falsità corretta in Fase 1.
            Text(
              'Resterà tratteggiato e dichiarato come ricostruito. Questi '
              'chilometri non si sommano alla distanza della traccia, che '
              'continua a contare quel tratto solo in linea retta.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annulla'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (_route.length >= 2 && !_loading)
                        ? () => Navigator.of(context).pop(_route)
                        : null,
                    child: const Text('Salva il tratto'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
