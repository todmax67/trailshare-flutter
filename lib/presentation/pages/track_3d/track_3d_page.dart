import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/api_keys.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/business_repository.dart';

/// Visualizzazione 3D di una traccia con fly-through animato
/// (stile Relive), resa via MapLibre GL JS dentro una WebView con
/// terrain 3D MapTiler.
///
/// La pagina HTML (`assets/3d/flythrough.html`) espone un'API JS
/// (`tsInit`, `tsLoadTrack`, `tsPlay`, `tsPause`, `tsReset`,
/// `tsSetSpeed`, `tsSetExaggeration`) e comunica lo stato a Flutter
/// via il JavaScriptChannel `TSChannel`.
class Track3DPage extends StatefulWidget {
  final String trackName;

  /// Segmenti del percorso: ogni lista interna è una traccia separata.
  /// - Traccia singola / cammino consecutivo → 1 segmento.
  /// - Raccolta (tour collection) → più segmenti, anche distanti: il
  ///   viewer fa un "salto volante" morbido (flyTo) tra l'uno e l'altro.
  final List<List<TrackPoint>> segments;

  /// Nomi dei segmenti (es. nomi tappe/tracce di un tour). Se forniti,
  /// quando il volo inizia un nuovo segmento compare un banner col nome.
  final List<String>? segmentNames;

  const Track3DPage({
    super.key,
    required this.trackName,
    required this.segments,
    this.segmentNames,
  });

  /// Convenience per una sola traccia (un solo segmento).
  factory Track3DPage.single({
    Key? key,
    required String trackName,
    required List<TrackPoint> points,
  }) =>
      Track3DPage(key: key, trackName: trackName, segments: [points]);

  @override
  State<Track3DPage> createState() => _Track3DPageState();
}

class _Track3DPageState extends State<Track3DPage> {
  late final WebViewController _controller;

  bool _ready = false; // mappa + terrain caricati
  bool _trackLoaded = false;
  bool _playing = false;
  double _progress = 0; // 0..1
  double _speed = 1.0;
  double _distM = 0; // distanza dalla partenza (metri)
  double _eleM = 0; // quota corrente (m s.l.m.)
  String? _error;
  String? _segmentBanner; // nome traccia corrente (banner temporaneo)
  int _segmentBannerSeq = 0;
  String? _poiBanner; // Spazio Pro raggiunto (banner temporaneo)
  int _poiBannerSeq = 0;

  bool _mapReady = false;
  List<Map<String, dynamic>>? _pois; // Spazi Pro vicini al percorso

  @override
  void initState() {
    super.initState();
    _fetchPois();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // La key MapTiler è ristretta per User-Agent (deve contenere
      // "TrailShareApp", vedi ApiKeys). Il WebView di default manda lo
      // UA del browser → MapTiler risponde 403 su style/tiles. Settiamo
      // uno UA browser-like che contiene il token richiesto, così le
      // richieste MapTiler dal WebView passano la restrizione e MapLibre
      // continua a funzionare (lo UA resta browser-like).
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 '
        '${ApiKeys.mapTilerUserAgent}',
      )
      ..setBackgroundColor(const Color(0xFF0C1116))
      ..addJavaScriptChannel('TSChannel', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (err) {
            // ERR_FAILED/ERR_ABORTED durante il fly-through sono tile
            // cancellati da MapLibre mentre la camera si muove veloce —
            // innocui e rumorosi. Logghiamo solo gli altri.
            final d = err.description;
            if (d.contains('ERR_FAILED') || d.contains('ERR_ABORTED')) return;
            debugPrint('[Track3D] web resource error: $d');
          },
        ),
      )
      ..loadFlutterAsset('assets/3d/flythrough.html');
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      // Log diagnostico di OGNI messaggio dal WebView 3D.
      debugPrint('[Track3D] msg: $type ${data['message'] ?? ''}');
      switch (type) {
        case 'log':
          // Solo diagnostica (già loggato sopra).
          break;
        case 'bridgeReady':
          // Il bridge JS è pronto: inizializza la mappa con la key.
          _controller.runJavaScript('tsInit(${jsonEncode(ApiKeys.mapTiler)})');
          break;
        case 'ready':
          // Mappa + terrain pronti: carica la traccia.
          if (mounted) setState(() => _ready = true);
          _loadTrack();
          break;
        case 'trackLoaded':
          if (mounted) setState(() => _trackLoaded = true);
          _mapReady = true;
          _sendPois(); // invia gli Spazi Pro se già caricati
          break;
        case 'progress':
          final t = (data['t'] as num?)?.toDouble() ?? 0;
          final d = (data['dist'] as num?)?.toDouble();
          final e = (data['ele'] as num?)?.toDouble();
          if (mounted) {
            setState(() {
              _progress = t;
              if (d != null) _distM = d;
              if (e != null) _eleM = e;
            });
          }
          break;
        case 'segment':
          final name = data['name'] as String?;
          if (name != null && name.isNotEmpty) _showSegmentBanner(name);
          break;
        case 'poi':
          final name = data['name'] as String?;
          if (name != null && name.isNotEmpty) _showPoiBanner(name);
          break;
        case 'playing':
          if (mounted) setState(() => _playing = true);
          break;
        case 'paused':
        case 'reset':
          if (mounted) {
            setState(() {
              _playing = false;
              if (type == 'reset') _progress = 0;
            });
          }
          break;
        case 'ended':
          if (mounted) {
            setState(() {
              _playing = false;
              _progress = 1;
            });
          }
          break;
        case 'error':
          if (mounted) {
            setState(() => _error = data['message'] as String? ?? 'Errore 3D');
          }
          break;
      }
    } catch (e) {
      debugPrint('[Track3D] msg parse error: $e — ${message.message}');
    }
  }

  /// Cerca gli Spazi Pro vicini al percorso e li manda al viewer 3D.
  /// Filtra ai soli business entro ~350m da un punto della traccia
  /// (quelli realmente lungo il percorso, non tutta l'area).
  Future<void> _fetchPois() async {
    try {
      final pts = widget.segments.expand((s) => s).toList();
      if (pts.length < 2) return;
      double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
      for (final p in pts) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final cLat = (minLat + maxLat) / 2, cLng = (minLng + maxLng) / 2;
      const dist = Distance();
      final radiusKm = (dist.as(LengthUnit.Kilometer, LatLng(cLat, cLng),
                  LatLng(maxLat, maxLng)) +
              2)
          .clamp(2.0, 60.0);
      final businesses = await BusinessRepository().getNearby(
        lat: cLat,
        lng: cLng,
        radiusKm: radiusKm,
        limit: 150,
      );
      // Downsample punti per la verifica di vicinanza (perf).
      final step = (pts.length / 400).ceil().clamp(1, 50);
      final sampled = <TrackPoint>[];
      for (var i = 0; i < pts.length; i += step) {
        sampled.add(pts[i]);
      }
      final near = <Map<String, dynamic>>[];
      for (final b in businesses) {
        final bl = LatLng(b.location.lat, b.location.lng);
        for (final p in sampled) {
          if (dist.as(LengthUnit.Meter, bl,
                  LatLng(p.latitude, p.longitude)) <
              400) {
            near.add({
              'name': b.name,
              'lat': b.location.lat,
              'lng': b.location.lng,
            });
            break;
          }
        }
      }
      _pois = near;
      _sendPois();
    } catch (e) {
      debugPrint('[Track3D] poi fetch error: $e');
    }
  }

  void _sendPois() {
    if (!_mapReady || _pois == null || _pois!.isEmpty) return;
    _controller.runJavaScript('tsLoadPois(${jsonEncode(jsonEncode(_pois))})');
  }

  /// Banner temporaneo (~3s) quando il volo raggiunge uno Spazio Pro.
  void _showPoiBanner(String name) {
    if (!mounted) return;
    final seq = ++_poiBannerSeq;
    setState(() => _poiBanner = name);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && seq == _poiBannerSeq) {
        setState(() => _poiBanner = null);
      }
    });
  }

  /// Mostra un banner temporaneo (~3s) col nome della traccia corrente,
  /// usato nei tour quando il volo passa da una tappa all'altra.
  void _showSegmentBanner(String name) {
    if (!mounted) return;
    final seq = ++_segmentBannerSeq;
    setState(() => _segmentBanner = name);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && seq == _segmentBannerSeq) {
        setState(() => _segmentBanner = null);
      }
    });
  }

  void _loadTrack() {
    // Ogni segmento → array di [lng, lat, ele]. La quota (corretta DEM
    // dove disponibile) serve per il display; il volo è terrain-aware.
    final segs = widget.segments
        .where((s) => s.length >= 2)
        .map((s) => s
            .map((p) => [p.longitude, p.latitude, p.elevation ?? 0.0])
            .toList())
        .toList();
    final payload = jsonEncode({
      'segments': segs,
      if (widget.segmentNames != null) 'names': widget.segmentNames,
    });
    _controller.runJavaScript('tsLoadTrack(${jsonEncode(payload)})');
  }

  void _togglePlay() {
    if (_playing) {
      _controller.runJavaScript('tsPause()');
    } else {
      _controller.runJavaScript('tsPlay()');
    }
  }

  void _reset() => _controller.runJavaScript('tsReset()');

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _controller.runJavaScript('tsSetSpeed($s)');
  }

  @override
  Widget build(BuildContext context) {
    final loading = !_ready || !_trackLoaded;
    return Scaffold(
      backgroundColor: const Color(0xFF0C1116),
      body: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),

          // Loader iniziale
          if (loading && _error == null)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Costruisco il terreno 3D…',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),

          // Errore
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.terrain, color: Colors.white38, size: 48),
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),

          // Top bar: chiudi + titolo
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.trackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Banner cambio tappa (tour): nome traccia corrente.
          if (_segmentBanner != null)
            Positioned(
              top: 64,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    key: ValueKey(_segmentBanner),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.route,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _segmentBanner!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Banner Spazio Pro raggiunto.
          if (_poiBanner != null)
            Positioned(
              top: _segmentBanner != null ? 108 : 64,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    key: ValueKey('poi_$_poiBanner'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6D4AC4).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cabin, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _poiBanner!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Controlli in basso (solo quando pronta)
          if (!loading && _error == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(child: _buildControls()),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Riga info: distanza dalla partenza + quota (live).
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
            child: Row(
              children: [
                _InfoStat(
                  icon: Icons.straighten,
                  value: _distM < 1000
                      ? '${_distM.round()} m'
                      : '${(_distM / 1000).toStringAsFixed(1)} km',
                  label: 'Distanza',
                ),
                const SizedBox(width: 18),
                _InfoStat(
                  icon: Icons.terrain,
                  value: '${_eleM.round()} m',
                  label: 'Quota',
                ),
              ],
            ),
          ),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 4,
              backgroundColor: Colors.white24,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: Colors.white,
                  size: 40,
                ),
                onPressed: _togglePlay,
              ),
              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white70),
                onPressed: _reset,
              ),
              const Spacer(),
              // Velocità — pill con contrasto netto attivo/inattivo.
              for (final s in const [0.5, 1.0, 2.0])
                _SpeedPill(
                  label: '${s == s.toInt() ? s.toInt() : s}×',
                  selected: _speed == s,
                  onTap: () => _setSpeed(s),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Trascina per ruotare · pizzica per inclinare',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Statistica live (distanza/quota) nella barra controlli 3D.
class _InfoStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _InfoStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}

/// Pill velocità con contrasto netto: attivo = primario pieno, inattivo
/// = sfondo scuro semi-trasparente con testo bianco leggibile.
class _SpeedPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SpeedPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? AppColors.primary : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.30),
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
