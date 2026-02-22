import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/track.dart';
import '../../core/constants/app_colors.dart';

/// Card grafica per condivisione social (stile Strava)
class ShareCardGenerator {
  /// Mostra la preview della card e permette di condividerla
  static Future<void> showSharePreview({
    required BuildContext context,
    required String name,
    required List<TrackPoint> points,
    required double distanceKm,
    required double elevationGain,
    required String durationFormatted,
    required String activityEmoji,
    String? activityName,
    String? username,
    VoidCallback? onExportGpx,
  }) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SharePreviewSheet(
        name: name,
        points: points,
        distanceKm: distanceKm,
        elevationGain: elevationGain,
        durationFormatted: durationFormatted,
        activityEmoji: activityEmoji,
        activityName: activityName,
        username: username,
        onExportGpx: onExportGpx,
      ),
    );
  }
}

class _SharePreviewSheet extends StatefulWidget {
  final String name;
  final List<TrackPoint> points;
  final double distanceKm;
  final double elevationGain;
  final String durationFormatted;
  final String activityEmoji;
  final String? activityName;
  final String? username;
  final VoidCallback? onExportGpx;

  const _SharePreviewSheet({
    required this.name,
    required this.points,
    required this.distanceKm,
    required this.elevationGain,
    required this.durationFormatted,
    required this.activityEmoji,
    this.activityName,
    this.username,
    this.onExportGpx,
  });

  @override
  State<_SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<_SharePreviewSheet> {
  final GlobalKey _cardKey = GlobalKey();
  int _selectedStyle = 0;
  bool _isSharing = false;

  // Stili disponibili
  static const _styles = [
    _CardStyle(
      name: 'Verde natura',
      gradientColors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
      accentColor: Color(0xFF81C784),
      trackColor: Color(0xFFFFFFFF),
    ),
    _CardStyle(
      name: 'Blu montagna',
      gradientColors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1E88E5)],
      accentColor: Color(0xFF64B5F6),
      trackColor: Color(0xFFFFFFFF),
    ),
    _CardStyle(
      name: 'Arancio tramonto',
      gradientColors: [Color(0xFFE65100), Color(0xFFF57C00), Color(0xFFFFB74D)],
      accentColor: Color(0xFFFFE0B2),
      trackColor: Color(0xFFFFFFFF),
    ),
    _CardStyle(
      name: 'Scuro elegante',
      gradientColors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
      accentColor: Color(0xFF53A8B6),
      trackColor: Color(0xFF53A8B6),
    ),
  ];

  Future<void> _shareCard() async {
    setState(() => _isSharing = true);

    try {
      // Attendi un frame per assicurarsi che il widget sia renderizzato
      await Future.delayed(const Duration(milliseconds: 100));

      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Widget non trovato');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Errore generazione immagine');

      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/trailshare_share.png');
      await file.writeAsBytes(bytes);

      final text = _buildShareText();

      if (mounted) Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
        subject: 'La mia attività su TrailShare',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore condivisione: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  String _buildShareText() {
    final buffer = StringBuffer();
    buffer.writeln('${widget.activityEmoji} ${widget.activityName ?? "Attività"} completata!');
    buffer.writeln('');
    buffer.writeln('📍 ${widget.name}');
    buffer.writeln('📏 ${widget.distanceKm.toStringAsFixed(1)} km');
    if (widget.elevationGain > 0) {
      buffer.writeln('⬆️ +${widget.elevationGain.toStringAsFixed(0)} m');
    }
    if (widget.durationFormatted.isNotEmpty && widget.durationFormatted != '--') {
      buffer.writeln('⏱️ ${widget.durationFormatted}');
    }
    buffer.writeln('');
    buffer.writeln('🗺️ Traccia le tue avventure con TrailShare!');
    buffer.writeln(_getStoreUrl());
    return buffer.toString();
  }

  String _getStoreUrl() {
    if (Platform.isIOS) {
      return '📲 https://apps.apple.com/us/app/trailshare/id6751456265';
    } else {
      return '📲 https://play.google.com/store/apps/details?id=com.trailshare.app';
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _styles[_selectedStyle];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const Text(
              'Condividi attività',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // ═══ CARD PREVIEW ═══
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: RepaintBoundary(
                key: _cardKey,
                child: _buildShareCard(style),
              ),
            ),

            const SizedBox(height: 12),

            // ═══ SELETTORE STILE ═══
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _styles.length,
                itemBuilder: (ctx, index) {
                  final s = _styles[index];
                  final isSelected = index == _selectedStyle;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedStyle = index),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: s.gradientColors),
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected
                            ? Border.all(color: Colors.black, width: 2.5)
                            : null,
                        boxShadow: isSelected
                            ? [BoxShadow(color: s.gradientColors.first.withOpacity(0.4), blurRadius: 8)]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          s.name,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // ═══ BOTTONI ═══
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  // Export GPX
                  if (widget.onExportGpx != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onExportGpx!();
                        },
                        icon: const Icon(Icons.file_download, size: 18),
                        label: const Text('GPX'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  if (widget.onExportGpx != null) const SizedBox(width: 12),

                  // Condividi
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSharing ? null : _shareCard,
                      icon: _isSharing
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, size: 18),
                      label: const Text('Condividi', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// ═══ LA CARD VERA E PROPRIA ═══
  Widget _buildShareCard(_CardStyle style) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: 420,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: style.gradientColors,
          ),
        ),
        child: Stack(
          children: [
            // Pattern decorativo di sfondo
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -20,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),

            // Contenuto
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Header: branding ───
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.asset(
                            'assets/icons/app_icon.png',
                            width: 26,
                            height: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'TrailShare',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      if (widget.username != null)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '@${widget.username}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ─── Mappa ───
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          _buildMiniMap(style),
                          // Overlay gradiente bottom
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 60,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.5),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Nome attività sulla mappa
                          Positioned(
                            bottom: 10,
                            left: 12,
                            right: 12,
                            child: Text(
                              widget.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ─── Statistiche ───
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _buildStat(
                          'Distanza',
                          '${widget.distanceKm.toStringAsFixed(1)} km',
                          style.accentColor,
                        ),
                        _buildStatDivider(),
                        _buildStat(
                          'Dislivello',
                          '+${widget.elevationGain.toStringAsFixed(0)} m',
                          style.accentColor,
                        ),
                        _buildStatDivider(),
                        _buildStat(
                          'Tempo',
                          widget.durationFormatted,
                          style.accentColor,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ─── Footer: tipo attività ───
                  Row(
                    children: [
                      Text(
                        widget.activityEmoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.activityName ?? 'Attività',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'trailshare.app',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color accentColor) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accentColor,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 30,
      color: Colors.white.withOpacity(0.15),
    );
  }

  Widget _buildMiniMap(_CardStyle style) {
    if (widget.points.isEmpty) {
      return Container(
        color: Colors.black26,
        child: const Center(child: Text('Nessun dato GPS', style: TextStyle(color: Colors.white54))),
      );
    }

    final latLngs = widget.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in latLngs) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final maxDiff = (maxLat - minLat) > (maxLng - minLng)
        ? (maxLat - minLat)
        : (maxLng - minLng);
    double zoom = maxDiff > 0.5 ? 10 : maxDiff > 0.2 ? 11 : maxDiff > 0.1 ? 12 : maxDiff > 0.05 ? 13 : 14;

    return AbsorbPointer(
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: zoom,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.trailshare.app',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: latLngs,
                strokeWidth: 4,
                color: style.trackColor,
                borderStrokeWidth: 1.5,
                borderColor: style.trackColor.withOpacity(0.3),
              ),
            ],
          ),
          // Marker start/end
          MarkerLayer(
            markers: [
              Marker(
                point: latLngs.first,
                width: 16,
                height: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
                  ),
                ),
              ),
              Marker(
                point: latLngs.last,
                width: 16,
                height: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardStyle {
  final String name;
  final List<Color> gradientColors;
  final Color accentColor;
  final Color trackColor;

  const _CardStyle({
    required this.name,
    required this.gradientColors,
    required this.accentColor,
    required this.trackColor,
  });
}
