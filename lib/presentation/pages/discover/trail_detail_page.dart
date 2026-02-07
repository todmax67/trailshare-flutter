import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/gpx_service.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/public_trails_repository.dart';
import '../../../presentation/widgets/interactive_track_map.dart';
import '../../../presentation/widgets/track_charts_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io' show Platform;
import 'trail_follow_page.dart';

class TrailDetailPage extends StatefulWidget {
  final PublicTrail trail;

  const TrailDetailPage({super.key, required this.trail});

  @override
  State<TrailDetailPage> createState() => _TrailDetailPageState();
}

class _TrailDetailPageState extends State<TrailDetailPage> {
  final GpxService _gpxService = GpxService();
  final PublicTrailsRepository _trailsRepo = PublicTrailsRepository();
  bool _isExporting = false;
  bool _isDeleting = false;

  /// Punti completi con elevazione (caricati da Firebase)
  List<TrackPoint>? _fullPoints;
  bool _isLoadingFull = true;

  /// Indice punto selezionato (sync mappa↔grafico)
  int? _selectedPointIndex;

  /// Check admin (stessa lista di settings_page.dart)
  bool get _isAdmin {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    const adminEmails = [
      'admin@trailshare.app',
      'todde.massimiliano@gmail.com',
    ];
    return adminEmails.contains(user.email?.toLowerCase());
  }

  @override
  void initState() {
    super.initState();
    _loadFullGeometry();
    debugPrint('[TrailDetail] isAdmin: $_isAdmin, email: ${FirebaseAuth.instance.currentUser?.email}');
  }

  /// Carica geometria completa dal database (790 punti con elevazione)
  Future<void> _loadFullGeometry() async {
    try {
      final points = await _trailsRepo.getFullGeometry(widget.trail.id);
      if (mounted) {
        setState(() {
          _fullPoints = points;
          _isLoadingFull = false;
        });
      }
    } catch (e) {
      debugPrint('[TrailDetail] Errore caricamento geometria: $e');
      if (mounted) setState(() => _isLoadingFull = false);
    }
  }

  /// Punti da usare: completi se disponibili, altrimenti semplificati
  List<TrackPoint> get _displayPoints => _fullPoints ?? widget.trail.points;

  /// Verifica se ci sono dati di elevazione
  bool get _hasElevationData => _displayPoints.any((p) => p.elevation != null);

  @override
  Widget build(BuildContext context) {
    final trail = widget.trail;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar con mappa
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            actions: [
              // 🗑 Pulsante elimina (solo admin)
              if (_isAdmin)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.85),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isDeleting
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.delete_forever, color: Colors.white),
                    tooltip: 'Elimina sentiero (Admin)',
                    onPressed: _isDeleting ? null : _confirmDeleteTrail,
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                trail.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
              background: _buildMap(),
            ),
          ),

          // Contenuto
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  _buildInfoCard(),
                  
                  const SizedBox(height: 16),
                  
                  // Stats principali
                  _buildMainStats(),
                  
                  const SizedBox(height: 16),
                  
                  // Grafici (elevazione, velocità, combinato) con sync mappa
                  if (_displayPoints.length > 1) ...[
                    TrackChartsWidget(
                      points: _displayPoints,
                      height: 180,
                      onPointTap: (index, distance) {
                        setState(() => _selectedPointIndex = index);
                      },
                    ),
                    if (_isLoadingFull)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Caricamento traccia completa...',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                  
                  const SizedBox(height: 16),
                  
                  // Dettagli
                  _buildDetails(),

                  const SizedBox(height: 24),

                  // Azioni
                  _buildActions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_displayPoints.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Center(child: Text('Nessun dato GPS')),
      );
    }

    // Crea un Track per abilitare TrackMapPage in fullscreen
    // (con grafico elevazione, scorrimento, colori pendenza)
    final track = Track(
      id: widget.trail.id,
      name: widget.trail.displayName,
      points: _displayPoints,
      activityType: ActivityType.trekking,
      createdAt: DateTime.now(),
      stats: TrackStats(
        distance: widget.trail.length?.toDouble() ?? 0,
        elevationGain: widget.trail.elevationGain ?? 0,
      ),
    );

    return InteractiveTrackMap(
      points: _displayPoints,
      height: 300,
      title: widget.trail.displayName,
      showUserLocation: true,
      highlightedPointIndex: _selectedPointIndex,
      onPointTap: (index) {
        setState(() => _selectedPointIndex = index);
      },
      track: track, // ⭐ Abilita TrackMapPage fullscreen con grafico elevazione
    );
  }

  Widget _buildInfoCard() {
    final trail = widget.trail;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icona difficoltà
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  trail.difficultyIcon,
                  style: const TextStyle(fontSize: 32),
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          trail.difficultyName,
                          style: const TextStyle(
                            color: AppColors.info,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (trail.networkName.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          trail.networkName,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (trail.operator != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.business, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          trail.operator!,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStats() {
    final trail = widget.trail;
    
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.straighten,
            value: trail.length != null 
                ? '${trail.lengthKm.toStringAsFixed(1)}' 
                : '--',
            unit: 'km',
            label: 'Lunghezza',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up,
            value: trail.elevationGain != null 
                ? '+${trail.elevationGain!.toStringAsFixed(0)}' 
                : '--',
            unit: 'm',
            label: 'Dislivello',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.location_on,
            value: '${_displayPoints.length}',
            unit: _isLoadingFull ? '...' : '',
            label: 'Punti GPS',
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    final trail = widget.trail;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informazioni',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(height: 24),
            if (trail.ref != null)
              _buildDetailRow(Icons.tag, 'Numero sentiero', trail.ref!),
            _buildDetailRow(Icons.terrain, 'Difficoltà', trail.difficultyName),
            if (trail.operator != null)
              _buildDetailRow(Icons.business, 'Gestore', trail.operator!),
            if (trail.networkName.isNotEmpty)
              _buildDetailRow(Icons.hub, 'Rete', trail.networkName),
            if (trail.region != null)
              _buildDetailRow(Icons.map, 'Regione', trail.region!),
            _buildDetailRow(Icons.source, 'Fonte', 'OpenStreetMap'),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        // ⭐ Pulsante principale: Segui la traccia
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _displayPoints.length > 1 ? _followTrail : null,
            icon: const Icon(Icons.explore),
            label: const Text('Segui la traccia'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Scarica GPX
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isExporting ? null : _exportGpx,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download),
            label: Text(_isExporting ? 'Esportazione...' : 'Scarica GPX'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Naviga al punto di partenza
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _displayPoints.isNotEmpty ? _navigateToStart : null,
            icon: const Icon(Icons.navigation),
            label: const Text('Naviga al punto di partenza'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  /// 🗑 Conferma eliminazione sentiero (solo admin)
  Future<void> _confirmDeleteTrail() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: AppColors.danger),
            SizedBox(width: 8),
            Text('Elimina sentiero'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stai per eliminare definitivamente:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('"${widget.trail.displayName}"'),
            const SizedBox(height: 4),
            Text('ID: ${widget.trail.id}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            const Text(
              'Questa azione è irreversibile e rimuoverà il sentiero dalla mappa per tutti gli utenti.',
              style: TextStyle(color: AppColors.danger),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Elimina'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _deleteTrail();
    }
  }

  Future<void> _deleteTrail() async {
    setState(() => _isDeleting = true);

    try {
      await FirebaseFirestore.instance
          .collection('public_trails')
          .doc(widget.trail.id)
          .delete();

      debugPrint('[AdminDelete] ✅ Sentiero eliminato: ${widget.trail.id} - ${widget.trail.displayName}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${widget.trail.displayName}" eliminato'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true); // true = sentiero eliminato (per refresh lista)
      }
    } catch (e) {
      debugPrint('[AdminDelete] ❌ Errore: $e');
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore eliminazione: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  /// Apre la pagina "Segui la traccia" con navigazione GPS in tempo reale
  void _followTrail() {
    if (_displayPoints.length <= 1) return;

    // Se la geometria completa non è ancora caricata, avvisa
    if (_isLoadingFull) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caricamento traccia in corso, attendi...')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrailFollowPage(
          trailPoints: _displayPoints,
          trailName: widget.trail.displayName,
          totalDistance: widget.trail.length?.toDouble(),
          totalElevationGain: widget.trail.elevationGain,
        ),
      ),
    );
  }

  /// Apre l'app di navigazione verso il punto di partenza del sentiero
  Future<void> _navigateToStart() async {
    if (_displayPoints.isEmpty) return;

    final start = _displayPoints.first;
    final lat = start.latitude;
    final lng = start.longitude;
    final label = Uri.encodeComponent(widget.trail.displayName);

    Uri uri;
    if (Platform.isIOS) {
      // Apple Maps con fallback a Google Maps
      uri = Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=d&t=m');
    } else {
      // Google Maps navigation
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: URL generico Google Maps (funziona ovunque)
        final fallback = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossibile aprire la navigazione: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _exportGpx() async {
    if (_displayPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun punto GPS da esportare')),
      );
      return;
    }

    if (_isLoadingFull) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caricamento in corso, riprova tra un momento...')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final trail = widget.trail;
      final track = Track(
        id: trail.id,
        name: trail.displayName,
        description: 'Sentiero: ${trail.displayName}',
        points: _displayPoints,
        activityType: ActivityType.trekking,
        createdAt: DateTime.now(),
        stats: const TrackStats(),
      );
      final filePath = await _gpxService.saveGpxToFile(track);
      
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: widget.trail.displayName,
        text: 'Sentiero GPX: ${widget.trail.displayName}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ GPX esportato!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      fontSize: 12,
                      color: color.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
