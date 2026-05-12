import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/trail_photo.dart';
import '../../data/repositories/trail_photos_repository.dart';
import 'trail_photo_viewer.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/extensions/l10n_extension.dart';

/// Sezione completa "Foto community" per la pagina dettaglio sentiero.
///
/// Mostra una grid 3 colonne di foto, permette di aggiungerne (camera/galleria)
/// e di visualizzarle a pieno schermo.
class TrailPhotosSection extends StatefulWidget {
  final String trailId;

  const TrailPhotosSection({super.key, required this.trailId});

  @override
  State<TrailPhotosSection> createState() => _TrailPhotosSectionState();
}

class _TrailPhotosSectionState extends State<TrailPhotosSection> {
  final TrailPhotosRepository _repo = TrailPhotosRepository();
  final ImagePicker _picker = ImagePicker();

  List<TrailPhoto> _photos = [];
  bool _isLoading = true;
  bool _error = false;
  bool _isUploading = false;

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
    final photos = await _repo.getPhotosForTrail(widget.trailId);
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _isLoading = false;
    });
  }

  Future<void> _showSourceSheet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devi effettuare il login per caricare foto'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Scatta foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.info),
              title: const Text('Scegli dalla galleria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;
    await _pickAndUpload(source);
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 70,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (picked == null || !mounted) return;

      // Chiedi caption opzionale
      final caption = await _askCaption();
      if (!mounted) return;

      setState(() => _isUploading = true);

      final result = await _repo.uploadPhoto(
        trailId: widget.trailId,
        file: File(picked.path),
        caption: caption ?? '',
      );

      if (!mounted) return;
      setState(() => _isUploading = false);

      if (result.success && result.photo != null) {
        setState(() => _photos = [result.photo!, ..._photos]);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Errore durante il caricamento'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.genericErrorWith(e.toString())),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<String?> _askCaption() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiungi una didascalia'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Descrivi la foto (opzionale)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Salta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Carica'),
          ),
        ],
      ),
    );
    return result;
  }

  void _openViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrailPhotoViewer(
          photos: _photos,
          initialIndex: index,
          onDelete: (photo) async {
            final result = await _repo.deletePhoto(photo);
            if (result.success && mounted) {
              setState(() => _photos.removeWhere((p) => p.photoId == photo.photoId));
            }
            return result.success;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
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
              _buildUploadButton(),
              const SizedBox(height: 12),
              if (_photos.isEmpty && !_isUploading)
                _buildEmpty()
              else
                _buildGrid(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.photo_library_outlined, size: 20, color: AppColors.info),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Foto community',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (!_isLoading && !_error && _photos.isNotEmpty)
          Text(
            '${_photos.length}',
            style: TextStyle(fontSize: 13, color: context.textMuted),
          ),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: context.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Impossibile caricare le foto',
              style: TextStyle(color: context.textMuted, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isUploading ? null : _showSourceSheet,
        icon: _isUploading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(_isUploading ? 'Caricamento...' : 'Aggiungi foto'),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'Nessuna foto ancora. Sii il primo a condividere!',
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final photo = _photos[index];
        return GestureDetector(
          onTap: () => _openViewer(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              photo.photoUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (context, error, stack) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        );
      },
    );
  }
}
