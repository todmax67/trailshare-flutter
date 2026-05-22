import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../business_web_app.dart';

/// Epic 7.H1 — Pagina di self-claim aperta dal link condiviso via
/// WhatsApp/email al gestore reale di uno Spazio Pro inserito dal
/// team TrailShare per suo conto.
///
/// URL: `https://app.trailshare.app/claim-self/{businessId}?t={token}`
///
/// Flow:
/// 1. L'utente arriva qui — AuthGate ha già garantito che è loggato.
/// 2. Mostro nome scheda + utente loggato + bottone "Sì, rivendico".
/// 3. Click → chiama `acceptSelfClaim` Cloud Function.
/// 4. Success → mostra messaggio + bottone "Vai alla mia scheda".
/// 5. Errore (token scaduto / consumato / mismatch) → messaggio
///    chiaro con CTA "Contatta il team".
class WebSelfClaimPage extends StatefulWidget {
  final String businessId;
  final String token;

  const WebSelfClaimPage({
    super.key,
    required this.businessId,
    required this.token,
  });

  @override
  State<WebSelfClaimPage> createState() => _WebSelfClaimPageState();
}

class _WebSelfClaimPageState extends State<WebSelfClaimPage> {
  bool _loadingBusiness = true;
  String? _businessName;
  String? _businessSlug;
  bool _businessLoadError = false;

  bool _busy = false;
  String? _errorMessage;
  String? _successMessage;
  bool _alreadyOwner = false;
  bool _claimed = false;

  @override
  void initState() {
    super.initState();
    _loadBusinessPreview();
  }

  Future<void> _loadBusinessPreview() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .get();
      if (!mounted) return;
      if (!snap.exists) {
        setState(() {
          _loadingBusiness = false;
          _businessLoadError = true;
        });
        return;
      }
      final data = snap.data() ?? {};
      setState(() {
        _businessName = data['name']?.toString() ?? 'Scheda';
        _businessSlug = data['slug']?.toString();
        _loadingBusiness = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingBusiness = false;
        _businessLoadError = true;
      });
    }
  }

  Future<void> _confirmClaim() async {
    if (widget.token.isEmpty) {
      setState(() => _errorMessage =
          'Link non valido: token mancante. Chiedi al team un nuovo link.');
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('acceptSelfClaim');
      final result = await callable.call({
        'businessId': widget.businessId,
        'token': widget.token,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final alreadyOwner = data['alreadyOwner'] == true;
      if (!mounted) return;
      setState(() {
        _claimed = true;
        _alreadyOwner = alreadyOwner;
        _successMessage = alreadyOwner
            ? 'Eri già il proprietario di questa scheda. Tutto a posto.'
            : 'La scheda è ora gestita da te. Benvenuto su TrailShare!';
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _humanError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Errore inatteso: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'Link non valido o già usato. Se serve, chiedi al team un nuovo link.';
      case 'deadline-exceeded':
        return 'Il link è scaduto (30 giorni). Chiedi al team un nuovo link.';
      case 'permission-denied':
        return 'Il link non corrisponde a questa scheda.';
      case 'unauthenticated':
        return 'Devi essere loggato per rivendicare la scheda.';
      default:
        return e.message ?? 'Errore (${e.code}). Riprova o contatta il team.';
    }
  }

  void _goToBusiness() {
    if (_businessSlug != null && _businessSlug!.isNotEmpty) {
      Navigator.of(context).pushReplacementNamed('/b/$_businessSlug');
    } else {
      Navigator.of(context).pushReplacementNamed(
        WebRoutes.businessDashboard(widget.businessId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? user?.displayName ?? 'utente loggato';

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _buildContent(email),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(String email) {
    if (_loadingBusiness) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_businessLoadError) {
      return _ResultBlock(
        icon: Icons.error_outline,
        color: AppColors.danger,
        title: 'Scheda non trovata',
        message:
            'Non riusciamo a trovare la scheda associata a questo link. Forse è stata rimossa o l\'URL è sbagliato.',
        primaryActionLabel: 'Contatta il team',
        primaryAction: () => _mailto(),
      );
    }

    if (_claimed) {
      return _ResultBlock(
        icon: Icons.verified_outlined,
        color: AppColors.primary,
        title: _alreadyOwner ? 'Tutto a posto' : 'Scheda rivendicata!',
        message: _successMessage ?? '',
        primaryActionLabel: 'Vai alla mia scheda',
        primaryAction: _goToBusiness,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.storefront,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Rivendica la tua scheda',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Il team TrailShare ha inserito la scheda seguente per tuo conto. '
          'Conferma per diventarne tu il gestore: potrai aggiornare orari, '
          'foto, contatti, percorsi consigliati e ricevere statistiche delle '
          'visite.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textPrimary.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SCHEDA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _businessName ?? '—',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'ACCEDI COME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            TextButton(
              onPressed: _busy ? null : () => _mailto(),
              child: const Text('Non sono io / Contatta team'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _confirmClaim,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: const Text('Sì, rivendico'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _mailto() {
    // Senza url_launcher per non aggiungere dipendenze. Apriamo un
    // mailto nel browser via window.open style — qui usiamo
    // un fallback Navigator.pop o un SnackBar con info contatto.
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: SelectableText(
          'Scrivi a info@trailshare.app citando l\'ID scheda: ${widget.businessId}',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String primaryActionLabel;
  final VoidCallback primaryAction;

  const _ResultBlock({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.primaryActionLabel,
    required this.primaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 40),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textPrimary.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: primaryAction,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: Text(primaryActionLabel),
          ),
        ),
      ],
    );
  }
}
