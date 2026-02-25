import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/services/challenges_service.dart';

/// Pagina Sfide
class ChallengesPage extends StatefulWidget {
  const ChallengesPage({super.key});

  @override
  State<ChallengesPage> createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage>
    with SingleTickerProviderStateMixin {
  final ChallengesService _service = ChallengesService();

  late TabController _tabController;
  List<Challenge> _activeChallenges = [];
  List<Challenge> _myChallenges = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadChallenges();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadChallenges() async {
    setState(() => _isLoading = true);

    final active = await _service.getActiveChallenges();
    final mine = await _service.getMyChallenges();

    if (mounted) {
      setState(() {
        _activeChallenges = active;
        _myChallenges = mine;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.challenges),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: [
            Tab(text: context.l10n.activeTabCount(_activeChallenges.length)),
            Tab(text: context.l10n.myChallengesTabCount(_myChallenges.length)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChallengesList(_activeChallenges, showJoinButton: true),
                _buildChallengesList(_myChallenges, showProgress: true),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        backgroundColor: Theme.of(context).colorScheme.primary,
        icon: const Icon(Icons.add),
        label: Text(context.l10n.createChallengeBtn),
      ),
    );
  }

  Widget _buildChallengesList(
    List<Challenge> challenges, {
    bool showJoinButton = false,
    bool showProgress = false,
  }) {
    if (challenges.isEmpty) {
      return _buildEmptyState(showJoinButton);
    }

    return RefreshIndicator(
      onRefresh: _loadChallenges,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: challenges.length,
        itemBuilder: (context, index) {
          return _ChallengeCard(
            challenge: challenges[index],
            showJoinButton: showJoinButton,
            showProgress: showProgress,
            onJoin: () => _joinChallenge(challenges[index]),
            onTap: () => _showChallengeDetail(challenges[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isActivePage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏆', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              isActivePage ? context.l10n.noActiveChallenges : context.l10n.notInAnyChallenges,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isActivePage
                  ? context.l10n.createFirstChallenge
                  : context.l10n.joinFromActiveTab,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinChallenge(Challenge challenge) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.joinChallengeTitle(challenge.title)),
        content: Text(
          '${context.l10n.goalLabel}: ${challenge.formattedGoal}\n'
          '${context.l10n.deadlineLabel}: ${context.l10n.daysCount(challenge.daysLeft)}\n\n'
          '${context.l10n.joinChallengeConfirm}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text(context.l10n.joinAction),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _service.joinChallenge(challenge.id);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.joinedChallenge),
              backgroundColor: AppColors.success,
            ),
          );
          _loadChallenges();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.joinError),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }
  }

  void _showChallengeDetail(Challenge challenge) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChallengeDetailPage(challenge: challenge),
      ),
    );
  }

  void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CreateChallengeSheet(
        onCreated: () {
          Navigator.pop(context);
          _loadChallenges();
        },
      ),
    );
  }
}

/// Card singola sfida
class _ChallengeCard extends StatefulWidget {
  final Challenge challenge;
  final bool showJoinButton;
  final bool showProgress;
  final VoidCallback onJoin;
  final VoidCallback onTap;

  const _ChallengeCard({
    required this.challenge,
    required this.showJoinButton,
    required this.showProgress,
    required this.onJoin,
    required this.onTap,
  });

  @override
  State<_ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends State<_ChallengeCard> {
  final ChallengesService _service = ChallengesService();
  bool _isParticipating = false;
  double _progress = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadParticipation();
  }

  Future<void> _loadParticipation() async {
    final participating = await _service.isParticipating(widget.challenge.id);
    double progress = 0;
    if (participating) {
      progress = await _service.getUserProgress(widget.challenge.id);
    }

    if (mounted) {
      setState(() {
        _isParticipating = participating;
        _progress = progress;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.challenge;
    final progressPercent = challenge.goal > 0
        ? (_progress / challenge.goal * 100).clamp(0, 100)
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(challenge.icon, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          challenge.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          context.l10n.goalPrefix(challenge.formattedGoal),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: challenge.daysLeft <= 3
                          ? AppColors.danger.withOpacity(0.1)
                          : AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${challenge.daysLeft}g',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: challenge.daysLeft <= 3
                            ? AppColors.danger
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),

              if (challenge.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  challenge.description,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Progress bar (se partecipa)
              if (_loaded && _isParticipating && widget.showProgress) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.yourProgress,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '${challenge.formatProgress(_progress)} / ${challenge.formattedGoal}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressPercent / 100,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progressPercent >= 100 ? AppColors.success : AppColors.primary,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.l10n.participantsCount(challenge.participantCount),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  if (widget.showJoinButton && _loaded)
                    _isParticipating
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              context.l10n.enrolled,
                              style: TextStyle(fontSize: 12),
                            ),
                          )
                        : ElevatedButton(
                            onPressed: widget.onJoin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(context.l10n.joinAction),
                          ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sheet per creare una nuova sfida
class _CreateChallengeSheet extends StatefulWidget {
  final VoidCallback onCreated;

  const _CreateChallengeSheet({required this.onCreated});

  @override
  State<_CreateChallengeSheet> createState() => _CreateChallengeSheetState();
}

class _CreateChallengeSheetState extends State<_CreateChallengeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _goalController = TextEditingController();

  String _selectedType = ChallengesService.TYPE_DISTANCE;
  int _durationDays = 7;
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  context.l10n.createNewChallenge,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // Titolo
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: context.l10n.challengeTitle,
                    hintText: context.l10n.challengeHint,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v?.trim().isEmpty == true ? context.l10n.enterTitle : null,
                ),
                const SizedBox(height: 16),

                // Descrizione
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: context.l10n.descriptionOptional,
                    hintText: context.l10n.describeChallenge,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Tipo sfida
                Text(context.l10n.challengeTypeLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: ChallengesService.TYPE_DISTANCE,
                      label: Text(context.l10n.distance),
                      icon: const Icon(Icons.straighten),
                    ),
                    ButtonSegment(
                      value: ChallengesService.TYPE_ELEVATION,
                      label: Text(context.l10n.elevation),
                      icon: const Icon(Icons.terrain),
                    ),
                    ButtonSegment(
                      value: ChallengesService.TYPE_TRACKS,
                      label: Text(context.l10n.tracks),
                      icon: const Icon(Icons.route),
                    ),
                  ],
                  selected: {_selectedType},
                  onSelectionChanged: (v) => setState(() => _selectedType = v.first),
                ),
                const SizedBox(height: 16),

                // Obiettivo
                TextFormField(
                  controller: _goalController,
                  decoration: InputDecoration(
                    labelText: context.l10n.goalLabel,
                    suffixText: _getUnitLabel(),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v?.trim().isEmpty == true) return context.l10n.enterGoal;
                    final num = double.tryParse(v!);
                    if (num == null || num <= 0) return context.l10n.enterValidNumber;
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Durata
                Text(context.l10n.duration, style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [7, 14, 30].map((days) {
                    final isSelected = _durationDays == days;
                    return ChoiceChip(
                      label: Text(context.l10n.daysCount(days)),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _durationDays = days),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Bottone crea
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isCreating ? null : _createChallenge,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(context.l10n.createChallengeBtn),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getUnitLabel() {
    switch (_selectedType) {
      case ChallengesService.TYPE_DISTANCE:
        return 'km';
      case ChallengesService.TYPE_ELEVATION:
        return 'm';
      case ChallengesService.TYPE_TRACKS:
        return context.l10n.tracksUnit;
      default:
        return '';
    }
  }

  Future<void> _createChallenge() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    double goal = double.parse(_goalController.text);
    // Converti km in metri per distanza
    if (_selectedType == ChallengesService.TYPE_DISTANCE) {
      goal *= 1000;
    }

    final endDate = DateTime.now().add(Duration(days: _durationDays));

    final id = await ChallengesService().createChallenge(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      type: _selectedType,
      goal: goal,
      endDate: endDate,
    );

    if (mounted) {
      setState(() => _isCreating = false);

      if (id != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.challengeCreated),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onCreated();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.creationError),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }
}

/// Pagina dettaglio sfida con classifica
class ChallengeDetailPage extends StatefulWidget {
  final Challenge challenge;

  const ChallengeDetailPage({super.key, required this.challenge});

  @override
  State<ChallengeDetailPage> createState() => _ChallengeDetailPageState();
}

class _ChallengeDetailPageState extends State<ChallengeDetailPage> {
  final ChallengesService _service = ChallengesService();

  List<ChallengeParticipant> _leaderboard = [];
  bool _isLoading = true;
  bool _isParticipating = false;
  double _myProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final leaderboard = await _service.getLeaderboard(widget.challenge.id);
    final participating = await _service.isParticipating(widget.challenge.id);
    double progress = 0;
    if (participating) {
      progress = await _service.getUserProgress(widget.challenge.id);
    }

    if (mounted) {
      setState(() {
        _leaderboard = leaderboard;
        _isParticipating = participating;
        _myProgress = progress;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.challenge;
    final progressPercent = challenge.goal > 0
        ? (_myProgress / challenge.goal * 100).clamp(0, 100)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.challengeDetail),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header sfida
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(challenge.icon, style: const TextStyle(fontSize: 40)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    challenge.title,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    context.l10n.createdBy(challenge.creatorName),
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (challenge.description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(challenge.description),
                        ],
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStat(context.l10n.goalLabel, challenge.formattedGoal),
                            _buildStat(context.l10n.deadlineLabel, context.l10n.daysCount(challenge.daysLeft)),
                            _buildStat(context.l10n.participants, '${challenge.participantCount}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Progresso personale
                if (_isParticipating) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.yourProgress,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                challenge.formatProgress(_myProgress),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${progressPercent.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: progressPercent >= 100
                                      ? AppColors.success
                                      : AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progressPercent / 100,
                              minHeight: 12,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progressPercent >= 100
                                    ? AppColors.success
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Classifica
                const SizedBox(height: 16),
                Text(
                  context.l10n.leaderboard,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                if (_leaderboard.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(context.l10n.noParticipants)),
                    ),
                  )
                else
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _leaderboard.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = _leaderboard[index];
                        final isMe = p.userId == FirebaseAuth.instance.currentUser?.uid;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: index < 3
                                ? [Colors.amber, Colors.grey[400], Colors.brown][index]
                                : Colors.grey[200],
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: index < 3 ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            p.displayName,
                            style: TextStyle(
                              fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: Text(
                            challenge.formatProgress(p.progress),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          tileColor: isMe
                              ? AppColors.primary.withOpacity(0.05)
                              : null,
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
