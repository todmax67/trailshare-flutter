import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/business_photos_service.dart';
import '../../../data/repositories/business_repository.dart';
import '../../../core/extensions/l10n_extension.dart';

class BusinessPostComposerPage extends StatefulWidget {
  final String businessId;
  const BusinessPostComposerPage({super.key, required this.businessId});

  @override
  State<BusinessPostComposerPage> createState() =>
      _BusinessPostComposerPageState();
}

class _BusinessPostComposerPageState extends State<BusinessPostComposerPage> {
  final _ctrl = TextEditingController();
  final _repo = BusinessRepository();
  final _photos = BusinessPhotosService();
  final List<String> _photoUrls = [];
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _addPhoto({bool fromCamera = false}) async {
    setState(() => _uploadingPhoto = true);
    try {
      final url = await _photos.pickAndUpload(
        businessId: widget.businessId,
        kind: BusinessPhotoKind.posts,
        fromCamera: fromCamera,
      );
      if (url != null) {
        setState(() => _photoUrls.add(url));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _removePhoto(int index) {
    final url = _photoUrls[index];
    setState(() => _photoUrls.removeAt(index));
    _photos.deletePhotoByUrl(url);
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _photoUrls.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _repo.createPost(
        businessId: widget.businessId,
        text: text,
        photoUrls: _photoUrls,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.genericErrorWith(e.toString()))),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuovo aggiornamento'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Pubblica'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cosa vuoi comunicare ai tuoi follower?',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                maxLength: 5000,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText:
                      'Es. "Sentiero al rifugio innevato sopra 2200m, raccomandiamo ramponi..."',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_photoUrls.isNotEmpty)
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: _photoUrls[i],
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: IconButton.filled(
                          iconSize: 14,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black87,
                          ),
                          icon: const Icon(Icons.close,
                              color: Colors.white),
                          onPressed: () => _removePhoto(i),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: _uploadingPhoto ? null : () => _addPhoto(),
                  icon: const Icon(Icons.photo_library),
                  tooltip: 'Aggiungi da galleria',
                ),
                IconButton.filledTonal(
                  onPressed: _uploadingPhoto
                      ? null
                      : () => _addPhoto(fromCamera: true),
                  icon: const Icon(Icons.camera_alt),
                  tooltip: 'Scatta foto',
                ),
                if (_uploadingPhoto) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                const Spacer(),
                Text(
                  '${_photoUrls.length} foto',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
