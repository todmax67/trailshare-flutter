import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/business_funnel_tracker.dart';
import '../../data/models/business.dart';

/// Epic 7.H5 — Form di rivendicazione per schede `unclaimed`.
///
/// Widget condiviso da:
/// - `BusinessClaimRequestPage` (mobile, in app)
/// - `WebClaimRequestPage` (web, da landing pubblica `/b/{slug}`)
///
/// Il client crea un doc su `business_claim_requests/{auto}` con
/// `status='pending'`. Lo trigger Cloud Function `onClaimRequestCreated`
/// invia un'email al team admin. L'admin review da web admin panel
/// e chiama `approveClaimRequest` o `rejectClaimRequest`.
///
/// Niente verifica P.IVA automatica per ora: l'admin valuta i dati
/// forniti (email aziendale che combacia col dominio del sito,
/// telefono pubblico OSM, riconoscibilità del richiedente).
class BusinessClaimRequestForm extends StatefulWidget {
  final Business business;

  /// Callback opzionale dopo submit ok: il chiamante può fare pop +
  /// snackbar, oppure routing verso una pagina di "richiesta inviata".
  /// Se null, mostriamo un dialog di conferma e ritorniamo a indietro.
  final VoidCallback? onSubmitted;

  const BusinessClaimRequestForm({
    super.key,
    required this.business,
    this.onSubmitted,
  });

  @override
  State<BusinessClaimRequestForm> createState() =>
      _BusinessClaimRequestFormState();
}

class _BusinessClaimRequestFormState extends State<BusinessClaimRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _vatCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _agreedTos = false;
  bool _busy = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    // Pre-compila email se l'utente è loggato — flow tipico.
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) _emailCtrl.text = user!.email!;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      _nameCtrl.text = user.displayName!.trim();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _roleCtrl,
      _vatCtrl,
      _emailCtrl,
      _phoneCtrl,
      _websiteCtrl,
      _notesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedTos) {
      setState(() => _serverError =
          'Devi confermare di essere il gestore o un suo rappresentante.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _serverError =
          'Devi essere loggato per inviare la richiesta. Effettua il login e riprova.');
      return;
    }

    setState(() {
      _busy = true;
      _serverError = null;
    });
    try {
      await FirebaseFirestore.instance.collection('business_claim_requests').add({
        'businessId': widget.business.id,
        'businessName': widget.business.name,
        'businessSlug': widget.business.slug,
        'status': 'pending',
        'requesterUid': user.uid,
        'requesterName': _nameCtrl.text.trim(),
        'requesterRole': _roleCtrl.text.trim(),
        'requesterVat': _vatCtrl.text.trim(),
        'requesterEmail': _emailCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty)
          'requesterPhone': _phoneCtrl.text.trim(),
        if (_websiteCtrl.text.trim().isNotEmpty)
          'requesterWebsite': _websiteCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      // 7.H12 — funnel event claim_completed (best-effort)
      final bizId = widget.business.id;
      if (bizId != null) {
        BusinessFunnelTracker().trackClaimCompleted(bizId);
      }
      if (!mounted) return;
      if (widget.onSubmitted != null) {
        widget.onSubmitted!();
      } else {
        await _showConfirmation();
        if (mounted) Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = 'Errore invio: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showConfirmation() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline,
            color: AppColors.success, size: 48),
        title: const Text('Richiesta inviata'),
        content: Text(
          'Abbiamo ricevuto la tua richiesta per "${widget.business.name}". '
          'Il team TrailShare la verificherà entro 48 ore lavorative e ti '
          'risponderà via email a ${_emailCtrl.text.trim()}.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.storefront, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stai rivendicando',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.business.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _field(_nameCtrl, 'Il tuo nome e cognome *',
              validator: _notEmpty),
          const SizedBox(height: 12),
          _field(_roleCtrl, 'Ruolo (es. titolare, gestore, manager) *',
              validator: _notEmpty),
          const SizedBox(height: 12),
          _field(_vatCtrl, 'P.IVA o Codice Fiscale *',
              validator: _notEmpty),
          const SizedBox(height: 12),
          _field(_emailCtrl, 'Email aziendale *',
              keyboard: TextInputType.emailAddress, validator: _validEmail),
          const SizedBox(height: 12),
          _field(_phoneCtrl, 'Telefono (opzionale)',
              keyboard: TextInputType.phone),
          const SizedBox(height: 12),
          _field(_websiteCtrl, 'Sito web ufficiale (opzionale)',
              keyboard: TextInputType.url),
          const SizedBox(height: 12),
          _field(_notesCtrl, 'Note per il team (opzionale)', maxLines: 3),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _agreedTos,
            onChanged: (v) => setState(() => _agreedTos = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Confermo di essere il gestore di questa attività o un suo '
              'rappresentante autorizzato.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (_serverError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Text(
                _serverError!,
                style: const TextStyle(
                    color: AppColors.danger, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_busy ? 'Invio in corso...' : 'Invia richiesta'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tempi di verifica: entro 48 ore lavorative. Riceverai una '
            'email con l\'esito (approvazione o richiesta di chiarimenti). '
            'I dati sono trattati in conformità all\'art. 6.1.b GDPR '
            '(esecuzione di un contratto / misure pre-contrattuali).',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: validator,
    );
  }

  String? _notEmpty(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null;

  String? _validEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email obbligatoria';
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(v.trim()) ? null : 'Email non valida';
  }
}
