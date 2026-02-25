import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../data/repositories/groups_repository.dart';
import 'create_event_page.dart';
import 'event_detail_page.dart';

class GroupEventsTab extends StatefulWidget {
  final String groupId;
  final bool isAdmin;

  const GroupEventsTab({
    super.key,
    required this.groupId,
    this.isAdmin = false,
  });

  @override
  State<GroupEventsTab> createState() => _GroupEventsTabState();
}

class _GroupEventsTabState extends State<GroupEventsTab> {
  final _repo = GroupsRepository();
  List<GroupEvent> _events = [];
  bool _isLoading = true;
  bool _showPast = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    final events = await _repo.getEvents(widget.groupId, upcomingOnly: !_showPast);
    if (mounted) {
      setState(() {
        _events = events;
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
              builder: (_) => CreateEventPage(groupId: widget.groupId),
            ),
          );
          if (created == true) _loadEvents();
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        mini: true,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Filtro
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text(context.l10n.upcomingFilter),
                  selected: !_showPast,
                  onSelected: (value) {
                    setState(() => _showPast = false);
                    _loadEvents();
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(context.l10n.allFilter),
                  selected: _showPast,
                  onSelected: (value) {
                    setState(() => _showPast = true);
                    _loadEvents();
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                ),
              ],
            ),
          ),

          // Lista
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _events.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadEvents,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _events.length,
                          itemBuilder: (context, index) => _buildEventCard(_events[index]),
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
          Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(context.l10n.noEventsTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            context.l10n.organizeAnOuting,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(GroupEvent event) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isParticipating = currentUserId != null && event.participants.contains(currentUserId);
    final isPast = event.isPast;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventDetailPage(
              groupId: widget.groupId,
              eventId: event.id,
              isAdmin: widget.isAdmin,
            ),
          ),
        );
        _loadEvents(); // Ricarica dopo ritorno
      },
      child: Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isPast ? Colors.grey[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isPast
                        ? Colors.grey[200]
                        : AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${event.date.day}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isPast ? Colors.grey : AppColors.primary,
                        ),
                      ),
                      Text(
                        _monthName(context, event.date.month),
                        style: TextStyle(
                          fontSize: 11,
                          color: isPast ? Colors.grey : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isPast ? Colors.grey : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${event.date.hour.toString().padLeft(2, '0')}:${event.date.minute.toString().padLeft(2, '0')} • ${event.createdByName}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (isPast)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(context.l10n.pastLabel, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
              ],
            ),

            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                event.description!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],

            // Dettagli
            if (event.meetingPointName != null || event.estimatedDistance != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (event.meetingPointName != null)
                    _buildChip(Icons.location_on, event.meetingPointName!),
                  if (event.estimatedDistance != null)
                    _buildChip(Icons.straighten, '${(event.estimatedDistance! / 1000).toStringAsFixed(1)} km'),
                  if (event.estimatedElevation != null)
                    _buildChip(Icons.terrain, '+${event.estimatedElevation!.toStringAsFixed(0)} m'),
                  if (event.difficulty != null)
                    _buildChip(Icons.signal_cellular_alt, event.difficulty!),
                ],
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Partecipanti + bottone
            Row(
              children: [
                Icon(Icons.people, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  event.maxParticipants != null
                      ? context.l10n.participantsCountWithMax(
                          event.participants.length.toString(),
                          event.maxParticipants.toString(),
                        )
                      : context.l10n.participantsCountSimple(
                          event.participants.length.toString(),
                        ),
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const Spacer(),
                if (!isPast)
                  SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _repo.toggleEventParticipation(widget.groupId, event.id);
                        _loadEvents();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isParticipating ? Colors.grey[300] : AppColors.primary,
                        foregroundColor: isParticipating ? AppColors.textPrimary : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        isParticipating ? context.l10n.withdraw : context.l10n.participate,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),

            if (event.notes != null && event.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '📝 ${event.notes}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  String _monthName(BuildContext context, int month) {
    final months = [
      context.l10n.monthShortJan, context.l10n.monthShortFeb, context.l10n.monthShortMar,
      context.l10n.monthShortApr, context.l10n.monthShortMay, context.l10n.monthShortJun,
      context.l10n.monthShortJul, context.l10n.monthShortAug, context.l10n.monthShortSep,
      context.l10n.monthShortOct, context.l10n.monthShortNov, context.l10n.monthShortDec,
    ];
    return months[month - 1];
  }
}
