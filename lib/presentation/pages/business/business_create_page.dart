import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geohash_util.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/admin_repository.dart';
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

  /// 7.H1 — Self-claim flow.
  /// Default true perché lo use case principale di chi crea da admin
  /// è proprio inserire una scheda PER CONTO di un rifugista non
  /// ancora autonomo. Se il rifugista è già pronto a gestirla in
  /// autonomia (ha account TrailShare), basta togliere la spunta e
  /// l'UID owner inserito sarà quello finale.
  bool _pendingSelfManagement = true;
  // Tri-state: null = sto verificando, true = admin, false = bloccato.
  // Default null forza un loader iniziale invece di mostrare il form
  // prima del check (fail-closed UX).
  bool? _isAdminCheck;

  @override
  void initState() {
    super.initState();
    _verifyAdmin();
  }

  Future<void> _verifyAdmin() async {
    final ok = await AdminRepository.isCurrentUserAdmin();
    if (!mounted) return;
    setState(() => _isAdminCheck = ok);
    if (!ok) {
      // Pop con snackbar invece di lasciare un guscio vuoto: l'utente
      // ha provato a entrare in un'area che non gli compete, lo
      // riportiamo subito indietro con feedback chiaro.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Accesso riservato agli amministratori TrailShare.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      // Delay minimo perché lo snackbar sia visibile prima del pop.
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

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
        if (_pendingSelfManagement) 'pendingSelfManagement': true,
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
    // Gate: finché non sappiamo se l'utente è admin, loader. Se NON
    // è admin mostriamo il messaggio bloccante (intanto _verifyAdmin
    // ha schedulato il pop). Solo se confermato admin → form completo.
    if (_isAdminCheck == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isAdminCheck == false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Accesso negato')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 56, color: AppColors.danger),
                SizedBox(height: 16),
                Text(
                  'Pagina riservata agli amministratori',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Solo gli amministratori TrailShare possono creare '
                  'nuovi Spazi Pro. Contatta info@trailshare.app per '
                  'attivare la tua vetrina.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
            const SizedBox(height: 20),
            // 7.H1 — Self-claim toggle. Default ON perché lo use case
            // tipico è "inserisco per conto del rifugista che mi ha
            // detto di sì a voce". Spegni solo se la persona è già
            // autonoma ed ha account TrailShare (UID owner = il suo).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _pendingSelfManagement,
                        onChanged: (v) => setState(
                            () => _pendingSelfManagement = v ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'Sto inserendo per conto del proprietario',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _pendingSelfManagement
                          ? 'Dopo la creazione vai su Pannello Admin → '
                              '"Schede in attesa di self-claim" per '
                              'generare il link da mandare al proprietario.'
                          : 'Il proprietario gestirà da subito '
                              'autonomamente (UID owner sopra deve essere il suo).',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
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
