import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/track_photos_service.dart';
import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';

/// Editor foto di una traccia — versione **web**.
///
/// Mostra le foto esistenti in gallery responsive, permette di
/// aggiungere nuove foto (image_picker.pickMultiImage, upload via
/// [TrackPhotosService.uploadPhotoBytes] e [TracksRepository.updateTrackPhotos]),
/// di editare la caption e di eliminarle.
///
/// EXIF parsing e posizionamento manuale su mappa sono fuori dal
/// MVP — verranno aggiunti in iterazioni successive. Per ora le foto
/// caricate da web non hanno lat/lng (i marker mappa appariranno solo
/// per le foto già geolocalizzate dal mobile durante la registrazione).
class WebTrackPhotosEditor extends StatefulWidget {
  final Track track;

  /// Callback invocata quando la lista foto viene persistita su
  /// Firestore. Permette al parent (es. WebTrackDetailPage) di
  /// rifare lo state senza re-fetch completo.
  final ValueChanged<List<TrackPhotoMetadata>>? onPhotosChanged;

  const WebTrackPhotosEditor({
    super.key,
    required this.track,
    this.onPhotosChanged,
  });

  @override
  State<WebTrackPhotosEditor> createState() => _WebTrackPhotosEditorState();
}

class _WebTrackPhotosEditorState extends State<WebTrackPhotosEditor> {
  final _photosService = TrackPhotosService();
  final _tracksRepo = TracksRepository();
  final _picker = ImagePicker();

  late List<TrackPhotoMetadata> _photos;
  bool _uploading = false;
  int _uploadCurrent = 0;
  int _uploadTotal = 0;

  /// Vero se l'utente loggato è proprietario della traccia e quindi
  /// può modificare le foto. Lettori esterni vedono solo la gallery.
  bool get _canEdit {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && uid == widget.track.userId;
  }

  @override
  void initState() {
    super.initState();
    _photos = List.of(widget.track.photos);
  }

  Future<void> _addPhotos() async {
    final trackId = widget.track.id;
    if (trackId == null) {
      _snack('Salva la traccia prima di aggiungere foto', error: true);
      return;
    }
    final picked = await _picker.pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
      limit: 10,
    );
    if (picked.isEmpty) return;

    setState(() {
      _uploading = true;
      _uploadCurrent = 0;
      _uploadTotal = picked.length;
    });

    final newPhotos = <TrackPhotoMetadata>[];
    for (int i = 0; i < picked.length; i++) {
      setState(() => _uploadCurrent = i + 1);
      final xfile = picked[i];
      final bytes = await xfile.readAsBytes();
      // Estensione dal nome se possibile, altrimenti .jpg
      final name = xfile.name.toLowerCase();
      final ext = name.endsWith('.png')
          ? '.png'
          : name.endsWith('.jpeg')
              ? '.jpeg'
              : '.jpg';
      final url = await _photosService.uploadPhotoBytes(
        bytes: bytes,
        trackId: trackId,
        extension: ext,
      );
      if (url != null) {
        newPhotos.add(TrackPhotoMetadata(
          url: url,
          timestamp: DateTime.now(),
        ));
      }
    }

    if (!mounted) return;
    final merged = [..._photos, ...newPhotos];
    await _persist(merged);
    setState(() {
      _uploading = false;
      _uploadCurrent = 0;
      _uploadTotal = 0;
    });
    if (newPhotos.length == picked.length) {
      _snack('${newPhotos.length} foto aggiunte');
    } else {
      _snack(
        '${newPhotos.length} di ${picked.length} caricate '
        '(${picked.length - newPhotos.length} fallite)',
        error: true,
      );
    }
  }

  Future<void> _deletePhoto(int index) async {
    final p = _photos[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina foto'),
        content: const Text(
          'Vuoi eliminare definitivamente questa foto?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.12),
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Best-effort delete dello Storage, poi rimuovi dal Firestore.
    // Se Storage delete fallisce non blocchiamo l'update doc — la
    // metadata fa fede.
    await _photosService.deletePhoto(p.url);
    final updated = [..._photos]..removeAt(index);
    await _persist(updated);
    _snack('Foto eliminata');
  }

  Future<void> _editCaption(int index) async {
    final p = _photos[index];
    final ctrl = TextEditingController(text: p.caption ?? '');
    final newCaption = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Caption della foto'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 140,
          decoration: const InputDecoration(
            hintText: 'Es. "Bivio per il rifugio", "Sorgente"',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (newCaption == null) return;
    final trimmed = newCaption.trim();
    final updated = [..._photos];
    updated[index] = TrackPhotoMetadata(
      url: p.url,
      latitude: p.latitude,
      longitude: p.longitude,
      elevation: p.elevation,
      timestamp: p.timestamp,
      caption: trimmed.isEmpty ? null : trimmed,
    );
    await _persist(updated);
  }

  Future<void> _persist(List<TrackPhotoMetadata> updated) async {
    final trackId = widget.track.id;
    if (trackId == null) return;
    try {
      await _tracksRepo.updateTrackPhotos(trackId, updated);
      if (!mounted) return;
      setState(() => _photos = updated);
      widget.onPhotosChanged?.call(updated);
    } catch (e) {
      if (!mounted) return;
      _snack('Errore salvataggio: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? Colors.red.shade700 : const Color(0xFF2E7D5B),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openLightbox(int index) {
    showDialog(
      context: context,
      builder: (_) => _Lightbox(photos: _photos, initialIndex: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          if (_uploading) _buildUploadProgress(),
          if (_photos.isEmpty && !_uploading)
            _buildEmptyState()
          else
            _buildGallery(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.photo_library_outlined,
            size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        const Text(
          'Foto del percorso',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        if (_photos.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_photos.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        const Spacer(),
        if (_canEdit)
          FilledButton.icon(
            onPressed: _uploading ? null : _addPhotos,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('Aggiungi foto'),
          ),
      ],
    );
  }

  Widget _buildUploadProgress() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Caricamento $_uploadCurrent di $_uploadTotal…',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _uploadTotal == 0
                  ? null
                  : _uploadCurrent / _uploadTotal,
              minHeight: 6,
              backgroundColor:
                  AppColors.primary.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(
            Icons.image_outlined,
            size: 36,
            color: AppColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            _canEdit
                ? 'Nessuna foto. Aggiungi immagini del percorso per '
                    'arricchire la scheda — particolarmente utile per '
                    'percorsi pubblicati nel gruppo.'
                : 'Nessuna foto.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGallery() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (int i = 0; i < _photos.length; i++)
          _PhotoTile(
            photo: _photos[i],
            canEdit: _canEdit,
            onTap: () => _openLightbox(i),
            onEditCaption: () => _editCaption(i),
            onDelete: () => _deletePhoto(i),
          ),
      ],
    );
  }
}

// ============================================================
// PHOTO TILE
// ============================================================

class _PhotoTile extends StatelessWidget {
  final TrackPhotoMetadata photo;
  final bool canEdit;
  final VoidCallback onTap;
  final VoidCallback onEditCaption;
  final VoidCallback onDelete;

  const _PhotoTile({
    required this.photo,
    required this.canEdit,
    required this.onTap,
    required this.onEditCaption,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                InkWell(
                  onTap: onTap,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: CachedNetworkImage(
                      imageUrl: photo.url,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: AppColors.background,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: AppColors.background,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                if (photo.latitude != null && photo.longitude != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.place,
                              size: 10, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            'GPS',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (canEdit)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _IconBtn(
                      icon: Icons.delete_outline,
                      color: Colors.red.shade700,
                      onTap: onDelete,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: canEdit ? onEditCaption : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      photo.caption?.isNotEmpty == true
                          ? photo.caption!
                          : (canEdit
                              ? 'Aggiungi una didascalia…'
                              : ''),
                      style: TextStyle(
                        fontSize: 12,
                        color: photo.caption?.isNotEmpty == true
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontStyle: photo.caption?.isNotEmpty == true
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canEdit)
                    const Icon(
                      Icons.edit,
                      size: 12,
                      color: AppColors.textMuted,
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

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

// ============================================================
// LIGHTBOX
// ============================================================

class _Lightbox extends StatefulWidget {
  final List<TrackPhotoMetadata> photos;
  final int initialIndex;
  const _Lightbox({required this.photos, required this.initialIndex});

  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final p = widget.photos[_index];
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          Center(
            child: CachedNetworkImage(
              imageUrl: p.url,
              fit: BoxFit.contain,
              placeholder: (_, _) => const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (_index > 0)
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_left,
                      color: Colors.white, size: 36),
                  onPressed: () => setState(() => _index--),
                ),
              ),
            ),
          if (_index < widget.photos.length - 1)
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_right,
                      color: Colors.white, size: 36),
                  onPressed: () => setState(() => _index++),
                ),
              ),
            ),
          if (p.caption?.isNotEmpty == true)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.black.withValues(alpha: 0.55),
                child: Text(
                  p.caption!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: 12,
            child: Center(
              child: Text(
                '${_index + 1} / ${widget.photos.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
