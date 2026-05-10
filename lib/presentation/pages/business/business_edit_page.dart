import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';

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
  final _formKey = GlobalKey<FormState>();

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
      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        if (_shortDesc.text.trim().isNotEmpty)
          'shortDescription': _shortDesc.text.trim(),
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
        'contacts': {
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          if (_whatsapp.text.trim().isNotEmpty)
            'whatsapp': _whatsapp.text.trim(),
          if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
          if (_website.text.trim().isNotEmpty)
            'website': _website.text.trim(),
          if (_instagram.text.trim().isNotEmpty)
            'instagram': _instagram.text.trim(),
        },
        'location': {
          ..._business!.location.toMap(),
          if (_address.text.trim().isNotEmpty)
            'address': _address.text.trim(),
          if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
        },
      };
      await _repo.updateBusiness(widget.businessId, patch);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profilo aggiornato')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
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
        title: const Text('Modifica profilo'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salva'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
              decoration: const InputDecoration(
                labelText: 'Descrizione breve (per le card)',
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
              decoration: const InputDecoration(
                labelText: 'Via / Località',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              decoration: const InputDecoration(
                labelText: 'Città',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Posizione GPS attuale: salvata. Per modificarla contatta il supporto (lo strumento mappa-picker arriva nella prossima versione).',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
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
