import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/business_photos_service.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';
import 'business_location_picker_page.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Form di edit del profilo business (versione MVP).
/// Modifica: nome, descrizione, contatti, indirizzo testuale.
/// TODO iterazioni successive:
/// - upload logo + hero photo + gallery
/// - editor orari giorno-per-giorno
/// - selettore posizione su mappa interattiva
class BusinessEditPage extends StatefulWidget {
  final String businessId;
  const BusinessEditPage({super.key, required this.businessId});

  @override
  State<BusinessEditPage> createState() => _BusinessEditPageState();
}

class _BusinessEditPageState extends State<BusinessEditPage> {
  final _repo = BusinessRepository();
  final _photos = BusinessPhotosService();
  final _formKey = GlobalKey<FormState>();
  String? _logoUrl;
  String? _heroUrl;
  bool _uploadingLogo = false;
  bool _uploadingHero = false;

  late final TextEditingController _name;
  late final TextEditingController _shortDesc;
  late final TextEditingController _description;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _email;
  late final TextEditingController _website;
  late final TextEditingController _instagram;
  late final TextEditingController _address;
  late final TextEditingController _city;

  bool _loading = true;
  bool _saving = false;
  Business? _business;
  Map<String, DayHours> _hours = {};
  // Posizione editabile (lat, lng, geohash). Inizializzata da business
  // al load; aggiornata via picker.
  double? _lat;
  double? _lng;
  String? _geohash;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _shortDesc = TextEditingController();
    _description = TextEditingController();
    _phone = TextEditingController();
    _whatsapp = TextEditingController();
    _email = TextEditingController();
    _website = TextEditingController();
    _instagram = TextEditingController();
    _address = TextEditingController();
    _city = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _shortDesc, _description, _phone, _whatsapp,
      _email, _website, _instagram, _address, _city,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final b = await _repo.getBusiness(widget.businessId);
    if (b == null) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }
    _business = b;
    _logoUrl = b.branding.logoUrl;
    _heroUrl = b.branding.heroPhotoUrl;
    _hours = Map.of(b.openingHours);
    _lat = b.location.lat;
    _lng = b.location.lng;
    _geohash = b.location.geohash;
    _name.text = b.name;
    _shortDesc.text = b.shortDescription ?? '';
    _description.text = b.description ?? '';
    _phone.text = b.contacts.phone ?? '';
    _whatsapp.text = b.contacts.whatsapp ?? '';
    _email.text = b.contacts.email ?? '';
    _website.text = b.contacts.website ?? '';
    _instagram.text = b.contacts.instagram ?? '';
    _address.text = b.location.address ?? '';
    _city.text = b.location.city ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // Helper: se il campo è vuoto, lo cancella esplicitamente dal
      // doc Firestore tramite FieldValue.delete(). Senza questa
      // distinzione, l'update di un campo opzionale a stringa vuota
      // veniva silenziosamente ignorato.
      //
      // ⚠️ Firestore vincolo: FieldValue.delete() può apparire SOLO
      // al top level di un update. Per i nested fields (contacts.*,
      // location.*) usiamo la dot-notation così Firestore aggiorna
      // solo quei campi specifici senza sostituire l'intero oggetto.
      dynamic textOrDelete(String text) =>
          text.trim().isNotEmpty ? text.trim() : FieldValue.delete();

      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'shortDescription': textOrDelete(_shortDesc.text),
        'description': textOrDelete(_description.text),

        // contacts.* — dot-notation per gestire delete dei singoli campi
        'contacts.phone': textOrDelete(_phone.text),
        'contacts.whatsapp': textOrDelete(_whatsapp.text),
        'contacts.email': textOrDelete(_email.text),
        'contacts.website': textOrDelete(_website.text),
        'contacts.instagram': textOrDelete(_instagram.text),

        // location.* — stessa logica
        if (_lat != null) 'location.lat': _lat,
        if (_lng != null) 'location.lng': _lng,
        if (_geohash != null) 'location.geohash': _geohash,
        'location.address': textOrDelete(_address.text),
        'location.city': textOrDelete(_city.text),

        // branding.* — solo update positivo (no delete per ora)
        if (_logoUrl != null) 'branding.logoUrl': _logoUrl,
        if (_heroUrl != null) 'branding.heroPhotoUrl': _heroUrl,

        // openingHours è una map nested completa (tutti i giorni
        // sempre presenti) → replace dell'intero oggetto è ok.
        'openingHours': {
          for (final entry in _hours.entries) entry.key: entry.value.toMap(),
        },
      };
      await _repo.updateBusiness(widget.businessId, patch);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.profileUpdated)),
      );
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
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.editProfile),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.l10n.save),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Foto'),
            _photoEditor(
              label: 'Foto di copertina',
              url: _heroUrl,
              uploading: _uploadingHero,
              kind: BusinessPhotoKind.hero,
              aspectRatio: 16 / 9,
              onUploaded: (u) => setState(() => _heroUrl = u),
              onUploading: (v) => setState(() => _uploadingHero = v),
            ),
            const SizedBox(height: 12),
            _photoEditor(
              label: 'Logo',
              url: _logoUrl,
              uploading: _uploadingLogo,
              kind: BusinessPhotoKind.logo,
              aspectRatio: 1,
              onUploaded: (u) => setState(() => _logoUrl = u),
              onUploading: (v) => setState(() => _uploadingLogo = v),
            ),
            const SizedBox(height: 24),
            _section('Identità'),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _shortDesc,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: context.l10n.shortDescriptionForCards,
                border: OutlineInputBorder(),
              ),
            ),
            TextFormField(
              controller: _description,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Descrizione completa',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _section('Contatti'),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefono',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _whatsapp,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp (es. +39333...)',
                prefixIcon: Icon(Icons.chat),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _website,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Sito web',
                prefixIcon: Icon(Icons.language),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instagram,
              decoration: const InputDecoration(
                labelText: 'Instagram (@username)',
                prefixIcon: Icon(Icons.camera_alt),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _section('Indirizzo'),
            TextFormField(
              controller: _address,
              decoration: InputDecoration(
                labelText: context.l10n.streetLocation,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              decoration: InputDecoration(
                labelText: context.l10n.city,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Posizione GPS modificabile via picker
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gps_fixed,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Posizione sulla mappa',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text(
                          _lat != null && _lng != null
                              ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                              : 'Non impostata',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickLocation,
                    icon: const Icon(Icons.edit_location_alt, size: 18),
                    label: const Text('Sposta'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _section('Orari di apertura'),
            ..._buildHoursEditors(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  static const _dayKeys = [
    'monday', 'tuesday', 'wednesday', 'thursday',
    'friday', 'saturday', 'sunday',
  ];
  static const _dayLabels = {
    'monday': 'Lunedì',
    'tuesday': 'Martedì',
    'wednesday': 'Mercoledì',
    'thursday': 'Giovedì',
    'friday': 'Venerdì',
    'saturday': 'Sabato',
    'sunday': 'Domenica',
  };

  List<Widget> _buildHoursEditors() {
    return _dayKeys.map((key) {
      final h = _hours[key];
      String text;
      if (h == null) {
        text = 'Non impostato';
      } else if (h.closed) {
        text = 'Chiuso';
      } else if (h.open24h) {
        text = 'Aperto 24h';
      } else {
        text = '${h.open} – ${h.close}';
      }
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_dayLabels[key]!),
        subtitle: Text(text,
            style: const TextStyle(color: AppColors.textSecondary)),
        trailing: const Icon(Icons.edit, size: 18),
        onTap: () => _editDayHours(key),
      );
    }).toList();
  }

  Future<void> _pickLocation() async {
    final initial = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : null;
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessLocationPickerPage(initial: initial),
      ),
    );
    if (result == null) return;
    final newLoc = buildLocationUpdate(
      newPos: result,
      oldLocationMap: _business!.location.toMap(),
    );
    setState(() {
      _lat = (newLoc['lat'] as num).toDouble();
      _lng = (newLoc['lng'] as num).toDouble();
      _geohash = newLoc['geohash'] as String;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.positionUpdatedSaveToApply),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _editDayHours(String dayKey) async {
    final current = _hours[dayKey];
    final result = await showModalBottomSheet<DayHours?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _HoursSheet(
        dayLabel: _dayLabels[dayKey]!,
        initial: current,
      ),
    );
    if (result == null) return;
    setState(() {
      // Sentinel: name=='__CLEAR__' significa rimuovi
      if (result.open == '__CLEAR__') {
        _hours.remove(dayKey);
      } else {
        _hours[dayKey] = result;
      }
    });
  }

  Widget _photoEditor({
    required String label,
    required String? url,
    required bool uploading,
    required BusinessPhotoKind kind,
    required double aspectRatio,
    required void Function(String) onUploaded,
    required void Function(bool) onUploading,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
        AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null)
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppColors.border),
                  )
                else
                  const Center(
                    child: Icon(Icons.image,
                        size: 40, color: AppColors.textMuted),
                  ),
                if (uploading)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(
                        color: Colors.white),
                  ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: ElevatedButton.icon(
                    onPressed: uploading
                        ? null
                        : () async {
                            onUploading(true);
                            final newUrl = await _photos.pickAndUpload(
                              businessId: widget.businessId,
                              kind: kind,
                            );
                            if (newUrl != null) {
                              // Cancella la vecchia (best-effort)
                              if (url != null) {
                                _photos.deletePhotoByUrl(url);
                              }
                              onUploaded(newUrl);
                            }
                            onUploading(false);
                          },
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: Text(url == null ? 'Carica' : 'Sostituisci'),
                    style: ElevatedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

enum _HoursMode { open, closed, open24h, unset }

class _HoursSheet extends StatefulWidget {
  final String dayLabel;
  final DayHours? initial;
  const _HoursSheet({required this.dayLabel, this.initial});

  @override
  State<_HoursSheet> createState() => _HoursSheetState();
}

class _HoursSheetState extends State<_HoursSheet> {
  late _HoursMode _mode;
  TimeOfDay _open = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _close = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    final h = widget.initial;
    if (h == null) {
      _mode = _HoursMode.unset;
    } else if (h.closed) {
      _mode = _HoursMode.closed;
    } else if (h.open24h) {
      _mode = _HoursMode.open24h;
    } else {
      _mode = _HoursMode.open;
      _open = _parseTime(h.open) ?? _open;
      _close = _parseTime(h.close) ?? _close;
    }
  }

  TimeOfDay? _parseTime(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(bool open) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: open ? _open : _close,
      builder: (ctx, child) =>
          MediaQuery(data: const MediaQueryData(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return;
    setState(() {
      if (open) {
        _open = picked;
      } else {
        _close = picked;
      }
    });
  }

  void _save() {
    DayHours? result;
    switch (_mode) {
      case _HoursMode.unset:
        // Sentinel per rimozione
        result = const DayHours(open: '__CLEAR__');
        break;
      case _HoursMode.closed:
        result = const DayHours(closed: true);
        break;
      case _HoursMode.open24h:
        result = const DayHours(open24h: true);
        break;
      case _HoursMode.open:
        result = DayHours(open: _fmt(_open), close: _fmt(_close));
        break;
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.dayLabel,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          RadioListTile<_HoursMode>(
            value: _HoursMode.open,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('Aperto'),
            contentPadding: EdgeInsets.zero,
          ),
          if (_mode == _HoursMode.open)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(true),
                      child: Text('Da ${_fmt(_open)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(false),
                      child: Text('A ${_fmt(_close)}'),
                    ),
                  ),
                ],
              ),
            ),
          RadioListTile<_HoursMode>(
            value: _HoursMode.open24h,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('Aperto 24h'),
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<_HoursMode>(
            value: _HoursMode.closed,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('Chiuso'),
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<_HoursMode>(
            value: _HoursMode.unset,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: Text(context.l10n.notSet),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Salva'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
