import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/track_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TrackRepository _repository = TrackRepository();
  final user = FirebaseAuth.instance.currentUser;
  
  bool _isLoading = true;
  ProfileStats _stats = const ProfileStats();

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    
    try {
      final tracks = await _repository.getMyTracks();
      final stats = ProfileStats.fromTracks(tracks);
      
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header utente
              _buildUserHeader(),
              
              const SizedBox(height: 24),
              
              // Stats principali
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                )
              else ...[
                _buildMainStats(),
                
                const SizedBox(height: 16),
                
                // Stats dettagliate
                _buildDetailedStats(),
                
                const SizedBox(height: 16),
                
                // Statistiche per attività
                if (_stats.tracksByActivity.isNotEmpty)
                  _buildActivityBreakdown(),
              ],
              
              const SizedBox(height: 24),
              
              // Info app
              _buildAppInfo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserHeader() {
    final email = user?.email ?? 'Utente';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'U';
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        user?.emailVerified == true 
                            ? Icons.verified 
                            : Icons.warning_amber,
                        size: 14,
                        color: user?.emailVerified == true 
                            ? AppColors.success 
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        user?.emailVerified == true 
                            ? 'Email verificata' 
                            : 'Email non verificata',
                        style: TextStyle(
                          fontSize: 12,
                          color: user?.emailVerified == true 
                              ? AppColors.success 
                              : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Membro dal ${_formatMemberDate()}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
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

  Widget _buildMainStats() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.route,
            value: '${_stats.totalTracks}',
            label: 'Tracce',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.straighten,
            value: '${_stats.totalDistanceKm.toStringAsFixed(0)}',
            label: 'km totali',
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.terrain,
            value: '${(_stats.totalElevationGain / 1000).toStringAsFixed(1)}k',
            label: 'm D+',
            color: AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedStats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, size: 20, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'Statistiche Totali',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildStatRow(Icons.straighten, 'Distanza totale', '${_stats.totalDistanceKm.toStringAsFixed(2)} km'),
            _buildStatRow(Icons.trending_up, 'Dislivello positivo', '+${_stats.totalElevationGain.toStringAsFixed(0)} m'),
            _buildStatRow(Icons.trending_down, 'Dislivello negativo', '-${_stats.totalElevationLoss.toStringAsFixed(0)} m'),
            _buildStatRow(Icons.timer, 'Tempo totale', _formatTotalDuration(_stats.totalDuration)),
            _buildStatRow(Icons.speed, 'Velocità media', '${_stats.avgSpeed.toStringAsFixed(1)} km/h'),
            _buildStatRow(Icons.star, 'Traccia più lunga', '${_stats.longestTrackKm.toStringAsFixed(2)} km'),
            _buildStatRow(Icons.landscape, 'Quota max raggiunta', '${_stats.maxElevation.toStringAsFixed(0)} m'),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityBreakdown() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.pie_chart, size: 20, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'Per Attività',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(height: 24),
            ..._stats.tracksByActivity.entries.map((entry) {
              final activity = entry.key;
              final count = entry.value;
              final percentage = (_stats.totalTracks > 0) 
                  ? (count / _stats.totalTracks * 100) 
                  : 0.0;
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text(activity.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: percentage / 100,
                              backgroundColor: AppColors.border,
                              valueColor: AlwaysStoppedAnimation(AppColors.primary),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildAppInfo() {
    return Card(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.terrain, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'TrailShare',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Versione Flutter 1.0.0',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              'Traccia le tue avventure',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMemberDate() {
    final creationTime = user?.metadata.creationTime;
    if (creationTime == null) return 'N/A';
    
    final months = ['Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu',
                    'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'];
    return '${months[creationTime.month - 1]} ${creationTime.year}';
  }

  String _formatTotalDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Vuoi uscire dall\'account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
            },
            child: const Text('Esci', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

/// Widget per stat card
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}


/// Statistiche profilo calcolate dalle tracce
class ProfileStats {
  final int totalTracks;
  final double totalDistance;
  final double totalElevationGain;
  final double totalElevationLoss;
  final Duration totalDuration;
  final double longestTrack;
  final double maxElevation;
  final Map<ActivityType, int> tracksByActivity;

  const ProfileStats({
    this.totalTracks = 0,
    this.totalDistance = 0,
    this.totalElevationGain = 0,
    this.totalElevationLoss = 0,
    this.totalDuration = Duration.zero,
    this.longestTrack = 0,
    this.maxElevation = 0,
    this.tracksByActivity = const {},
  });

  double get totalDistanceKm => totalDistance / 1000;
  double get longestTrackKm => longestTrack / 1000;
  
  double get avgSpeed {
    if (totalDuration.inSeconds == 0) return 0;
    return (totalDistance / totalDuration.inSeconds) * 3.6; // km/h
  }

  factory ProfileStats.fromTracks(List<Track> tracks) {
    if (tracks.isEmpty) return const ProfileStats();

    double totalDistance = 0;
    double totalElevationGain = 0;
    double totalElevationLoss = 0;
    Duration totalDuration = Duration.zero;
    double longestTrack = 0;
    double maxElevation = 0;
    final tracksByActivity = <ActivityType, int>{};

    for (final track in tracks) {
      totalDistance += track.stats.distance;
      totalElevationGain += track.stats.elevationGain;
      totalElevationLoss += track.stats.elevationLoss;
      totalDuration += track.stats.duration;
      
      if (track.stats.distance > longestTrack) {
        longestTrack = track.stats.distance;
      }
      
      if (track.stats.maxElevation > maxElevation) {
        maxElevation = track.stats.maxElevation;
      }
      
      tracksByActivity[track.activityType] = 
          (tracksByActivity[track.activityType] ?? 0) + 1;
    }

    return ProfileStats(
      totalTracks: tracks.length,
      totalDistance: totalDistance,
      totalElevationGain: totalElevationGain,
      totalElevationLoss: totalElevationLoss,
      totalDuration: totalDuration,
      longestTrack: longestTrack,
      maxElevation: maxElevation,
      tracksByActivity: tracksByActivity,
    );
  }
}
