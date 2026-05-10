import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';
import '../../widgets/star_rating.dart';

/// Pagina recensioni di uno Spazio Pro.
/// - Header con avg rating + count + distribuzione
/// - Bottone "Scrivi recensione" (o "Modifica la tua")
/// - Lista recensioni (la mia in cima se presente)
/// - Owner moderation: bottone "Rimuovi" sulle recensioni altrui
class BusinessReviewsPage extends StatefulWidget {
  final Business business;
  const BusinessReviewsPage({super.key, required this.business});

  @override
  State<BusinessReviewsPage> createState() => _BusinessReviewsPageState();
}

class _BusinessReviewsPageState extends State<BusinessReviewsPage> {
  final _repo = BusinessRepository();

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isOwner = widget.business.isOwnerOrAdmin(currentUid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recensioni'),
      ),
      body: StreamBuilder<List<BusinessReview>>(
        stream: _repo.watchReviews(widget.business.id!),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reviews = snap.data ?? [];
          // Mia review prima
          BusinessReview? myReview;
          final others = <BusinessReview>[];
          for (final r in reviews) {
            if (currentUid != null && r.userId == currentUid) {
              myReview = r;
            } else {
              others.add(r);
            }
          }

          return Column(
            children: [
              _buildHeader(reviews),
              const Divider(height: 1),
              if (currentUid != null && !isOwner) _buildWriteCta(myReview),
              Expanded(
                child: _buildList(myReview, others, isOwner, currentUid),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(List<BusinessReview> reviews) {
    final count = reviews.length;
    final avg = count == 0
        ? 0.0
        : reviews.fold<int>(0, (s, r) => s + r.rating) / count;

    // Distribuzione 5..1
    final dist = <int, int>{for (var i = 1; i <= 5; i++) i: 0};
    for (final r in reviews) {
      dist[r.rating] = (dist[r.rating] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                count == 0 ? '—' : avg.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              StarRating(value: avg, size: 16),
              const SizedBox(height: 4),
              Text(
                count == 0
                    ? 'Nessuna recensione'
                    : '$count ${count == 1 ? "recensione" : "recensioni"}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                final n = dist[star] ?? 0;
                final pct = count == 0 ? 0.0 : n / count;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text('$star',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                      const SizedBox(width: 4),
                      const Icon(Icons.star,
                          size: 12, color: Color(0xFFFFB300)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            color: const Color(0xFFFFB300),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 24,
                        child: Text('$n',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWriteCta(BusinessReview? myReview) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _openComposer(myReview),
          icon: Icon(myReview == null ? Icons.rate_review : Icons.edit),
          label: Text(myReview == null
              ? 'Scrivi una recensione'
              : 'Modifica la tua recensione'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    BusinessReview? myReview,
    List<BusinessReview> others,
    bool isOwner,
    String? currentUid,
  ) {
    if (myReview == null && others.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.rate_review_outlined,
                  size: 64, color: AppColors.textMuted),
              const SizedBox(height: 12),
              const Text('Nessuna recensione ancora',
                  textAlign: TextAlign.center),
              if (currentUid != null && !isOwner) ...[
                const SizedBox(height: 4),
                const Text(
                  'Sii il primo a recensire questo Spazio Pro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListView(
      children: [
        if (myReview != null)
          _ReviewCard(
            review: myReview,
            isMine: true,
            isOwnerView: false,
            onEdit: () => _openComposer(myReview),
            onDelete: () => _confirmDeleteMyReview(myReview),
          ),
        if (myReview != null && others.isNotEmpty)
          const Divider(height: 24),
        ...others.map((r) => _ReviewCard(
              review: r,
              isMine: false,
              isOwnerView: isOwner,
              onDelete: isOwner ? () => _confirmModerateReview(r) : null,
            )),
      ],
    );
  }

  Future<void> _openComposer(BusinessReview? existing) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final result = await showModalBottomSheet<_ReviewComposerResult?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _ReviewComposerSheet(initial: existing),
      ),
    );
    if (result == null) return;
    try {
      // Display name: prendi dal Firebase Auth profile
      final displayName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!
          : (user.email?.split('@').first ?? 'Utente');
      await _repo.upsertReview(
        businessId: widget.business.id!,
        rating: result.rating,
        comment: result.comment,
        userDisplayName: displayName,
        userAvatarUrl: user.photoURL,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grazie per la tua recensione!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    }
  }

  Future<void> _confirmDeleteMyReview(BusinessReview r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina la tua recensione?'),
        content: const Text(
            'La rimozione è definitiva. Potrai scriverne una nuova in futuro.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.danger),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteReview(widget.business.id!, r.userId);
  }

  Future<void> _confirmModerateReview(BusinessReview r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi recensione?'),
        content: Text(
            'Stai rimuovendo come owner la recensione di ${r.userDisplayName}. '
            'Il rating del business verrà ricalcolato.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.danger),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteReview(widget.business.id!, r.userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    }
  }
}

class _ReviewCard extends StatelessWidget {
  final BusinessReview review;
  final bool isMine;
  final bool isOwnerView;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ReviewCard({
    required this.review,
    required this.isMine,
    required this.isOwnerView,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: review.userAvatarUrl != null
                        ? CachedNetworkImageProvider(review.userAvatarUrl!)
                        : null,
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.15),
                    child: review.userAvatarUrl == null
                        ? Text(
                            review.userDisplayName.isNotEmpty
                                ? review.userDisplayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                review.userDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (isMine) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Tua',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            StarRating(
                              value: review.rating.toDouble(),
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(
                                  review.editedAt ?? review.createdAt),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                            ),
                            if (review.editedAt != null)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Text(
                                  '· modificata',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isMine || isOwnerView)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (v) {
                        if (v == 'edit') onEdit?.call();
                        if (v == 'delete') onDelete?.call();
                      },
                      itemBuilder: (_) => [
                        if (isMine)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 16),
                                SizedBox(width: 8),
                                Text('Modifica'),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(Icons.delete_outline,
                                  size: 16, color: AppColors.danger),
                              const SizedBox(width: 8),
                              Text(isMine ? 'Elimina' : 'Rimuovi (owner)',
                                  style: const TextStyle(
                                      color: AppColors.danger)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (review.comment != null && review.comment!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    review.comment!,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays < 1) return 'oggi';
    if (diff.inDays < 7) return '${diff.inDays}g fa';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}sett fa';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _ReviewComposerResult {
  final int rating;
  final String? comment;
  const _ReviewComposerResult({required this.rating, this.comment});
}

class _ReviewComposerSheet extends StatefulWidget {
  final BusinessReview? initial;
  const _ReviewComposerSheet({this.initial});

  @override
  State<_ReviewComposerSheet> createState() => _ReviewComposerSheetState();
}

class _ReviewComposerSheetState extends State<_ReviewComposerSheet> {
  late int _rating;
  late final TextEditingController _commentCtrl;

  @override
  void initState() {
    super.initState();
    _rating = widget.initial?.rating ?? 0;
    _commentCtrl =
        TextEditingController(text: widget.initial?.comment ?? '');
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_rating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tocca le stelle per dare una valutazione'),
        ),
      );
      return;
    }
    final comment = _commentCtrl.text.trim();
    Navigator.pop(
      context,
      _ReviewComposerResult(
        rating: _rating,
        comment: comment.isEmpty ? null : comment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.initial == null
                ? 'Scrivi una recensione'
                : 'Modifica la tua recensione',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Center(
            child: StarRating(
              value: _rating.toDouble(),
              size: 36,
              readOnly: false,
              onChanged: (v) => setState(() => _rating = v),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentCtrl,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText: 'Cosa ti è piaciuto? Cosa miglioreresti? (opzionale)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annulla'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                    widget.initial == null ? 'Pubblica' : 'Salva modifiche'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

