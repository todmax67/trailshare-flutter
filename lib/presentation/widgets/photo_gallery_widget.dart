import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/track_photos_service.dart';

/// Widget per visualizzare e gestire foto durante/dopo registrazione
class PhotoGalleryWidget extends StatelessWidget {
  final List<TrackPhoto> photos;
  final VoidCallback? onAddPhoto;
  final Function(int index)? onDeletePhoto;
  final bool isRecording;

  const PhotoGalleryWidget({
    super.key,
    required this.photos,
    this.onAddPhoto,
    this.onDeletePhoto,
    this.isRecording = false,
  });

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty && !isRecording) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.photo_camera, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                photos.isEmpty ? 'Nessuna foto' : '${photos.length} ${photos.length == 1 ? "foto" : "foto"}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (isRecording && onAddPhoto != null)
                IconButton(
                  icon: const Icon(Icons.add_a_photo, size: 20),
                  onPressed: onAddPhoto,
                  tooltip: 'Aggiungi foto',
                  color: AppColors.primary,
                ),
            ],
          ),
        ),

        // Galleria orizzontale
        if (photos.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: photos.length,
              itemBuilder: (context, index) {
                final photo = photos[index];
                return _PhotoThumbnail(
                  photo: photo,
                  onTap: () => _showPhotoDetail(context, photos, index),
                  onDelete: onDeletePhoto != null ? () => onDeletePhoto!(index) : null,
                );
              },
            ),
          ),
      ],
    );
  }

  void _showPhotoDetail(BuildContext context, List<TrackPhoto> photos, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoDetailPage(
          photos: photos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

/// Thumbnail singola foto
class _PhotoThumbnail extends StatelessWidget {
  final TrackPhoto photo;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _PhotoThumbnail({
    required this.photo,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          // Immagine
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey[200],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(photo.localPath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.broken_image, color: Colors.grey[400]),
                ),
              ),
            ),
          ),

          // Badge posizione
          if (photo.latitude != null && photo.longitude != null)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, size: 12, color: Colors.white),
                    const SizedBox(width: 2),
                    if (photo.elevation != null)
                      Text(
                        '${photo.elevation!.toStringAsFixed(0)}m',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Bottone elimina
          if (onDelete != null)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pagina dettaglio foto fullscreen
class _PhotoDetailPage extends StatefulWidget {
  final List<TrackPhoto> photos;
  final int initialIndex;

  const _PhotoDetailPage({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<_PhotoDetailPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('${_currentIndex + 1} / ${widget.photos.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showPhotoInfo(context, photo),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final p = widget.photos[index];
          return InteractiveViewer(
            child: Center(
              child: Image.file(
                File(p.localPath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPhotoInfo(BuildContext context, TrackPhoto photo) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informazioni foto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _InfoRow(Icons.access_time, 'Scattata', _formatDateTime(photo.timestamp)),
            if (photo.latitude != null && photo.longitude != null)
              _InfoRow(
                Icons.location_on,
                'Coordinate',
                '${photo.latitude!.toStringAsFixed(6)}, ${photo.longitude!.toStringAsFixed(6)}',
              ),
            if (photo.elevation != null)
              _InfoRow(Icons.terrain, 'Quota', '${photo.elevation!.toStringAsFixed(0)} m'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget per il bottone "Aggiungi foto" durante registrazione
class AddPhotoButton extends StatelessWidget {
  final VoidCallback onTakePhoto;
  final VoidCallback onPickFromGallery;

  const AddPhotoButton({
    super.key,
    required this.onTakePhoto,
    required this.onPickFromGallery,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'add_photo',
      onPressed: () => _showOptions(context),
      backgroundColor: AppColors.info,
      child: const Icon(Icons.add_a_photo),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Scatta foto'),
              onTap: () {
                Navigator.pop(context);
                onTakePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.info),
              title: const Text('Scegli dalla galleria'),
              onTap: () {
                Navigator.pop(context);
                onPickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: AppColors.textMuted),
              title: const Text('Annulla'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
