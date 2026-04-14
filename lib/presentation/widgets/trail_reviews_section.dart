import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/trail_review.dart';
import '../../data/repositories/reviews_repository.dart';
import 'review_editor_sheet.dart';
import 'star_rating.dart';

/// Sezione completa recensioni per la pagina dettaglio sentiero.
///
/// ```dart
/// TrailReviewsSection(trailId: trail.id)
/// ```
class TrailReviewsSection extends StatefulWidget {
  final String trailId;

  const TrailReviewsSection({super.key, required this.trailId});

  @override
  State<TrailReviewsSection> createState() => _TrailReviewsSectionState();
}

class _TrailReviewsSectionState extends State<TrailReviewsSection> {
  final ReviewsRepository _repo = ReviewsRepository();

  List<TrailReview> _reviews = [];
  TrailReview? _myReview;
  bool _isLoading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = false;
    });

    try {
      final results = await Future.wait([
        _repo.getReviewsForTrail(widget.trailId),
        _repo.getUserReview(widget.trailId),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews = results[0] as List<TrailReview>;
        _myReview = results[1] as TrailReview?;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = true;
      });
    }
  }

  Future<void> _openEditor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devi effettuare il login per lasciare una recensione'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ReviewEditorSheet(
        existing: _myReview,
        onSave: (rating, text) => _repo.saveReview(
          trailId: widget.trailId,
          rating: rating,
          text: text,
        ),
        onDelete: _myReview != null
            ? () => _repo.deleteReview(widget.trailId)
            : null,
      ),
    );

    if (changed == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final average = ReviewsRepository.computeAverage(_reviews);
    final otherReviews = _reviews.where((r) => r.userId != _myReview?.userId).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(average),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error)
              _buildError()
            else ...[
              if (_myReview != null) ...[
                _buildMyReview(_myReview!),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
              ] else ...[
                _buildCta(),
                if (otherReviews.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                ],
              ],
              if (otherReviews.isEmpty && _myReview == null)
                _buildEmpty()
              else if (otherReviews.isNotEmpty)
                Column(
                  children: otherReviews
                      .map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildReviewTile(r),
                          ))
                      .toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double average) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 22, color: Colors.amber),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Recensioni',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (!_isLoading && !_error && _reviews.isNotEmpty) ...[
          Text(
            average.toStringAsFixed(1),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            '(${_reviews.length})',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Impossibile caricare le recensioni',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Riprova'),
          ),
        ],
      ),
    );
  }

  Widget _buildCta() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openEditor,
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Scrivi una recensione'),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Nessuna recensione ancora. Sii il primo!',
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildMyReview(TrailReview r) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'La tua recensione',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: _openEditor,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Modifica',
              ),
            ],
          ),
          const SizedBox(height: 6),
          StarRating(value: r.rating.toDouble(), size: 18),
          if (r.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.text, style: const TextStyle(fontSize: 14)),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewTile(TrailReview r) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          backgroundImage:
              (r.avatarUrl != null && r.avatarUrl!.isNotEmpty) ? NetworkImage(r.avatarUrl!) : null,
          child: (r.avatarUrl == null || r.avatarUrl!.isEmpty)
              ? Text(
                  r.username.isNotEmpty ? r.username[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.username,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _relativeDate(r.createdAt),
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              StarRating(value: r.rating.toDouble(), size: 14),
              if (r.text.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(r.text, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} h fa';
    if (diff.inDays < 7) return '${diff.inDays} g fa';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} sett fa';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} mesi fa';
    return '${(diff.inDays / 365).floor()} anni fa';
  }
}
