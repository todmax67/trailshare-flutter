import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../data/models/trail_photo.dart';
import '../../core/extensions/l10n_extension.dart';

/// Viewer full-screen per sfogliare una lista di [TrailPhoto] con pinch-to-zoom.
///
/// ```dart
/// Navigator.push(context, MaterialPageRoute(builder: (_) => TrailPhotoViewer(
///   photos: photos,
///   initialIndex: 2,
///   onDelete: (photo) => repo.deletePhoto(photo),
/// )));
/// ```
class TrailPhotoViewer extends StatefulWidget {
  final List<TrailPhoto> photos;
  final int initialIndex;
  final Future<bool> Function(TrailPhoto photo)? onDelete;

  const TrailPhotoViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
    this.onDelete,
  });

  @override
  State<TrailPhotoViewer> createState() => _TrailPhotoViewerState();
}

class _TrailPhotoViewerState extends State<TrailPhotoViewer> {
  late PageController _controller;
  late int _currentIndex;
  late List<TrailPhoto> _photos;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _photos = List.of(widget.photos);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final photo = _photos[_currentIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deletePhotoQuestion),
        content: Text('Questa azione non può essere annullata.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final success = await widget.onDelete!(photo);
    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante l\'eliminazione'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _photos.removeAt(_currentIndex);
      if (_photos.isEmpty) {
        Navigator.pop(context, true);
        return;
      }
      if (_currentIndex >= _photos.length) {
        _currentIndex = _photos.length - 1;
      }
    });
    _controller.jumpToPage(_currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (_photos.isEmpty) return const SizedBox.shrink();

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final photo = _photos[_currentIndex];
    final isOwner = currentUserId != null && currentUserId == photo.userId;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${_photos.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          if (isOwner && widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
              tooltip: 'Elimina',
            ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _photos.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, index) {
              final p = _photos[index];
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    p.photoUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (context, error, stack) => const Center(
                      child: Icon(Icons.broken_image, size: 64, color: Colors.white),
                    ),
                  ),
                ),
              );
            },
          ),
          // Footer info
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    backgroundImage:
                        (photo.avatarUrl != null && photo.avatarUrl!.isNotEmpty)
                            ? NetworkImage(photo.avatarUrl!)
                            : null,
                    child: (photo.avatarUrl == null || photo.avatarUrl!.isEmpty)
                        ? Text(
                            photo.username.isNotEmpty
                                ? photo.username[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          photo.username,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (photo.caption.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            photo.caption,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
