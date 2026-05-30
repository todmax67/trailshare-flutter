import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/api_keys.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';

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
  final List<TrackPoint> points;

  const Track3DPage({
    super.key,
    required this.trackName,
    required this.points,
  });

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
  String? _error;

  @override
  void initState() {
    super.initState();
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
            // Errori di risorse (tile, CDN): non fatali, logghiamo.
            debugPrint('[Track3D] web resource error: ${err.description}');
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
          break;
        case 'progress':
          final t = (data['t'] as num?)?.toDouble() ?? 0;
          if (mounted) setState(() => _progress = t);
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

  void _loadTrack() {
    // GeoJSON-ish: [lng, lat, ele] — la quota (corretta DEM) serve alla
    // camera 3D per posizionarsi sopra il terreno senza finire
    // sottoterra (queryTerrainElevation può essere null se i tile DEM
    // non sono ancora pronti).
    final coords = widget.points
        .map((p) => [p.longitude, p.latitude, p.elevation ?? 0.0])
        .toList(growable: false);
    final payload = jsonEncode({'coordinates': coords});
    // jsonEncode(payload) → string literal JS sicura da passare.
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
              // Velocità
              for (final s in const [0.5, 1.0, 2.0])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    label: Text('${s == s.toInt() ? s.toInt() : s}×'),
                    selected: _speed == s,
                    onSelected: (_) => _setSpeed(s),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _speed == s ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: Colors.white12,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2),
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
