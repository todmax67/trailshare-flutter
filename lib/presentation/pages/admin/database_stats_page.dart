import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';

/// Pagina admin per visualizzare statistiche del database Firestore
class DatabaseStatsPage extends StatefulWidget {
  const DatabaseStatsPage({super.key});

  @override
  State<DatabaseStatsPage> createState() => _DatabaseStatsPageState();
}

class _DatabaseStatsPageState extends State<DatabaseStatsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  String? _error;

  // Conteggi collections
  int _publicTrails = 0;
  int _publishedTracks = 0;
  int _userProfiles = 0;
  int _totalUserTracks = 0;

  // Dettagli sentieri
  int _trailsWithGeohash = 0;
  int _trailsWithElevation = 0;

  // Dettagli community
  int _totalCheers = 0;

  // Utenti attivi (con almeno 1 traccia)
  int _activeUsers = 0;

  // Ultime tracce pubblicate
  List<Map<String, dynamic>> _recentPublished = [];

  // Ultimi utenti registrati
  List<Map<String, dynamic>> _recentUsers = [];

  @override
  void initState() {
    super.initState();
    _loadAllStats();
  }

  Future<void> _loadAllStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _loadCollectionCounts(),
        _loadTrailDetails(),
        _loadCommunityDetails(),
        _loadRecentPublished(),
        _loadRecentUsers(),
      ]);
    } catch (e) {
      debugPrint('[DBStats] Errore: $e');
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCollectionCounts() async {
    // public_trails
    final trailsCount = await _firestore.collection('public_trails').count().get();
    _publicTrails = trailsCount.count ?? 0;

    // published_tracks (community)
    final pubCount = await _firestore.collection('published_tracks').count().get();
    _publishedTracks = pubCount.count ?? 0;

    // user_profiles
    final profilesCount = await _firestore.collection('user_profiles').count().get();
    _userProfiles = profilesCount.count ?? 0;
  }

  Future<void> _loadTrailDetails() async {
    // Sentieri con geohash
    final withGeo = await _firestore
        .collection('public_trails')
        .where('geoHash', isNull: false)
        .count()
        .get();
    _trailsWithGeohash = withGeo.count ?? 0;

    // Sentieri con elevazione (campione)
    final withEle = await _firestore
        .collection('public_trails')
        .where('elevationGain', isGreaterThan: 0)
        .count()
        .get();
    _trailsWithElevation = withEle.count ?? 0;
  }

  Future<void> _loadCommunityDetails() async {
    // Prendi gli ID utenti dai profili
    final profilesSnap = await _firestore
        .collection('user_profiles')
        .get();

    int totalTracks = 0;
    int usersWithTracks = 0;
    int totalCheers = 0;

    // Conta tracce per ogni utente IN PARALLELO (batch da 10 per non sovraccaricare)
    final userIds = profilesSnap.docs.map((d) => d.id).toList();
    for (int i = 0; i < userIds.length; i += 10) {
      final batch = userIds.skip(i).take(10).toList();
      final futures = batch.map((uid) => _firestore
          .collection('users')
          .doc(uid)
          .collection('tracks')
          .count()
          .get());
      
      final results = await Future.wait(futures);
      for (final result in results) {
        final count = result.count ?? 0;
        totalTracks += count;
        if (count > 0) usersWithTracks++;
      }
    }

    // Conta cheers totali dalle tracce pubblicate (solo il campo cheerCount)
    final publishedSnap = await _firestore
        .collection('published_tracks')
        .get();
    for (final doc in publishedSnap.docs) {
      final cheerCount = (doc.data()['cheerCount'] as num?)?.toInt() ?? 0;
      totalCheers += cheerCount;
    }

    _totalUserTracks = totalTracks;
    _activeUsers = usersWithTracks;
    _totalCheers = totalCheers;
  }

  Future<void> _loadRecentPublished() async {
    final snap = await _firestore
        .collection('published_tracks')
        .orderBy('sharedAt', descending: true)
        .limit(5)
        .get();

    _recentPublished = snap.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'] ?? 'Senza nome',
        'owner': data['ownerUsername'] ?? '?',
        'distance': ((data['distance'] as num?)?.toDouble() ?? 0) / 1000,
        'sharedAt': (data['sharedAt'] as Timestamp?)?.toDate(),
        'cheerCount': (data['cheerCount'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }

  Future<void> _loadRecentUsers() async {
    final snap = await _firestore
        .collection('user_profiles')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();

    _recentUsers = snap.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'username': data['username'] ?? data['displayName'] ?? 'Utente',
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
        'followers': (data['followers'] as List?)?.length ?? 0,
        'following': (data['following'] as List?)?.length ?? 0,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiche Database'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadAllStats,
            tooltip: 'Aggiorna',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Caricamento statistiche...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                      const SizedBox(height: 12),
                      Text('Errore: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadAllStats, child: const Text('Riprova')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAllStats,
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══ OVERVIEW GRID ═══
          _buildSectionTitle('📊 Overview'),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _StatCard(
                icon: Icons.hiking,
                label: 'Sentieri Pubblici',
                value: '$_publicTrails',
                color: AppColors.primary,
              ),
              _StatCard(
                icon: Icons.people,
                label: 'Utenti Registrati',
                value: '$_userProfiles',
                color: AppColors.info,
              ),
              _StatCard(
                icon: Icons.route,
                label: 'Tracce Registrate',
                value: '$_totalUserTracks',
                color: AppColors.success,
              ),
              _StatCard(
                icon: Icons.share,
                label: 'Tracce Pubblicate',
                value: '$_publishedTracks',
                color: AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ═══ ENGAGEMENT ═══
          _buildSectionTitle('🔥 Engagement'),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: [
              _StatCard(
                icon: Icons.person_pin,
                label: 'Utenti Attivi',
                value: '$_activeUsers',
                color: AppColors.success,
                subtitle: _userProfiles > 0
                    ? '${(_activeUsers / _userProfiles * 100).toStringAsFixed(0)}%'
                    : null,
              ),
              _StatCard(
                icon: Icons.celebration,
                label: 'Cheers Totali',
                value: '$_totalCheers',
                color: AppColors.warning,
              ),
              _StatCard(
                icon: Icons.calculate,
                label: 'Tracce/Utente',
                value: _activeUsers > 0
                    ? (_totalUserTracks / _activeUsers).toStringAsFixed(1)
                    : '0',
                color: AppColors.info,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ═══ SALUTE DATABASE ═══
          _buildSectionTitle('🏥 Salute Database'),
          const SizedBox(height: 8),
          _buildHealthCard(),
          const SizedBox(height: 24),

          // ═══ ULTIME TRACCE PUBBLICATE ═══
          _buildSectionTitle('📤 Ultime Tracce Pubblicate'),
          const SizedBox(height: 8),
          _buildRecentPublished(),
          const SizedBox(height: 24),

          // ═══ ULTIMI UTENTI REGISTRATI ═══
          _buildSectionTitle('👤 Ultimi Utenti Registrati'),
          const SizedBox(height: 8),
          _buildRecentUsers(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildHealthCard() {
    final geoPct = _publicTrails > 0
        ? (_trailsWithGeohash / _publicTrails * 100)
        : 0.0;
    final elePct = _publicTrails > 0
        ? (_trailsWithElevation / _publicTrails * 100)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _HealthRow(
              label: 'GeoHash Coverage',
              value: '$_trailsWithGeohash / $_publicTrails',
              percentage: geoPct,
              color: geoPct > 90 ? AppColors.success : geoPct > 50 ? AppColors.warning : AppColors.danger,
            ),
            const SizedBox(height: 12),
            _HealthRow(
              label: 'Elevazione Sentieri',
              value: '$_trailsWithElevation / $_publicTrails',
              percentage: elePct,
              color: elePct > 80 ? AppColors.success : elePct > 40 ? AppColors.warning : AppColors.danger,
            ),
            const SizedBox(height: 12),
            _HealthRow(
              label: 'Utenti Attivi',
              value: '$_activeUsers / $_userProfiles',
              percentage: _userProfiles > 0 ? (_activeUsers / _userProfiles * 100) : 0,
              color: AppColors.info,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPublished() {
    if (_recentPublished.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nessuna traccia pubblicata'),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _recentPublished.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final track = _recentPublished[index];
          final date = track['sharedAt'] as DateTime?;
          final dateStr = date != null
              ? '${date.day}/${date.month}/${date.year}'
              : '?';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: const Icon(Icons.route, color: AppColors.primary, size: 20),
            ),
            title: Text(
              track['name'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${track['owner']} • ${(track['distance'] as double).toStringAsFixed(1)} km • $dateStr',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.celebration, size: 14, color: AppColors.warning),
                const SizedBox(width: 4),
                Text('${track['cheerCount']}'),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentUsers() {
    if (_recentUsers.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nessun utente registrato'),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _recentUsers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final user = _recentUsers[index];
          final date = user['createdAt'] as DateTime?;
          final dateStr = date != null
              ? '${date.day}/${date.month}/${date.year}'
              : '?';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.info.withOpacity(0.1),
              child: Text(
                (user['username'] as String).substring(0, 1).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.info),
              ),
            ),
            title: Text(user['username'] as String),
            subtitle: Text(
              'Registrato $dateStr',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Text(
              '${user['followers']} follower',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET AUSILIARI
// ═══════════════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? subtitle;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(fontSize: 11, color: color.withOpacity(0.7)),
              ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  final String label;
  final String value;
  final double percentage;
  final Color color;

  const _HealthRow({
    required this.label,
    required this.value,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(
              '$value (${percentage.toStringAsFixed(0)}%)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percentage / 100).clamp(0.0, 1.0),
            backgroundColor: Colors.grey[200],
            color: color,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
