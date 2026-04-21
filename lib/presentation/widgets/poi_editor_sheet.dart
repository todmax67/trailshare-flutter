import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/trail_poi.dart';
import '../../data/repositories/poi_repository.dart';
import '../../core/extensions/theme_colors_extension.dart';

/// Apre il bottom sheet per creare/modificare un POI.
///
/// [latitude] e [longitude] sono la posizione del POI (fissata dal
/// contesto: posizione GPS attuale durante la registrazione, oppure
/// tap sulla mappa in edit mode).
///
/// [relatedTrailId] e [relatedTrackId] sono opzionali: se presenti il
/// POI viene associato al trail/track. Entrambi null = POI globale.
///
/// [initialPoi] per modalità edit (mostra campi precompilati).
///
/// Ritorna il POI creato/modificato (con id) o null se l'utente ha
/// annullato.
Future<TrailPoi?> showPoiEditorSheet(
  BuildContext context, {
  required double latitude,
  required double longitude,
  double? elevation,
  String? relatedTrailId,
  String? relatedTrackId,
  TrailPoi? initialPoi,
}) {
  return showModalBottomSheet<TrailPoi>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PoiEditorSheet(
      latitude: latitude,
      longitude: longitude,
      elevation: elevation,
      relatedTrailId: relatedTrailId,
      relatedTrackId: relatedTrackId,
      initialPoi: initialPoi,
    ),
  );
}

class _PoiEditorSheet extends StatefulWidget {
  final double latitude;
  final double longitude;
  final double? elevation;
  final String? relatedTrailId;
  final String? relatedTrackId;
  final TrailPoi? initialPoi;

  const _PoiEditorSheet({
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.relatedTrailId,
    this.relatedTrackId,
    this.initialPoi,
  });

  @override
  State<_PoiEditorSheet> createState() => _PoiEditorSheetState();
}

class _PoiEditorSheetState extends State<_PoiEditorSheet> {
  final _repo = PoiRepository();
  final _picker = ImagePicker();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late PoiType _selectedType;
  File? _photoFile;
  String? _existingPhotoUrl;
  bool _isPublic = false;
  bool _saving = false;

  bool get _isEdit => widget.initialPoi != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initialPoi;
    _selectedType = init?.type ?? PoiType.water;
    if (init != null) {
      _titleCtrl.text = init.title;
      _descCtrl.text = init.description ?? '';
      _existingPhotoUrl = init.photoUrl;
      _isPublic = init.isPublic;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto({required ImageSource source}) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
      if (photo == null) return;
      setState(() {
        _photoFile = File(photo.path);
        _existingPhotoUrl = null; // sostituito dalla nuova
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore scatto foto: $e')),
      );
    }
  }

  Future<String?> _uploadPhoto(String poiId) async {
    final file = _photoFile;
    if (file == null) return _existingPhotoUrl;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final ref = FirebaseStorage.instance
          .ref()
          .child('poi_photos')
          .child('${uid}_${poiId}.jpg');
      final upload = await ref.putFile(file);
      return await upload.ref.getDownloadURL();
    } catch (e) {
      debugPrint('[PoiEditor] Errore upload foto: $e');
      return null;
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      if (_isEdit) {
        final existing = widget.initialPoi!;
        final updated = existing.copyWith(
          type: _selectedType,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          isPublic: _isPublic,
        );
        // Upload nuova foto se selezionata
        if (_photoFile != null) {
          final url = await _uploadPhoto(existing.id);
          if (url != null) {
            await _repo.updatePoi(updated.copyWith(photoUrl: url));
            if (!mounted) return;
            Navigator.pop(context, updated.copyWith(photoUrl: url));
            return;
          }
        }
        await _repo.updatePoi(updated);
        if (!mounted) return;
        Navigator.pop(context, updated);
      } else {
        // CREATE
        final draft = TrailPoi(
          id: '',
          type: _selectedType,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          latitude: widget.latitude,
          longitude: widget.longitude,
          createdBy: user.uid,
          createdByUsername: user.displayName,
          relatedTrailId: widget.relatedTrailId,
          relatedTrackId: widget.relatedTrackId,
          isPublic: _isPublic,
        );
        final id = await _repo.createPoi(draft);
        if (id == null) {
          throw Exception('Errore creazione POI');
        }
        String? photoUrl;
        if (_photoFile != null) {
          photoUrl = await _uploadPhoto(id);
          if (photoUrl != null) {
            await _repo.updatePoi(draft.copyWith(id: id, photoUrl: photoUrl));
          }
        }
        if (!mounted) return;
        Navigator.pop(context, draft.copyWith(id: id, photoUrl: photoUrl));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore salvataggio POI: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      _isEdit ? 'Modifica POI' : 'Aggiungi POI qui',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Picker tipo POI
                  const Text(
                    'Tipo',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _buildTypeGrid(),
                  const SizedBox(height: 14),

                  // Titolo
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: InputDecoration(
                      labelText: 'Titolo *',
                      hintText: _selectedType.displayName,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Inserisci un titolo'
                        : (v.trim().length > 120
                            ? 'Massimo 120 caratteri'
                            : null),
                  ),
                  const SizedBox(height: 10),

                  // Descrizione opzionale
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descrizione (opzionale)',
                      hintText: 'Info utili, es. "Fonte sotto grande faggio"',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),

                  // Foto opzionale
                  _buildPhotoPicker(),
                  const SizedBox(height: 12),

                  // Toggle pubblico
                  SwitchListTile(
                    value: _isPublic,
                    onChanged: (v) => setState(() => _isPublic = v),
                    title: const Text('Rendi pubblico',
                        style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      _isPublic
                          ? 'Visibile a tutti gli utenti TrailShare'
                          : 'Visibile solo a te',
                      style: const TextStyle(fontSize: 11),
                    ),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  const SizedBox(height: 12),

                  // Azioni
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          child: const Text('Annulla'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check),
                          label: Text(_isEdit ? 'Salva' : 'Aggiungi POI'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: PoiType.values.map((t) {
        final selected = _selectedType == t;
        return GestureDetector(
          onTap: () => setState(() => _selectedType = t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? t.pinColor : t.pinColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? t.pinColor : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(
                  t.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? Colors.white : t.pinColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPhotoPicker() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.photo_camera_outlined,
                  size: 18, color: context.textMuted),
              const SizedBox(width: 6),
              const Text('Foto (opzionale)',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_photoFile != null || _existingPhotoUrl != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _photoFile = null;
                    _existingPhotoUrl = null;
                  }),
                  tooltip: 'Rimuovi foto',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_photoFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(_photoFile!,
                  height: 120, fit: BoxFit.cover),
            )
          else if (_existingPhotoUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(_existingPhotoUrl!,
                  height: 120, fit: BoxFit.cover),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(source: ImageSource.camera),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Scatta'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _pickPhoto(source: ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: const Text('Galleria'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
