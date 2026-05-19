import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/tour_photos_service.dart';
import '../../../data/models/business.dart';
import '../../../data/models/tour.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/business_repository.dart';
import '../../../data/repositories/tours_repository.dart';
import '../../../data/repositories/tracks_repository.dart';

/// Crea o modifica un tour.
///
/// Flusso:
/// 1. Carica le tracce dell'utente.
/// 2. L'utente inserisce titolo/descrizione, seleziona le tracce, le ordina.
/// 3. Toggle pubblico/privato.
/// 4. Save → ToursRepository.
class TourEditPage extends StatefulWidget {
  final Tour? existing;

  const TourEditPage({super.key, this.existing});

  @override
  State<TourEditPage> createState() => _TourEditPageState();
}

class _TourEditPageState extends State<TourEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _equipmentCtrl = TextEditingController();
  final _naturalNotesCtrl = TextEditingController();
  final TracksRepository _tracksRepo = TracksRepository();
  final ToursRepository _toursRepo = ToursRepository();
  final TourPhotosService _photosSvc = TourPhotosService();
  final BusinessRepository _businessRepo = BusinessRepository();

  List<Track> _availableTracks = [];
  List<String> _selectedIds = [];
  Set<String> _publicTrackIds = const {};
  bool _isPublic = false;

  // Epic 11 — nuovi campi scheda
  String? _coverPhotoUrl;
  List<String> _galleryUrls = const [];
  String? _bestPeriod;
  String? _difficultyGrade;
  // Mappa trackId → businessId rifugio
  Map<String, String> _stageAccommodations = {};
  // Cache business per visualizzazione (id → Business). Popolata on-demand
  // dal picker.
  final Map<String, Business> _accommodationCache = {};
  bool _uploadingCover = false;
  final Set<String> _uploadingGallery = {};

  bool _loading = true;
  bool _saving = false;

  // Opzioni dropdown
  static const _difficultyOptions = <String>[
    'T (Turistico)',
    'E (Escursionistico)',
    'EE (Escursionisti Esperti)',
    'EEA (Esperti con Attrezzatura)',
  ];

  static const _periodOptions = <String>[
    'Gennaio - Marzo',
    'Aprile - Maggio',
    'Giugno - Luglio',
    'Luglio - Agosto',
    'Giugno - Settembre',
    'Settembre - Ottobre',
    'Novembre - Marzo (sci/snow)',
    'Tutto l\'anno',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description ?? '';
      _equipmentCtrl.text = e.equipment ?? '';
      _naturalNotesCtrl.text = e.naturalNotes ?? '';
      _selectedIds = List.of(e.trackIds);
      _isPublic = e.isPublic;
      _coverPhotoUrl = e.coverPhotoUrl;
      _galleryUrls = List.of(e.galleryUrls);
      _bestPeriod = e.bestPeriod;
      _difficultyGrade = e.difficultyGrade;
      _stageAccommodations = Map.of(e.stageAccommodations);
    }
    _loadTracks();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _equipmentCtrl.dispose();
    _naturalNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTracks() async {
    final tracks = await _tracksRepo.getMyTracks();
    final ids = tracks.map((t) => t.id).whereType<String>().toList();
    final publicIds = await _toursRepo.getPublicTrackIds(ids);
    if (!mounted) return;
    setState(() {
      _availableTracks = tracks;
      _publicTrackIds = publicIds;
      _loading = false;
    });
    // Hydrate accommodation cache in background (per mostrare nomi
    // rifugi nelle tile selezionate quando si apre un tour in edit).
    if (_stageAccommodations.isNotEmpty) {
      _hydrateAccommodationCache();
    }
  }

  void _toggleTrack(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _reorderSelected(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _selectedIds.removeAt(oldIndex);
      _selectedIds.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tourSelectAtLeastOne), backgroundColor: AppColors.danger),
      );
      return;
    }

    // Filtra le accommodation alle sole tappe ancora selezionate (se
    // l'utente ha tolto una tappa, ripulisce l'accommodation orfana).
    final cleanedAccommodations = <String, String>{
      for (final entry in _stageAccommodations.entries)
        if (_selectedIds.contains(entry.key)) entry.key: entry.value,
    };

    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await _toursRepo.createTour(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          coverPhotoUrl: _coverPhotoUrl,
          galleryUrls: _galleryUrls,
          bestPeriod: _bestPeriod,
          difficultyGrade: _difficultyGrade,
          equipment: _equipmentCtrl.text.trim().isEmpty
              ? null
              : _equipmentCtrl.text.trim(),
          naturalNotes: _naturalNotesCtrl.text.trim().isEmpty
              ? null
              : _naturalNotesCtrl.text.trim(),
          trackIds: _selectedIds,
          stageAccommodations: cleanedAccommodations,
          isPublic: _isPublic,
        );
      } else {
        await _toursRepo.updateTour(
          widget.existing!.id,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          coverPhotoUrl: _coverPhotoUrl,
          galleryUrls: _galleryUrls,
          bestPeriod: _bestPeriod,
          difficultyGrade: _difficultyGrade,
          equipment: _equipmentCtrl.text.trim().isEmpty
              ? null
              : _equipmentCtrl.text.trim(),
          naturalNotes: _naturalNotesCtrl.text.trim().isEmpty
              ? null
              : _naturalNotesCtrl.text.trim(),
          trackIds: _selectedIds,
          stageAccommodations: cleanedAccommodations,
          isPublic: _isPublic,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tourSaved), backgroundColor: AppColors.success),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
      );
    }
  }

  // ─── PHOTO HELPERS ──────────────────────────────────────────────────
  // Upload cover/gallery a Firebase Storage. Per i nuovi tour usiamo
  // un id pre-generato (Firebase Storage path) → quando si chiama
  // _save il tour viene creato col coverPhotoUrl già pronto.
  String _ensureTourId() {
    return widget.existing?.id ?? 'draft-${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _pickCover() async {
    setState(() => _uploadingCover = true);
    try {
      final url = await _photosSvc.pickAndUpload(
        tourId: _ensureTourId(),
        kind: TourPhotoKind.cover,
      );
      if (url != null && mounted) {
        setState(() => _coverPhotoUrl = url);
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _addGalleryPhoto() async {
    final tempId = 'gal-${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _uploadingGallery.add(tempId));
    try {
      final url = await _photosSvc.pickAndUpload(
        tourId: _ensureTourId(),
        kind: TourPhotoKind.gallery,
      );
      if (url != null && mounted) {
        setState(() => _galleryUrls = [..._galleryUrls, url]);
      }
    } finally {
      if (mounted) setState(() => _uploadingGallery.remove(tempId));
    }
  }

  void _removeGalleryPhoto(String url) {
    setState(() => _galleryUrls = _galleryUrls.where((u) => u != url).toList());
  }

  // ─── ACCOMMODATION PICKER ───────────────────────────────────────────
  Future<void> _pickAccommodation(Track track) async {
    if (track.points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tappa senza coordinate, impossibile cercare rifugi vicini')),
      );
      return;
    }
    // Punto finale della tappa = approssimazione del luogo pernottamento
    final lastPoint = track.points.last;
    final center = LatLng(lastPoint.latitude, lastPoint.longitude);
    showDialog<void>(
      context: context,
      builder: (ctx) => _AccommodationPickerDialog(
        searchCenter: center,
        currentBusinessId: _stageAccommodations[track.id ?? ''],
        repo: _businessRepo,
        onSelected: (business) {
          if (business == null) {
            // Rimuovi
            setState(() {
              _stageAccommodations.remove(track.id);
            });
          } else {
            setState(() {
              _stageAccommodations[track.id!] = business.id!;
              _accommodationCache[business.id!] = business;
            });
          }
        },
      ),
    );
  }

  Business? _accommodationFor(Track track) {
    final bizId = _stageAccommodations[track.id ?? ''];
    if (bizId == null) return null;
    return _accommodationCache[bizId];
  }

  // Per le tappe già con accommodation salvata, fetcho lazy il business
  // dal repo per popolare la cache (per mostrarne il nome nella UI).
  Future<void> _hydrateAccommodationCache() async {
    final missing = _stageAccommodations.values
        .where((id) => !_accommodationCache.containsKey(id))
        .toSet();
    for (final id in missing) {
      try {
        final b = await _businessRepo.getBusiness(id);
        if (b != null && mounted) {
          setState(() => _accommodationCache[id] = b);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.existing == null ? context.l10n.newTour : context.l10n.editTour;

    final selectedTracks = [
      for (final id in _selectedIds)
        _availableTracks.firstWhere(
          (t) => t.id == id,
          orElse: () => Track(
            id: id,
            name: '?',
            points: const [],
            createdAt: DateTime.now(),
          ),
        ),
    ];
    final unselectedTracks =
        _availableTracks.where((t) => t.id != null && !_selectedIds.contains(t.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildCoverSection(),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.tourTitle,
                      hintText: context.l10n.tourTitleHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? context.l10n.tourTitleRequired : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.tourDescription,
                      hintText: 'Una panoramica generale del tour',
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  _buildMetadataSection(),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _equipmentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Equipaggiamento consigliato',
                      hintText: 'Es. scarponi A/B, ramponi leggeri, picozza, '
                          'casco, imbragatura...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _naturalNotesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note storiche / naturalistiche',
                      hintText: 'Cenni geologici, fauna, flora, '
                          'storia del luogo, leggende locali...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 20),
                  _buildGallerySection(),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    value: _isPublic,
                    onChanged: (v) => setState(() => _isPublic = v),
                    title: Text(context.l10n.tourPublic),
                    subtitle: Text(context.l10n.tourPublicHint),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 32),
                  Text(
                    context.l10n.tourSelectTracks,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.tourSelectTracksHint,
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (selectedTracks.isNotEmpty) ...[
                    Text(
                      context.l10n.tourReorderHint,
                      style: TextStyle(color: context.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorder: _reorderSelected,
                      children: [
                        for (var i = 0; i < selectedTracks.length; i++)
                          _SelectedTrackTile(
                            key: ValueKey('sel-${selectedTracks[i].id}'),
                            index: i + 1,
                            track: selectedTracks[i],
                            isPublic: _publicTrackIds.contains(selectedTracks[i].id),
                            accommodation: _accommodationFor(selectedTracks[i]),
                            onPickAccommodation: () =>
                                _pickAccommodation(selectedTracks[i]),
                            onRemove: () => _toggleTrack(selectedTracks[i].id!),
                          ),
                      ],
                    ),
                    const Divider(height: 32),
                  ],
                  if (unselectedTracks.isNotEmpty)
                    ...unselectedTracks.map(
                      (t) => _AvailableTrackTile(
                        track: t,
                        isPublic: _publicTrackIds.contains(t.id),
                        onAdd: () => _toggleTrack(t.id!),
                      ),
                    ),
                  if (_availableTracks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          context.l10n.noTracksSaved,
                          style: TextStyle(color: context.textSecondary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // ─── COVER SECTION ──────────────────────────────────────────────────
  Widget _buildCoverSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Copertina',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: InkWell(
            onTap: _uploadingCover ? null : _pickCover,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                image: _coverPhotoUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(_coverPhotoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _uploadingCover
                  ? const Center(child: CircularProgressIndicator())
                  : _coverPhotoUrl == null
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined,
                                  size: 36, color: AppColors.textMuted),
                              SizedBox(height: 4),
                              Text('Aggiungi copertina',
                                  style: TextStyle(
                                      color: AppColors.textMuted)),
                            ],
                          ),
                        )
                      : Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                icon: const Icon(Icons.edit,
                                    size: 16, color: Colors.white),
                                onPressed: _pickCover,
                              ),
                            ),
                          ),
                        ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── METADATA SECTION (difficoltà + periodo) ────────────────────────
  Widget _buildMetadataSection() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _difficultyGrade,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Difficoltà',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('—'),
              ),
              ..._difficultyOptions.map(
                (d) => DropdownMenuItem<String>(
                  value: d,
                  child: Text(d, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _difficultyGrade = v),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _bestPeriod,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Periodo migliore',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('—'),
              ),
              ..._periodOptions.map(
                (p) => DropdownMenuItem<String>(
                  value: p,
                  child: Text(p, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _bestPeriod = v),
          ),
        ),
      ],
    );
  }

  // ─── GALLERY SECTION ────────────────────────────────────────────────
  Widget _buildGallerySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Galleria foto',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            TextButton.icon(
              onPressed: _uploadingGallery.isNotEmpty ? null : _addGalleryPhoto,
              icon: const Icon(Icons.add_a_photo_outlined, size: 16),
              label: const Text('Aggiungi'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_galleryUrls.isEmpty && _uploadingGallery.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'Aggiungi 5-10 foto del tour: paesaggi, dettagli del percorso, '
              'rifugi attraversati. Una buona gallery fa innamorare prima '
              'ancora di leggere i dati.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          )
        else
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._galleryUrls.map((url) => _GalleryThumb(
                      url: url,
                      onRemove: () => _removeGalleryPhoto(url),
                    )),
                if (_uploadingGallery.isNotEmpty)
                  Container(
                    width: 96,
                    height: 96,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;
  const _GalleryThumb({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: onRemove,
              child: const CircleAvatar(
                radius: 12,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _publicChip(BuildContext context) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.info.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.public, size: 12, color: AppColors.info),
        const SizedBox(width: 3),
        Text(
          context.l10n.publicLabel,
          style: TextStyle(fontSize: 10, color: AppColors.info, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}

class _SelectedTrackTile extends StatelessWidget {
  final int index;
  final Track track;
  final bool isPublic;
  final Business? accommodation;
  final VoidCallback onPickAccommodation;
  final VoidCallback onRemove;

  const _SelectedTrackTile({
    super.key,
    required this.index,
    required this.track,
    required this.isPublic,
    required this.accommodation,
    required this.onPickAccommodation,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                child: Text('$index'),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(track.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (isPublic) ...[
                    const SizedBox(width: 6),
                    _publicChip(context),
                  ],
                ],
              ),
              subtitle: Text(
                '${track.stats.distanceKm.toStringAsFixed(1)} km · '
                '+${track.stats.elevationGain.toStringAsFixed(0)} m',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: AppColors.danger,
                onPressed: onRemove,
              ),
            ),
            // Slot accommodation (pernottamento a fine tappa)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 4),
              child: InkWell(
                onTap: onPickAccommodation,
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  children: [
                    Icon(
                      Icons.bed,
                      size: 16,
                      color: accommodation != null
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        accommodation != null
                            ? 'Pernottamento: ${accommodation!.name}'
                            : 'Aggiungi pernottamento (dove dormi?)',
                        style: TextStyle(
                          fontSize: 12,
                          color: accommodation != null
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                          fontWeight: accommodation != null
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── ACCOMMODATION PICKER DIALOG ────────────────────────────────────
class _AccommodationPickerDialog extends StatefulWidget {
  final LatLng searchCenter;
  final String? currentBusinessId;
  final BusinessRepository repo;
  final void Function(Business?) onSelected;
  const _AccommodationPickerDialog({
    required this.searchCenter,
    required this.currentBusinessId,
    required this.repo,
    required this.onSelected,
  });

  @override
  State<_AccommodationPickerDialog> createState() =>
      _AccommodationPickerDialogState();
}

class _AccommodationPickerDialogState
    extends State<_AccommodationPickerDialog> {
  List<Business> _results = const [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final list = await widget.repo.getNearby(
        lat: widget.searchCenter.latitude,
        lng: widget.searchCenter.longitude,
        radiusKm: 15, // raggio generoso: rifugi anche a 10km dal punto finale
        type: BusinessType.rifugio,
      );
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase();
    final filtered = query.isEmpty
        ? _results
        : _results
            .where((b) =>
                b.name.toLowerCase().contains(query) ||
                (b.location.city?.toLowerCase().contains(query) ?? false))
            .toList();
    return AlertDialog(
      title: const Text('Pernottamento a fine tappa'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            const Text(
              'Rifugi entro 15 km dal punto finale della tappa.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Cerca per nome…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'Nessun rifugio TrailShare entro 15 km. '
                            'Importa la regione da Pannello Admin → Import OSM '
                            'oppure crea la scheda manualmente.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final b = filtered[i];
                            final isSelected =
                                b.id == widget.currentBusinessId;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.bed,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                              ),
                              title: Text(b.name, maxLines: 1),
                              subtitle: Text(
                                b.location.city ?? '—',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle,
                                      color: AppColors.primary, size: 18)
                                  : null,
                              onTap: () {
                                widget.onSelected(b);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.currentBusinessId != null)
          TextButton(
            onPressed: () {
              widget.onSelected(null);
              Navigator.pop(context);
            },
            child: const Text('Rimuovi pernottamento',
                style: TextStyle(color: AppColors.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}

class _AvailableTrackTile extends StatelessWidget {
  final Track track;
  final bool isPublic;
  final VoidCallback onAdd;

  const _AvailableTrackTile({
    required this.track,
    required this.isPublic,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.hiking),
        title: Row(
          children: [
            Expanded(
              child: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (isPublic) ...[
              const SizedBox(width: 6),
              _publicChip(context),
            ],
          ],
        ),
        subtitle: Text(
          '${track.stats.distanceKm.toStringAsFixed(1)} km · +${track.stats.elevationGain.toStringAsFixed(0)} m',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          color: AppColors.primary,
          onPressed: onAdd,
        ),
      ),
    );
  }
}
