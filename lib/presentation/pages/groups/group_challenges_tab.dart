import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/groups_repository.dart';
import 'create_challenge_page.dart';

class GroupChallengesTab extends StatefulWidget {
  final String groupId;
  final bool isAdmin;

  const GroupChallengesTab({
    super.key,
    required this.groupId,
    this.isAdmin = false,
  });

  @override
  State<GroupChallengesTab> createState() => _GroupChallengesTabState();
}

class _GroupChallengesTabState extends State<GroupChallengesTab> {
  final _repo = GroupsRepository();
  List<GroupChallenge> _challenges = [];
  bool _isLoading = true;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _loadChallenges();
  }

  Future<void> _loadChallenges() async {
    setState(() => _isLoading = true);
    final challenges = await _repo.getChallenges(widget.groupId, activeOnly: !_showAll);
    if (mounted) {
      setState(() {
        _challenges = challenges;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => CreateChallengePage(groupId: widget.groupId),
            ),
          );
          if (created == true) _loadChallenges();
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        mini: true,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Attive'),
                  selected: !_showAll,
                  onSelected: (value) {
                    setState(() => _showAll = false);
                    _loadChallenges();
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Tutte'),
                  selected: _showAll,
                  onSelected: (value) {
                    setState(() => _showAll = true);
                    _loadChallenges();
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _challenges.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadChallenges,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _challenges.length,
                          itemBuilder: (context, index) => _buildChallengeCard(_challenges[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Nessuna sfida', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Lancia una sfida al gruppo!', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildChallengeCard(GroupChallenge challenge) {
    final daysLeft = challenge.endDate.difference(DateTime.now()).inDays;
    final isActive = challenge.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showStandings(challenge),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(challenge.typeIcon, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          challenge.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${challenge.typeLabel} • Obiettivo: ${challenge.targetFormatted}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: daysLeft <= 2
                            ? AppColors.danger.withOpacity(0.1)
                            : AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        daysLeft == 0 ? 'Ultimo giorno!' : '$daysLeft giorni',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: daysLeft <= 2 ? AppColors.danger : AppColors.success,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Conclusa', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Barra temporale
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _calculateTimeProgress(challenge),
                  minHeight: 6,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isActive ? AppColors.primary : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Creata da ${challenge.createdByName}',
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _calculateTimeProgress(GroupChallenge challenge) {
    final total = challenge.endDate.difference(challenge.startDate).inSeconds;
    if (total <= 0) return 1.0;
    final elapsed = DateTime.now().difference(challenge.startDate).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  Future<void> _showStandings(GroupChallenge challenge) async {
    final standings = await _repo.getChallengeStandings(widget.groupId, challenge.id);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${challenge.typeIcon} ${challenge.title}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Obiettivo: ${challenge.targetFormatted}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: standings.isEmpty
                  ? const Center(child: Text('Nessun partecipante ancora'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: standings.length,
                      itemBuilder: (context, index) {
                        final s = standings[index];
                        final progress = (s.value / challenge.target).clamp(0.0, 1.0);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: index == 0
                                ? AppColors.warning
                                : AppColors.primary.withOpacity(0.1),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: index == 0 ? Colors.white : AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(s.username),
                          subtitle: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progress >= 1.0 ? AppColors.success : AppColors.primary,
                              ),
                            ),
                          ),
                          trailing: Text(
                            _formatValue(s.value, challenge.type),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatValue(double value, String type) {
    switch (type) {
      case 'distance': return '${(value / 1000).toStringAsFixed(1)} km';
      case 'elevation': return '${value.toStringAsFixed(0)} m';
      case 'tracks': return '${value.toStringAsFixed(0)}';
      case 'streak': return '${value.toStringAsFixed(0)} gg';
      default: return value.toString();
    }
  }
}