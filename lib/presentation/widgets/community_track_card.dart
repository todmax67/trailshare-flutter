import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/track.dart';

/// Card per visualizzare una traccia della community
/// 
/// Mostra:
/// - Immagine di anteprima (foto o mappa statica)
/// - Nome traccia e autore
/// - Badge difficoltà
/// - Statistiche (distanza, dislivello, durata)
/// - Conteggio cheers
class CommunityTrackCard extends StatelessWidget {
  final String trackId;
  final String name;
  final String ownerUsername;
  final String activityIcon;
  final double distanceKm;
  final double elevationGain;
  final String durationFormatted;
  final int cheerCount;
  final DateTime? sharedAt;
  final String? difficulty;
  final List<String> photoUrls;
  final List<TrackPoint> points;
  final VoidCallback onTap;

  const CommunityTrackCard({
    super.key,
    required this.trackId,
    required this.name,
    required this.ownerUsername,
    required this.activityIcon,
    required this.distanceKm,
    required this.elevationGain,
    required this.durationFormatted,
    required this.cheerCount,
    this.sharedAt,
    this.difficulty,
    this.photoUrls = const [],
    this.points = const [],
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Immagine di anteprima
            _buildPreviewImage(),
            
            // Contenuto testuale
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titolo e cheers
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'di: $ownerUsername',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Cheers
                      if (cheerCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.favorite,
                                color: AppColors.danger,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$cheerCount',
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Badge difficoltà
                  if (difficulty != null && difficulty!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getDifficultyColor().withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getDifficultyColor().withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        difficulty!.toLowerCase(),
                        style: TextStyle(
                          color: _getDifficultyColor(),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  
                  // Divider
                  Divider(color: Colors.grey.withOpacity(0.3), height: 1),
                  
                  const SizedBox(height: 16),
                  
                  // Statistiche
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatColumn(
                        label: 'Distanza',
                        value: '${distanceKm.toStringAsFixed(2)} km',
                      ),
                      _StatColumn(
                        label: 'Dislivello+',
                        value: '${elevationGain.toStringAsFixed(0)} m',
                      ),
                      _StatColumn(
                        label: 'Durata',
                        value: _formatDuration(),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Pulsante Dettagli
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Dettagli',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Costruisce l'immagine di anteprima
  Widget _buildPreviewImage() {
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Immagine di sfondo
          if (photoUrls.isNotEmpty)
            // Mostra la prima foto disponibile
            Image.network(
              photoUrls.first,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // Fallback alla mappa se l'immagine non carica
                return _buildMapPreview();
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _buildLoadingPlaceholder();
              },
            )
          else
            // Mostra mappa statica se non ci sono foto
            _buildMapPreview(),
          
          // Overlay gradiente per leggibilità
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 60,
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
          
          // Icona attività in alto a sinistra
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                activityIcon,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          
          // Data in basso a destra (se disponibile)
          if (sharedAt != null)
            Positioned(
              bottom: 8,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatDate(sharedAt!),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Mappa statica come fallback
  Widget _buildMapPreview() {
    if (points.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Center(
          child: Icon(
            Icons.map_outlined,
            size: 48,
            color: AppColors.textMuted,
          ),
        ),
      );
    }

    // Calcola bounding box
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    final latLngPoints = <LatLng>[];
    
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
      latLngPoints.add(LatLng(p.latitude, p.longitude));
    }
    
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    
    // Calcola zoom appropriato
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    double zoom = 14.0;
    if (maxDiff > 0.5) zoom = 10;
    else if (maxDiff > 0.2) zoom = 11;
    else if (maxDiff > 0.1) zoom = 12;
    else if (maxDiff > 0.05) zoom = 13;

    return IgnorePointer(
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: zoom,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.trailshare.app',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: latLngPoints,
                strokeWidth: 4,
                color: AppColors.primary,
              ),
            ],
          ),
          // Marker inizio/fine
          if (latLngPoints.length > 1)
            MarkerLayer(
              markers: [
                Marker(
                  point: latLngPoints.first,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
                Marker(
                  point: latLngPoints.last,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      color: AppColors.background,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Color _getDifficultyColor() {
    switch (difficulty?.toLowerCase()) {
      case 'facile':
      case 'easy':
        return AppColors.success;
      case 'medio':
      case 'media':
      case 'medium':
        return AppColors.info;
      case 'difficile':
      case 'hard':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }

  String _formatDuration() {
    if (durationFormatted == '--' || durationFormatted.isEmpty) {
      return '--';
    }
    // Se già formattato come "Xh Ym", converti in HH:MM:SS
    // Altrimenti usa il valore così com'è
    return durationFormatted;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

/// Colonna statistica
class _StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _StatColumn({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}


/// Versione compatta della card (per liste)
class CommunityTrackCardCompact extends StatelessWidget {
  final String trackId;
  final String name;
  final String ownerUsername;
  final String activityIcon;
  final double distanceKm;
  final double elevationGain;
  final String durationFormatted;
  final int cheerCount;
  final DateTime? sharedAt;
  final String? difficulty;
  final String? thumbnailUrl;
  final VoidCallback onTap;

  const CommunityTrackCardCompact({
    super.key,
    required this.trackId,
    required this.name,
    required this.ownerUsername,
    required this.activityIcon,
    required this.distanceKm,
    required this.elevationGain,
    required this.durationFormatted,
    required this.cheerCount,
    this.sharedAt,
    this.difficulty,
    this.thumbnailUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail o icona
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: thumbnailUrl != null
                    ? Image.network(
                        thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(activityIcon, style: const TextStyle(fontSize: 24)),
                        ),
                      )
                    : Center(
                        child: Text(activityIcon, style: const TextStyle(fontSize: 24)),
                      ),
              ),
              const SizedBox(width: 12),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            ownerUsername,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (cheerCount > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.favorite, size: 14, color: AppColors.danger),
                          const SizedBox(width: 2),
                          Text(
                            '$cheerCount',
                            style: const TextStyle(color: AppColors.danger, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                    if (sharedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatDateRelative(sharedAt!),
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Stats
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  if (elevationGain > 0)
                    Text(
                      '+${elevationGain.toStringAsFixed(0)} m',
                      style: const TextStyle(color: AppColors.success, fontSize: 12),
                    ),
                  Text(
                    durationFormatted,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateRelative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) return 'Oggi';
    if (diff.inDays == 1) return 'Ieri';
    if (diff.inDays < 7) return '${diff.inDays} giorni fa';
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return weeks == 1 ? '1 settimana fa' : '$weeks settimane fa';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}
