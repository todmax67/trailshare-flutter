import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/gamification_service.dart';

/// Pagina Badge
class BadgesPage extends StatefulWidget {
  const BadgesPage({super.key});

  @override
  State<BadgesPage> createState() => _BadgesPageState();
}

class _BadgesPageState extends State<BadgesPage> with SingleTickerProviderStateMixin {
  final GamificationService _gamification = GamificationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late TabController _tabController;
  List<UnlockedBadge> _unlockedBadges = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBadges();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBadges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // ⭐ STEP 1: Calcola totali reali dalle tracce utente
      final tracksSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('tracks')
          .get();

      double totalDistance = 0;
      double totalElevation = 0;
      int totalTracks = tracksSnapshot.docs.length;

      for (final doc in tracksSnapshot.docs) {
        final data = doc.data();
        totalDistance += (data['distance'] as num?)?.toDouble() ?? 0;
        totalElevation += (data['elevationGain'] as num?)?.toDouble() ?? 0;
      }

      print('[BadgesPage] Totali: $totalTracks tracce, ${totalDistance.toStringAsFixed(0)}m distanza, +${totalElevation.toStringAsFixed(0)}m dislivello');

      // ⭐ STEP 2: Ottieni followers count dal profilo
      int followersCount = 0;
      int cheersReceived = 0;
      
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();

      if (profileDoc.exists) {
        final profileData = profileDoc.data()!;
        final followers = profileData['followers'] as List?;
        followersCount = followers?.length ?? 0;
      }

      // ⭐ STEP 3: Conta cheers ricevuti sulle tracce pubblicate dell'utente
      final publishedSnapshot = await _firestore
          .collection('published_tracks')
          .where('originalOwnerId', isEqualTo: user.uid)
          .get();

      for (final doc in publishedSnapshot.docs) {
        final data = doc.data();
        // Gestisce entrambi i nomi campo (cheerCount da publish, cheersCount da update)
        final c1 = (data['cheerCount'] as num?)?.toInt() ?? 0;
        final c2 = (data['cheersCount'] as num?)?.toInt() ?? 0;
        cheersReceived += c1 > c2 ? c1 : c2; // Prende il valore più alto
      }

      print('[BadgesPage] Social: $followersCount followers, $cheersReceived cheers ricevuti');

      // ⭐ STEP 4: Controlla e sblocca badge maturati
      // (currentStreak = 0 per ora, richiede calcolo separato)
      final newBadges = await _gamification.checkAndUnlockBadges(
        totalDistance: totalDistance,
        totalElevation: totalElevation,
        totalTracks: totalTracks,
        followersCount: followersCount,
        cheersReceived: cheersReceived,
        currentStreak: 0, // TODO: calcolare streak giorni consecutivi
      );

      if (newBadges.isNotEmpty) {
        print('[BadgesPage] 🎉 Nuovi badge sbloccati: ${newBadges.map((b) => b.name).join(', ')}');
      }

      // ⭐ STEP 5: Ricarica badge aggiornati
      final badges = await _gamification.getUnlockedBadges(user.uid);

      if (mounted) {
        setState(() {
          _unlockedBadges = badges;
          _isLoading = false;
        });

        // Mostra dialog per nuovi badge sbloccati
        for (final badge in newBadges) {
          if (mounted) {
            await _showBadgeUnlockedDialog(badge);
          }
        }
      }
    } catch (e) {
      print('[BadgesPage] Errore: $e');
      // Fallback: carica solo badge esistenti
      final badges = await _gamification.getUnlockedBadges(user.uid);
      if (mounted) {
        setState(() {
          _unlockedBadges = badges;
          _isLoading = false;
        });
      }
    }
  }

  /// Mostra dialog per badge appena sbloccato
  Future<void> _showBadgeUnlockedDialog(GameBadge badge) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎊', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            const Text(
              'Nuovo Badge!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(badge.icon, style: const TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  Text(
                    badge.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    badge.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fantastico!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Badge'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: 'Sbloccati (${_unlockedBadges.length})'),
            Tab(text: 'Tutti (${GamificationService.availableBadges.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUnlockedTab(),
                _buildAllBadgesTab(),
              ],
            ),
    );
  }

  Widget _buildUnlockedTab() {
    if (_unlockedBadges.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _unlockedBadges.length,
      itemBuilder: (context, index) {
        final unlocked = _unlockedBadges[index];
        return _BadgeCard(
          badge: unlocked.badge,
          isUnlocked: true,
          unlockedAt: unlocked.unlockedAt,
        );
      },
    );
  }

  Widget _buildAllBadgesTab() {
    final unlockedIds = _unlockedBadges.map((b) => b.badge.id).toSet();
    final allBadges = GamificationService.availableBadges;

    final grouped = <GameBadgeCategory, List<GameBadge>>{};
    for (final badge in allBadges) {
      grouped.putIfAbsent(badge.category, () => []).add(badge);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final category in GameBadgeCategory.values)
          if (grouped.containsKey(category)) ...[
            _buildCategoryHeader(category),
            ...grouped[category]!.map((badge) => _BadgeCard(
              badge: badge,
              isUnlocked: unlockedIds.contains(badge.id),
            )),
            const SizedBox(height: 16),
          ],
      ],
    );
  }

  Widget _buildCategoryHeader(GameBadgeCategory category) {
    String title;
    IconData icon;

    switch (category) {
      case GameBadgeCategory.milestone:
        title = 'Traguardi';
        icon = Icons.flag;
        break;
      case GameBadgeCategory.distance:
        title = 'Distanza';
        icon = Icons.straighten;
        break;
      case GameBadgeCategory.elevation:
        title = 'Dislivello';
        icon = Icons.terrain;
        break;
      case GameBadgeCategory.social:
        title = 'Social';
        icon = Icons.people;
        break;
      case GameBadgeCategory.streak:
        title = 'Costanza';
        icon = Icons.local_fire_department;
        break;
      case GameBadgeCategory.challenge:
        title = 'Sfide';
        icon = Icons.emoji_events;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏅', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'Nessun badge ancora',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Completa tracce e attività per sbloccare badge!',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _tabController.animateTo(1);
              },
              icon: const Icon(Icons.visibility),
              label: const Text('Vedi tutti i badge'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final GameBadge badge;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const _BadgeCard({
    required this.badge,
    required this.isUnlocked,
    this.unlockedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUnlocked ? Colors.white : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnlocked 
              ? AppColors.primary.withOpacity(0.3)
              : Colors.grey[300]!,
        ),
        boxShadow: isUnlocked
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.1),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isUnlocked 
                  ? AppColors.primary.withOpacity(0.1)
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                badge.icon,
                style: TextStyle(
                  fontSize: 24,
                  color: isUnlocked ? null : Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isUnlocked ? AppColors.textPrimary : Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  badge.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isUnlocked ? AppColors.textSecondary : Colors.grey[400],
                  ),
                ),
                if (badge.requirement != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      badge.requirement!,
                      style: TextStyle(
                        fontSize: 11,
                        color: isUnlocked ? AppColors.primary : Colors.grey[400],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (unlockedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Sbloccato il ${unlockedAt!.day}/${unlockedAt!.month}/${unlockedAt!.year}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isUnlocked)
            const Icon(Icons.check_circle, color: AppColors.success, size: 24)
          else
            Icon(Icons.lock_outline, color: Colors.grey[400], size: 24),
        ],
      ),
    );
  }
}
