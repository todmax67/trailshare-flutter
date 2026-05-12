import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geohash_util.dart';
import '../../../data/models/business.dart';
import 'business_profile_page.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Pagina admin-only per creare uno Spazio Pro nuovo.
/// Per ora si richiede solo il minimo: nome, tipo, lat/lng, ownerId.
/// L'owner poi rifinisce il profilo da BusinessEditPage.
///
/// Lo creiamo SU FIRESTORE direttamente con i campi necessari (incluso
/// follower/post/review counter a 0 e status='active'). Ricalcoliamo
/// lo slug client-side e gestiamo la collisione con suffisso numerico.
class BusinessCreatePage extends StatefulWidget {
  const BusinessCreatePage({super.key});

  @override
  State<BusinessCreatePage> createState() => _BusinessCreatePageState();
}

class _BusinessCreatePageState extends State<BusinessCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _ownerUid = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();

  BusinessType _type = BusinessType.rifugio;
  BusinessTier _tier = BusinessTier.verified;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name, _ownerEmail, _ownerUid, _lat, _lng, _city, _address
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _slugify(String input) {
    final s = input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[àáâãä]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r"[^a-z0-9\s-]"), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'spazio' : s;
  }

  Future<String> _uniqueSlug(FirebaseFirestore db, String base) async {
    String candidate = base;
    int n = 1;
    while (true) {
      final s = await db.collection('businesses')
          .where('slug', isEqualTo: candidate)
          .limit(1)
          .get();
      if (s.docs.isEmpty) return candidate;
      n++;
      candidate = '$base-$n';
      if (n > 100) {
        return '$base-${DateTime.now().millisecondsSinceEpoch}';
      }
    }
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    final ownerUid = _ownerUid.text.trim();
    if (ownerUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('UID owner richiesto')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final slug = await _uniqueSlug(db, _slugify(_name.text));
      final lat = double.parse(_lat.text);
      final lng = double.parse(_lng.text);
      final geohash = GeoHashUtil.encode(lat, lng);

      final doc = {
        'name': _name.text.trim(),
        'slug': slug,
        'type': _type.name,
        'tier': _tier.name,
        'status': 'active',
        'ownerId': ownerUid,
        'location': {
          'lat': lat,
          'lng': lng,
          'geohash': geohash,
          if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
          if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
        },
        'followerCount': 0,
        'postsCount': 0,
        'reviewCount': 0,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      };
      final ref = await db.collection('businesses').add(doc);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Creato: ${ref.id}')),
      );

      // Apri subito il profilo per rifinire
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessProfilePage(businessId: ref.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.genericErrorWith(e.toString())),
          backgroundColor: AppColors.danger,
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Crea Spazio Pro')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              color: Color(0xFFFFF3CD),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pagina admin. Disponibile solo agli amministratori finché non attiviamo il self-serve.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome attività',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BusinessType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                border: OutlineInputBorder(),
              ),
              items: BusinessType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text('${t.icon} ${t.displayName}'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BusinessTier>(
              initialValue: _tier,
              decoration: const InputDecoration(
                labelText: 'Tier',
                border: OutlineInputBorder(),
              ),
              items: BusinessTier.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.displayName),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _tier = v);
              },
            ),
            const SizedBox(height: 24),
            const Text('Owner',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ownerUid,
              decoration: InputDecoration(
                labelText: 'UID Firebase del proprietario',
                border: const OutlineInputBorder(),
                helperText: 'Trovalo da Firebase Auth Console',
                suffixIcon: myUid != null
                    ? IconButton(
                        icon: const Icon(Icons.person),
                        tooltip: 'Usa il mio UID',
                        onPressed: () => _ownerUid.text = myUid,
                      )
                    : null,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ownerEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email owner (solo riferimento, non salvata)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Posizione',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Latitudine',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Obbl.';
                      final d = double.tryParse(v);
                      if (d == null || d.abs() > 90) return 'Invalido';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Longitudine',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Obbl.';
                      final d = double.tryParse(v);
                      if (d == null || d.abs() > 180) return 'Invalido';
                      return null;
                    },
                  ),
                ),
              ],
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
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Indirizzo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _saving ? null : _create,
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child:
                          CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_business),
              label: Text(_saving ? 'Creazione...' : 'Crea Spazio Pro'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
