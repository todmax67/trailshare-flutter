import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/l10n_extension.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../data/models/track_comment.dart';
import '../../data/repositories/track_comments_repository.dart';
import 'app_snackbar.dart';

/// Sezione commenti per una traccia community (o tour pubblico).
///
/// Renderizza:
/// - Titolo con conteggio ("Commenti · 5")
/// - Lista commenti in tempo reale (stream Firestore) — ordine cronologico
///   decrescente, max 50.
/// - Input testuale in basso con bottone Invia.
/// - Cancellazione per autore del commento e per [ownerId] della traccia.
///
/// Usage:
/// ```dart
/// TrackCommentsSection(
///   trackId: track.id,
///   ownerId: track.ownerId,
/// )
/// ```
class TrackCommentsSection extends StatefulWidget {
  final String trackId;

  /// Uid dell'autore della traccia: puo' cancellare qualsiasi commento
  /// (moderazione base). Se null, solo l'autore del commento puo' cancellare.
  final String? ownerId;

  const TrackCommentsSection({
    super.key,
    required this.trackId,
    this.ownerId,
  });

  @override
  State<TrackCommentsSection> createState() => _TrackCommentsSectionState();
}

class _TrackCommentsSectionState extends State<TrackCommentsSection> {
  final _repo = TrackCommentsRepository();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await _repo.addComment(
        trackId: widget.trackId,
        text: text,
      );
      if (!mounted) return;
      if (result == null) {
        AppSnackBar.error(context, context.l10n.commentsPostError);
      } else {
        _controller.clear();
        _focusNode.unfocus();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmDelete(TrackComment c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.commentsDeleteTitle),
        content: Text(ctx.l10n.commentsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(ctx.l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await _repo.deleteComment(
      trackId: widget.trackId,
      commentId: c.id,
    );
    if (!mounted) return;
    if (ok) {
      AppSnackBar.success(context, context.l10n.commentsDeleted);
    } else {
      AppSnackBar.error(context, context.l10n.commentsDeleteError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isTrackOwner = currentUid != null && currentUid == widget.ownerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<List<TrackComment>>(
          stream: _repo.watchComments(widget.trackId),
          builder: (context, snap) {
            final comments = snap.data ?? const <TrackComment>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 20, color: context.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.commentsTitle(comments.length),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (snap.connectionState == ConnectionState.waiting &&
                    comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        context.l10n.commentsEmpty,
                        style: TextStyle(
                          color: context.textMuted,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                else
                  ...comments.map((c) => _CommentTile(
                        comment: c,
                        canDelete: currentUid != null &&
                            (c.userId == currentUid || isTrackOwner),
                        onDelete: () => _confirmDelete(c),
                      )),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _CommentInput(
          controller: _controller,
          focusNode: _focusNode,
          submitting: _submitting,
          onSubmit: _submit,
          enabled: currentUid != null,
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final TrackComment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  const _CommentTile({
    required this.comment,
    required this.canDelete,
    required this.onDelete,
  });

  String _relativeDate(BuildContext context, DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return context.l10n.commentsJustNow;
    if (diff.inMinutes < 60) return context.l10n.commentsMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return context.l10n.commentsHoursAgo(diff.inHours);
    if (diff.inDays < 7) return context.l10n.commentsDaysAgo(diff.inDays);
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage: comment.avatarUrl != null && comment.avatarUrl!.isNotEmpty
                ? NetworkImage(comment.avatarUrl!)
                : null,
            child: comment.avatarUrl == null || comment.avatarUrl!.isEmpty
                ? Icon(Icons.person, size: 16, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.username,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${_relativeDate(context, comment.createdAt)}',
                      style: TextStyle(fontSize: 11, color: context.textMuted),
                    ),
                    const Spacer(),
                    if (canDelete)
                      InkWell(
                        onTap: onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.more_horiz,
                            size: 16,
                            color: context.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.text,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final VoidCallback onSubmit;
  final bool enabled;

  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onSubmit,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.themedBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled && !submitting,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: enabled
                    ? context.l10n.commentsInputHint
                    : context.l10n.commentsLoginHint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          IconButton(
            onPressed: enabled && !submitting ? onSubmit : null,
            icon: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.send_rounded,
                    color: enabled ? AppColors.primary : context.textMuted,
                  ),
          ),
        ],
      ),
    );
  }
}
