import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/tour_photos_service.dart';
import '../../data/models/tour.dart';
import '../../data/models/track.dart';
import '../../data/repositories/tours_repository.dart';
import '../../data/repositories/tracks_repository.dart';

/// Editor Tour per il web (MVP gestione): campi testuali + selezione/ordinamento
/// tappe dalle proprie tracce + pubblica/ritira + elimina. NIENTE upload
/// immagini (fase 2). tourId null = creazione.
class WebTourEditPage extends StatefulWidget {
  final String? tourId;
  const WebTourEditPage({super.key, this.tourId});

  @override
  State<WebTourEditPage> createState() => _WebTourEditPageState();
}

class _WebTourEditPageState extends State<WebTourEditPage> {
  final _repo = ToursRepository();
  final _tracksRepo = TracksRepository();
  final _photos = TourPhotosService();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _periodCtrl = TextEditingController();
  final _equipCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  TourType _type = TourType.consecutive;
  String? _difficulty;
  bool _isPublic = false;
  final List<String> _stageIds = [];

  // Immagini (fase 2). In creazione, alla prima immagine creo una bozza per
  // avere un tourId (path Storage tours/{id}/...): _createdId la traccia.
  String? _coverUrl;
  final List<String> _galleryUrls = [];
  String? _createdId;
  bool _uploading = false;

  String? get _effectiveId => widget.tourId ?? _createdId;

  final Map<String, Track> _trackById = {};
  List<Track> _allTracks = [];

  bool _loading = true;
  bool _saving = false;
  bool get _isEdit => widget.tourId != null;

  static const _difficulties = ['T', 'E', 'EE', 'EEA', 'Facile', 'Medio', 'Difficile'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _periodCtrl.dispose();
    _equipCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tracks = await _tracksRepo.getMyTracks();
    for (final t in tracks) {
      if (t.id != null) _trackById[t.id!] = t;
    }
    if (_isEdit) {
      final tour = await _repo.getTourById(widget.tourId!);
      if (tour != null) {
        _titleCtrl.text = tour.title;
        _descCtrl.text = tour.description ?? '';
        _periodCtrl.text = tour.bestPeriod ?? '';
        _equipCtrl.text = tour.equipment ?? '';
        _notesCtrl.text = tour.naturalNotes ?? '';
        _type = tour.type;
        _difficulty = tour.difficultyGrade;
        _isPublic = tour.isPublic;
        _stageIds.addAll(tour.trackIds);
        _coverUrl = tour.coverPhotoUrl;
        _galleryUrls.addAll(tour.galleryUrls);
      }
    }
    if (mounted) {
      setState(() {
        _allTracks = tracks;
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.success,
    ));
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Inserisci un titolo', error: true);
      return;
    }
    if (_stageIds.isEmpty) {
      _snack('Aggiungi almeno una tappa (traccia)', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final desc = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
      final period =
          _periodCtrl.text.trim().isEmpty ? null : _periodCtrl.text.trim();
      final equip =
          _equipCtrl.text.trim().isEmpty ? null : _equipCtrl.text.trim();
      final notes =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

      final id = _effectiveId;
      if (id != null) {
        await _repo.updateTour(
          id,
          title: title,
          description: desc,
          type: _type,
          bestPeriod: period,
          difficultyGrade: _difficulty,
          equipment: equip,
          naturalNotes: notes,
          trackIds: _stageIds,
          coverPhotoUrl: _coverUrl,
          galleryUrls: _galleryUrls,
          isPublic: _isPublic,
        );
      } else {
        await _repo.createTour(
          title: title,
          description: desc,
          type: _type,
          bestPeriod: period,
          difficultyGrade: _difficulty,
          equipment: equip,
          naturalNotes: notes,
          trackIds: _stageIds,
          coverPhotoUrl: _coverUrl,
          galleryUrls: _galleryUrls,
          isPublic: _isPublic,
        );
      }
      _snack('Tour salvato');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Errore: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina Tour'),
        content: Text(
            'Eliminare "${_titleCtrl.text}"? L\'operazione non è reversibile.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteTour(widget.tourId!);
      _snack('Tour eliminato');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Errore: $e', error: true);
    }
  }

  void _moveStage(int index, int delta) {
    final to = index + delta;
    if (to < 0 || to >= _stageIds.length) return;
    setState(() {
      final id = _stageIds.removeAt(index);
      _stageIds.insert(to, id);
    });
  }

  Future<void> _addStageDialog() async {
    final available =
        _allTracks.where((t) => t.id != null && !_stageIds.contains(t.id)).toList();
    if (available.isEmpty) {
      _snack('Nessun\'altra traccia disponibile da aggiungere');
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Aggiungi tappa'),
        children: available.map((t) {
          final km = (t.stats.distance / 1000).toStringAsFixed(1);
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, t.id),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.route, size: 20),
              title: Text(t.name),
              subtitle: Text('$km km'),
            ),
          );
        }).toList(),
      ),
    );
    if (picked != null) {
      setState(() => _stageIds.add(picked));
    }
  }

  // Garantisce un tourId per il path Storage: in creazione salva una bozza.
  Future<String?> _ensureTourId() async {
    if (_effectiveId != null) return _effectiveId;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Inserisci un titolo prima di aggiungere immagini', error: true);
      return null;
    }
    if (_stageIds.isEmpty) {
      _snack('Aggiungi almeno una tappa prima delle immagini', error: true);
      return null;
    }
    try {
      final id = await _repo.createTour(
        title: title,
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        type: _type,
        bestPeriod:
            _periodCtrl.text.trim().isEmpty ? null : _periodCtrl.text.trim(),
        difficultyGrade: _difficulty,
        equipment:
            _equipCtrl.text.trim().isEmpty ? null : _equipCtrl.text.trim(),
        naturalNotes:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        trackIds: _stageIds,
        isPublic: _isPublic,
      );
      setState(() => _createdId = id);
      return id;
    } catch (e) {
      _snack('Errore creazione bozza: $e', error: true);
      return null;
    }
  }

  Future<void> _uploadCover() async {
    final id = await _ensureTourId();
    if (id == null) return;
    setState(() => _uploading = true);
    final url = await _photos.pickAndUpload(tourId: id, kind: TourPhotoKind.cover);
    if (url != null) {
      _coverUrl = url;
      await _repo.updateTour(id, coverPhotoUrl: url);
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _addGalleryPhoto() async {
    final id = await _ensureTourId();
    if (id == null) return;
    setState(() => _uploading = true);
    final url =
        await _photos.pickAndUpload(tourId: id, kind: TourPhotoKind.gallery);
    if (url != null) {
      _galleryUrls.add(url);
      await _repo.updateTour(id, galleryUrls: _galleryUrls);
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _removeGallery(int i) async {
    setState(() => _galleryUrls.removeAt(i));
    final id = _effectiveId;
    if (id != null) {
      await _repo.updateTour(id, galleryUrls: _galleryUrls);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Modifica Tour' : 'Nuovo Tour'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Elimina',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save, size: 18),
              label: const Text('Salva'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _field('Titolo', _titleCtrl),
                    _field('Descrizione', _descCtrl, maxLines: 4),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<TourType>(
                            initialValue: _type,
                            decoration: _dec('Tipo'),
                            items: const [
                              DropdownMenuItem(
                                  value: TourType.consecutive,
                                  child: Text('Consecutivo (tappe in sequenza)')),
                              DropdownMenuItem(
                                  value: TourType.collection,
                                  child: Text('Collezione (tracce a tema)')),
                            ],
                            onChanged: (v) =>
                                setState(() => _type = v ?? TourType.consecutive),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _difficulty,
                            decoration: _dec('Difficoltà'),
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null, child: Text('—')),
                              ..._difficulties.map((d) => DropdownMenuItem(
                                  value: d, child: Text(d))),
                            ],
                            onChanged: (v) => setState(() => _difficulty = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field('Periodo migliore (es. Giugno - Settembre)',
                        _periodCtrl),
                    _field('Attrezzatura', _equipCtrl, maxLines: 2),
                    _field('Note storiche / naturalistiche', _notesCtrl,
                        maxLines: 4),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Pubblico (visibile nella community)'),
                      value: _isPublic,
                      onChanged: (v) => setState(() => _isPublic = v),
                    ),
                    const Divider(height: 32),
                    _imagesSection(),
                    const Divider(height: 32),
                    _stagesSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _imagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Immagini',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (_uploading)
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Cover (16:9) e galleria. In creazione, la prima immagine '
            'salva una bozza (servono titolo + 1 tappa).',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _coverUrl != null
                ? Stack(fit: StackFit.expand, children: [
                    CachedNetworkImage(
                        imageUrl: _coverUrl!, fit: BoxFit.cover),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: FilledButton.tonalIcon(
                        onPressed: _uploading ? null : _uploadCover,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Cambia cover'),
                      ),
                    ),
                  ])
                : InkWell(
                    onTap: _uploading ? null : _uploadCover,
                    child: Container(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                size: 32, color: AppColors.primary),
                            SizedBox(height: 6),
                            Text('Carica cover'),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(
            child: Text('Galleria',
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          TextButton.icon(
            onPressed: _uploading ? null : _addGalleryPhoto,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Aggiungi foto'),
          ),
        ]),
        const SizedBox(height: 6),
        if (_galleryUrls.isEmpty)
          const Text('Nessuna foto in galleria.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_galleryUrls.length, (i) {
              return SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                          imageUrl: _galleryUrls[i], fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: IconButton(
                        icon: const Icon(Icons.cancel,
                            size: 20, color: AppColors.danger),
                        onPressed: () => _removeGallery(i),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _stagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Tappe (${_stageIds.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: _addStageDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Aggiungi tappa'),
            ),
          ],
        ),
        const Text(
          'Le tappe sono tue tracce, nell\'ordine del percorso.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (_stageIds.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Nessuna tappa. Aggiungine almeno una.',
                style: TextStyle(color: AppColors.textMuted)),
          )
        else
          ...List.generate(_stageIds.length, (i) {
            final id = _stageIds[i];
            final track = _trackById[id];
            final name = track?.name ?? 'Traccia $id';
            final km = track != null
                ? '${(track.stats.distance / 1000).toStringAsFixed(1)} km'
                : '';
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primary,
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12)),
                ),
                title: Text(name),
                subtitle: km.isEmpty ? null : Text(km),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: i == 0 ? null : () => _moveStage(i, -1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      onPressed: i == _stageIds.length - 1
                          ? null
                          : () => _moveStage(i, 1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _stageIds.removeAt(i)),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      );

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: _dec(label),
      ),
    );
  }
}
