import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../data/repositories/groups_repository.dart';

/// Wizard di onboarding "Crea gruppo Business" — flusso lead-gen
/// pre-Stripe.
///
/// 3 step:
/// 1. **Info gruppo**: nome, descrizione, visibility
/// 2. **Tier**: selettore Verified/Pro/Enterprise con pricing display.
///    Stripe non è ancora attivo → tutti i tier sono trattati come
///    trial 14gg, con copy che invita al contatto commerciale per
///    l'attivazione vera. Quando arriverà Stripe il bottone "Conferma"
///    aprirà il checkout.
/// 3. **Successo**: invite code condivisibile, CTA "Vai al gruppo" /
///    "Personalizza brand".
class WebGroupOnboardingPage extends StatefulWidget {
  const WebGroupOnboardingPage({super.key});

  @override
  State<WebGroupOnboardingPage> createState() =>
      _WebGroupOnboardingPageState();
}

enum _Tier { verified, pro, enterprise }

extension _TierX on _Tier {
  String get label {
    switch (this) {
      case _Tier.verified:
        return 'Verified';
      case _Tier.pro:
        return 'Pro';
      case _Tier.enterprise:
        return 'Enterprise';
    }
  }

  String get monthlyPrice {
    switch (this) {
      case _Tier.verified:
        return '€19,99/mese';
      case _Tier.pro:
        return '€49,99/mese';
      case _Tier.enterprise:
        return 'Personalizzato';
    }
  }

  String get yearlyPrice {
    switch (this) {
      case _Tier.verified:
        return '€199/anno';
      case _Tier.pro:
        return '€499/anno';
      case _Tier.enterprise:
        return 'Contattaci';
    }
  }

  List<String> get features {
    switch (this) {
      case _Tier.verified:
        return [
          'Logo e cover personalizzati',
          'Codice invito + card brandizzata',
          'Statistiche base',
          'Solo founder admin',
        ];
      case _Tier.pro:
        return [
          'Tutto di Verified',
          'Statistiche avanzate (trend, breakdown, top membri)',
          'Pinned post',
          'Fino a 5 co-admin',
          'Export CSV illimitato',
        ];
      case _Tier.enterprise:
        return [
          'Tutto di Pro',
          'Co-admin illimitati',
          'SLA dedicato',
          'Onboarding personalizzato',
          'Integrazione custom',
        ];
    }
  }
}

class _WebGroupOnboardingPageState extends State<WebGroupOnboardingPage> {
  final _repo = GroupsRepository();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int _step = 0;
  _Tier _tier = _Tier.verified;
  String _visibility = 'secret';
  bool _submitting = false;

  // Result
  String? _createdGroupId;
  String? _createdInviteCode;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_step == 0) {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      setState(() => _step = 2);
      return;
    }
    // Step 2 — creazione vera
    setState(() => _submitting = true);
    final groupId = await _repo.createGroup(
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim(),
      visibility: _visibility,
    );
    if (groupId == null) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Errore creazione gruppo'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    // Tier: tutti partono come trial 14gg pre-Stripe. La conversione
    // a tier reale richiederà l'attivazione manuale post-contatto
    // (o automatica via webhook Stripe quando attivato).
    await _repo.setBusinessTier(groupId, 'trial');
    final code = await _repo.ensureInviteCode(groupId);

    if (!mounted) return;
    setState(() {
      _createdGroupId = groupId;
      _createdInviteCode = code;
      _submitting = false;
      _step = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Crea gruppo Business'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(_createdGroupId),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            children: [
              _Stepper(current: _step),
              const SizedBox(height: 24),
              _buildStepContent(),
              const SizedBox(height: 24),
              if (_step != 3) _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildStepInfo();
      case 1:
        return _buildStepTier();
      case 2:
        return _buildStepConfirm();
      case 3:
      default:
        return _buildStepSuccess();
    }
  }

  // ────────────────────────────────────────────────────────────
  // STEP 0 — INFO
  // ────────────────────────────────────────────────────────────

  Widget _buildStepInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Informazioni del gruppo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Iniziamo con i dati base. Potrai modificarli in qualsiasi '
              'momento da Personalizza.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              decoration: _input('Nome del gruppo *', 'Es. CAI Bergamo'),
              maxLength: 60,
              validator: (v) {
                if (v == null || v.trim().length < 3) {
                  return 'Almeno 3 caratteri';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: _input(
                'Descrizione',
                'Cosa fate, dove vi trovate, chi può unirsi',
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 12),
            const Text(
              'Visibilità',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _VisibilityPicker(
              value: _visibility,
              onChanged: (v) => setState(() => _visibility = v),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // STEP 1 — TIER
  // ────────────────────────────────────────────────────────────

  Widget _buildStepTier() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Scegli un piano',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tutti i nuovi gruppi partono con un trial gratuito di '
                '14 giorni. Per l\'attivazione del piano vero e proprio '
                'ti contatteremo via email — i pagamenti online '
                'arrivano a breve.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final t in _Tier.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _TierCard(
                    tier: t,
                    selected: _tier == t,
                    onTap: () => setState(() => _tier = t),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────
  // STEP 2 — CONFIRM
  // ────────────────────────────────────────────────────────────

  Widget _buildStepConfirm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Conferma e crea',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          _summaryRow('Nome', _nameCtrl.text.trim()),
          if (_descCtrl.text.trim().isNotEmpty)
            _summaryRow('Descrizione', _descCtrl.text.trim()),
          _summaryRow('Visibilità',
              _visibility == 'public' ? 'Pubblica' : 'Privata'),
          _summaryRow('Piano scelto',
              '${_tier.label} — ${_tier.monthlyPrice}'),
          _summaryRow('Periodo trial', '14 giorni gratis'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.email_outlined,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Dopo la creazione ti contatteremo via email per '
                    'attivare il piano e generare la fattura. Nessun '
                    'addebito durante il trial.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // STEP 3 — SUCCESS
  // ────────────────────────────────────────────────────────────

  Widget _buildStepSuccess() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D5B).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              size: 40,
              color: Color(0xFF2E7D5B),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${_nameCtrl.text.trim()} è online!',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Trial Verified attivo per 14 giorni. Ti scriveremo via '
            'email per finalizzare il piano scelto.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          if (_createdInviteCode != null) ...[
            const Text(
              'Codice invito condivisibile',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                await Clipboard.setData(
                    ClipboardData(text: _createdInviteCode!));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Codice copiato negli appunti'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _createdInviteCode!,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: AppColors.primary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.content_copy,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_createdGroupId),
            icon: const Icon(Icons.dashboard_outlined),
            label: const Text('Vai alla dashboard del gruppo'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // BOTTOM BAR
  // ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Row(
      children: [
        if (_step > 0)
          OutlinedButton.icon(
            onPressed: _submitting
                ? null
                : () => setState(() => _step--),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Indietro'),
          ),
        const Spacer(),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 14,
            ),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_step == 2 ? 'Crea gruppo' : 'Avanti'),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────
  // STYLE HELPERS
  // ────────────────────────────────────────────────────────────

  static const _cardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(14)),
    border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
  );

  InputDecoration _input(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: AppColors.primary, width: 1.5),
        ),
      );
}

// ============================================================
// STEPPER (custom horizontal)
// ============================================================

class _Stepper extends StatelessWidget {
  final int current;
  const _Stepper({required this.current});

  @override
  Widget build(BuildContext context) {
    const labels = ['Info', 'Piano', 'Conferma', 'Fatto'];
    return Row(
      children: [
        for (int i = 0; i < labels.length; i++) ...[
          _StepDot(
            index: i,
            label: labels[i],
            current: current,
          ),
          if (i < labels.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: i < current
                    ? AppColors.primary
                    : AppColors.border,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final String label;
  final int current;
  const _StepDot({
    required this.index,
    required this.label,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    final color = done || active ? AppColors.primary : AppColors.border;
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: done || active ? color : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : AppColors.textMuted,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TIER CARD
// ============================================================

class _TierCard extends StatelessWidget {
  final _Tier tier;
  final bool selected;
  final VoidCallback onTap;
  const _TierCard({
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  tier.label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle,
                      color: AppColors.primary, size: 20),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tier.monthlyPrice,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            Text(
              tier.yearlyPrice,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            for (final f in tier.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check,
                      size: 14,
                      color: Color(0xFF2E7D5B),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// VISIBILITY PICKER
// ============================================================

class _VisibilityPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _VisibilityPicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _option(
            value: 'secret',
            label: 'Privata',
            icon: Icons.lock_outline,
            description: 'Solo chi ha il codice invito può unirsi',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _option(
            value: 'public',
            label: 'Pubblica',
            icon: Icons.public,
            description: 'Visibile nelle ricerche e nelle scoperte',
          ),
        ),
      ],
    );
  }

  Widget _option({
    required String value,
    required String label,
    required IconData icon,
    required String description,
  }) {
    final selected = this.value == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
