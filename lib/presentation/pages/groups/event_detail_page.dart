import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/groups_repository.dart';

class EventDetailPage extends StatefulWidget {
  final String groupId;
  final String eventId;
  final bool isAdmin;

  const EventDetailPage({
    super.key,
    required this.groupId,
    required this.eventId,
    this.isAdmin = false,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final _repo = GroupsRepository();
  final _postController = TextEditingController();
  
  GroupEvent? _event;
  bool _isLoading = true;
  bool _isPostingUpdate = false;
  bool _isUploadingCover = false;
  List<Map<String, dynamic>> _posts = [];
  Map<String, String> _participantNames = {};

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;
  bool get _isCreator => _event?.createdBy == _currentUserId;
  bool get _canEdit => _isCreator || widget.isAdmin;
  bool get _isParticipating => _currentUserId != null && (_event?.participants.contains(_currentUserId) ?? false);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadEvent(),
      _loadPosts(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadEvent() async {
    final event = await _repo.getEvent(widget.groupId, widget.eventId);
    if (event != null && mounted) {
      final names = await _repo.getParticipantNames(event.participants);
      setState(() {
        _event = event;
        _participantNames = names;
      });
    }
  }

  Future<void> _loadPosts() async {
    final posts = await _repo.getEventPosts(widget.groupId, widget.eventId);
    if (mounted) setState(() => _posts = posts);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AZIONI
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _toggleParticipation() async {
    await _repo.toggleEventParticipation(widget.groupId, widget.eventId);
    await _loadEvent();
  }

  Future<void> _uploadCoverImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 900,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _isUploadingCover = true);

    try {
      final ref = FirebaseStorage.instance
          .ref('event_images/${widget.groupId}/${widget.eventId}_cover.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();

      await _repo.updateEvent(widget.groupId, widget.eventId, {
        'coverImageUrl': url,
      });
      await _loadEvent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore upload: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  Future<void> _addPost({String? imageUrl}) async {
    final text = _postController.text.trim();
    if (text.isEmpty && imageUrl == null) return;

    setState(() => _isPostingUpdate = true);

    final success = await _repo.addEventPost(
      widget.groupId,
      widget.eventId,
      text: text.isNotEmpty ? text : '📷 Foto',
      imageUrl: imageUrl,
    );

    if (success && mounted) {
      _postController.clear();
      await _loadPosts();
    }

    if (mounted) setState(() => _isPostingUpdate = false);
  }

  Future<void> _addPostWithImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 75,
    );
    if (picked == null) return;

    setState(() => _isPostingUpdate = true);

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref('event_images/${widget.groupId}/${widget.eventId}_post_$timestamp.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      await _addPost(imageUrl: url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore upload: $e'), backgroundColor: AppColors.danger),
        );
        setState(() => _isPostingUpdate = false);
      }
    }
  }

  Future<void> _deletePost(String postId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina post'),
        content: const Text('Vuoi eliminare questo post?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _repo.deleteEventPost(widget.groupId, widget.eventId, postId);
      await _loadPosts();
    }
  }

  Future<void> _deleteEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina evento'),
        content: const Text('Vuoi eliminare questo evento? L\'azione è irreversibile.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _repo.deleteEvent(widget.groupId, widget.eventId);
      if (mounted) Navigator.pop(context, true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _event == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Evento'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final event = _event!;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [
            // ─── HEADER CON IMMAGINE ───
            _buildSliverAppBar(event),

            // ─── CONTENUTO ───
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEventInfo(event),
                  const Divider(height: 1),
                  _buildParticipantsSection(event),
                  const Divider(height: 1),
                  _buildActionButtons(event),
                  const Divider(height: 1),
                  _buildPostsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SLIVER APP BAR CON COVER ───
  Widget _buildSliverAppBar(GroupEvent event) {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      actions: [
        if (_canEdit)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'cover') _uploadCoverImage();
              if (value == 'delete') _deleteEvent();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'cover', child: Text('Cambia copertina')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Elimina evento', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          event.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (event.coverImageUrl != null)
              Image.network(
                event.coverImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildDefaultCover(event),
              )
            else
              _buildDefaultCover(event),
            // Gradiente per leggibilità
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
            if (_isUploadingCover)
              Container(
                color: Colors.black38,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultCover(GroupEvent event) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.7),
            AppColors.success.withOpacity(0.5),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event, size: 48, color: Colors.white70),
            const SizedBox(height: 8),
            if (_canEdit)
              TextButton.icon(
                onPressed: _uploadCoverImage,
                icon: const Icon(Icons.add_photo_alternate, color: Colors.white70, size: 18),
                label: const Text('Aggiungi copertina', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }

  // ─── INFO EVENTO ───
  Widget _buildEventInfo(GroupEvent event) {
    final months = ['Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
                     'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Data e ora
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: event.isPast ? Colors.grey[100] : AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '${event.date.day}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: event.isPast ? Colors.grey : AppColors.primary,
                      ),
                    ),
                    Text(
                      months[event.date.month - 1],
                      style: TextStyle(
                        fontSize: 12,
                        color: event.isPast ? Colors.grey : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${event.date.hour.toString().padLeft(2, '0')}:${event.date.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        if (event.isPast) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Concluso', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Organizzato da ${event.createdByName}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Descrizione
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              event.description!,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ],

          // Dettagli percorso
          if (event.meetingPointName != null || event.estimatedDistance != null || event.difficulty != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                if (event.meetingPointName != null)
                  _buildInfoChip(Icons.location_on, event.meetingPointName!, AppColors.danger),
                if (event.estimatedDistance != null)
                  _buildInfoChip(Icons.straighten, '${(event.estimatedDistance! / 1000).toStringAsFixed(1)} km', AppColors.primary),
                if (event.estimatedElevation != null)
                  _buildInfoChip(Icons.terrain, '+${event.estimatedElevation!.toStringAsFixed(0)} m', AppColors.success),
                if (event.difficulty != null)
                  _buildInfoChip(Icons.signal_cellular_alt, event.difficulty!, Colors.orange),
              ],
            ),
          ],

          // Note
          if (event.notes != null && event.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📝 ', style: TextStyle(fontSize: 16)),
                  Expanded(
                    child: Text(
                      event.notes!,
                      style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ─── PARTECIPANTI ───
  Widget _buildParticipantsSection(GroupEvent event) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Partecipanti (${event.participants.length}${event.maxParticipants != null ? "/${event.maxParticipants}" : ""})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (event.participants.isEmpty)
            Text('Nessun partecipante ancora', style: TextStyle(color: Colors.grey[500]))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: event.participants.map((uid) {
                final name = _participantNames[uid] ?? 'Utente';
                final isCreator = uid == event.createdBy;
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: isCreator ? AppColors.primary : Colors.grey[300],
                    radius: 14,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isCreator ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  label: Text(name, style: const TextStyle(fontSize: 13)),
                  labelPadding: const EdgeInsets.only(left: 2, right: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: isCreator
                      ? const BorderSide(color: AppColors.primary, width: 1.5)
                      : BorderSide.none,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ─── BOTTONI AZIONE ───
  Widget _buildActionButtons(GroupEvent event) {
    if (event.isPast) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: (event.isFull && !_isParticipating) ? null : _toggleParticipation,
          icon: Icon(_isParticipating ? Icons.check_circle : Icons.add_circle_outline),
          label: Text(
            _isParticipating
                ? 'Sei iscritto — Ritirati'
                : event.isFull
                    ? 'Evento al completo'
                    : 'Partecipa',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isParticipating ? Colors.grey[200] : AppColors.primary,
            foregroundColor: _isParticipating ? AppColors.textPrimary : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  // ─── SEZIONE POST ───
  Widget _buildPostsSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.dynamic_feed, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Aggiornamenti',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Input nuovo post
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _postController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: 'Scrivi un aggiornamento...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: _isPostingUpdate ? null : _addPostWithImage,
                      icon: const Icon(Icons.image, color: AppColors.primary),
                      tooltip: 'Aggiungi foto',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: TextButton(
                        onPressed: _isPostingUpdate ? null : () => _addPost(),
                        child: _isPostingUpdate
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Pubblica', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Lista post
          if (_posts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.article_outlined, size: 40, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    Text(
                      'Nessun aggiornamento',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Condividi info, novità o foto dell\'evento!',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._posts.map((post) => _buildPostCard(post)),

          // Spazio extra in fondo
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    final authorName = post['authorName'] ?? 'Utente';
    final text = post['text'] ?? '';
    final imageUrl = post['imageUrl'] as String?;
    final createdAt = (post['createdAt'] as Timestamp?)?.toDate();
    final postId = post['id'] as String?;
    final authorId = post['authorId'] as String?;
    final canDelete = authorId == _currentUserId || _canEdit;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(authorName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    if (createdAt != null)
                      Text(
                        _formatPostDate(createdAt),
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                  ],
                ),
              ),
              if (canDelete && postId != null)
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
                  onPressed: () => _deletePost(postId),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ],
          ),

          // Testo
          if (text.isNotEmpty && text != '📷 Foto') ...[
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],

          // Immagine
          if (imageUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                onTap: () => _showFullImage(imageUrl),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 150,
                      color: Colors.grey[100],
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    height: 100,
                    color: Colors.grey[100],
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showFullImage(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url),
            ),
          ),
        ),
      ),
    );
  }

  // ─── UTILS ───
  String _formatPostDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Ora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} ore fa';
    if (diff.inDays < 7) return '${diff.inDays} giorni fa';
    return '${date.day}/${date.month}/${date.year}';
  }
}
