import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/leaderboard_repository.dart';

/// Pagina Classifica Settimanale
/// 
/// Mostra la classifica tra l'utente e le persone che segue,
/// basata sulle attività della settimana corrente.
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  final LeaderboardRepository _repository = LeaderboardRepository();

  LeaderboardData? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Prova prima la versione precalcolata, poi fallback al calcolo real-time
      final data = await _repository.getPrecomputedLeaderboard();
      
      if (mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Errore caricamento classifica';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classifica Settimanale'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeaderboard,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return _buildLoginRequired();
    }

    if (_isLoading) {
      return _buildLoading();
    }

    if (_error != null) {
      return _buildError();
    }

    if (_data == null || _data!.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadLeaderboard,
      child: Column(
        children: [
          // Header con posizione utente
          if (_data!.currentUserRank != null) _buildUserRankHeader(),
          
          // Lista classifica
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _data!.entries.length,
              itemBuilder: (context, index) {
                final entry = _data!.entries[index];
                final isCurrentUser = entry.userId == user.uid;
                return _LeaderboardItem(
                  entry: entry,
                  isCurrentUser: isCurrentUser,
                  onTap: () => _openUserProfile(entry),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRankHeader() {
    final rank = _data!.currentUserRank!;
    final total = _data!.totalParticipants;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Medaglia/Posizione
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: rank <= 3
                  ? Icon(
                      _getMedalIcon(rank),
                      color: _getMedalColor(rank),
                      size: 32,
                    )
                  : Text(
                      '#$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
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
                const Text(
                  'La tua posizione',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rank == 1
                      ? '🏆 Sei in testa!'
                      : 'Posizione $rank di $total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Icona motivazionale
          if (rank <= 3)
            const Icon(Icons.emoji_events, color: Colors.amber, size: 32),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) => _buildSkeletonItem(),
    );
  }

  Widget _buildSkeletonItem() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey[300],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 16,
                  width: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 12,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
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
            Icon(Icons.leaderboard_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text(
              'Nessuna attività questa settimana',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Completa una traccia per apparire in classifica.\nSegui altri utenti per competere con loro!',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.directions_walk),
              label: const Text('Inizia un\'escursione'),
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

  Widget _buildLoginRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text(
              'Accedi per vedere la classifica',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Competi con gli amici e scala la classifica settimanale!',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadLeaderboard,
            child: const Text('Riprova'),
          ),
        ],
      ),
    );
  }

  IconData _getMedalIcon(int rank) {
    switch (rank) {
      case 1:
        return Icons.emoji_events;
      case 2:
        return Icons.emoji_events;
      case 3:
        return Icons.emoji_events;
      default:
        return Icons.circle;
    }
  }

  Color _getMedalColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber;
      case 2:
        return Colors.grey[400]!;
      case 3:
        return Colors.brown[300]!;
      default:
        return Colors.grey;
    }
  }

  void _openUserProfile(LeaderboardEntry entry) {
    // TODO: Navigare al profilo pubblico dell'utente
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Profilo di ${entry.username}')),
    );
  }
}

/// Widget singolo item della classifica
class _LeaderboardItem extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final VoidCallback? onTap;

  const _LeaderboardItem({
    required this.entry,
    required this.isCurrentUser,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrentUser 
            ? AppColors.primary.withOpacity(0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentUser 
              ? AppColors.primary.withOpacity(0.3)
              : Colors.grey[200]!,
          width: isCurrentUser ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Rank
                SizedBox(
                  width: 32,
                  child: _buildRankBadge(),
                ),
                const SizedBox(width: 12),
                
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: entry.avatarUrl != null 
                      ? NetworkImage(entry.avatarUrl!)
                      : null,
                  child: entry.avatarUrl == null
                      ? Text(
                          entry.initial,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                
                // Nome e XP
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.username,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isCurrentUser 
                                    ? AppColors.primary 
                                    : AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrentUser) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'TU',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.weeklyXp} XP questa settimana',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Stats
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      entry.distanceFormatted,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '+${entry.elevationFormatted}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRankBadge() {
    if (entry.rank <= 3) {
      return Icon(
        Icons.emoji_events,
        color: _getRankColor(),
        size: 28,
      );
    }
    
    return Text(
      '${entry.rank}',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.grey[600],
      ),
      textAlign: TextAlign.center,
    );
  }

  Color _getRankColor() {
    switch (entry.rank) {
      case 1:
        return Colors.amber;
      case 2:
        return Colors.grey[400]!;
      case 3:
        return Colors.brown[300]!;
      default:
        return Colors.grey;
    }
  }
}
