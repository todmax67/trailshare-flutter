import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/monetization_config.dart';
import '../../core/constants/pro_products.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/services/pro_gate_service.dart';
import '../../core/services/subscription_manager.dart';

/// Tipo di trigger che ha aperto il paywall (per analytics + UI hint).
enum PaywallTrigger {
  mountainFinderAR,
  photoModePro,
  mapStylePro,
  discoveryUpsell,
  settingsManual,
  onboarding,
  generic,
}

/// Apre la [PaywallSheet] come modal bottom sheet.
///
/// Esempio:
/// ```dart
/// final purchased = await showPaywallSheet(
///   context,
///   trigger: PaywallTrigger.mountainFinderAR,
/// );
/// if (purchased == true) {
///   // user is now Pro
/// }
/// ```
Future<bool?> showPaywallSheet(
  BuildContext context, {
  PaywallTrigger trigger = PaywallTrigger.generic,
}) {
  // Su Android (monetizzazione disabilitata) non mostriamo il paywall
  // di acquisto ma una sheet informativa "Pro gratis su Android".
  if (Platform.isAndroid &&
      !MonetizationConfig.androidMonetizationEnabled) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => const _AndroidFreeProSheet(),
    );
  }

  // Routing context-aware in base allo stato Pro corrente:
  // - Yearly attivo  → "Sei Pro" + manage (no purchase)
  // - Monthly attivo → "Passa ad Annuale e risparmia" (upgrade flow)
  // - Free           → PaywallSheet standard con 2 piani
  final gate = ProGateService();
  if (gate.isPro && gate.isYearly) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => const _AlreadyProYearlySheet(),
    );
  }
  if (gate.isPro && gate.isMonthly) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => const _UpgradeToYearlySheet(),
    );
  }

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => PaywallSheet(trigger: trigger),
  );
}

/// URL per gestire l'abbonamento dalla pagina Apple/Play Store.
/// - iOS: deep link nativo che apre Settings → Apple ID → Abbonamenti
/// - Android (futuro): deep link a Play Store app management
String _manageSubscriptionUrl() {
  if (Platform.isIOS) {
    return 'https://apps.apple.com/account/subscriptions';
  }
  // Android: quando attiveremo la monetizzazione (6.B Android), usare:
  // 'https://play.google.com/store/account/subscriptions?package=<id>'
  return 'https://apps.apple.com/account/subscriptions';
}

/// Sheet di upgrade a TrailShare Pro.
///
/// 6.B1: collegato a [SubscriptionManager] per il purchase flow reale via
/// `in_app_purchase`. I prezzi sono dinamici (vengono dallo store) con
/// fallback hardcoded se i prodotti non sono ancora caricati o lo store
/// non è disponibile (emulatore, tester non firmato).
class PaywallSheet extends StatefulWidget {
  final PaywallTrigger trigger;

  const PaywallSheet({super.key, this.trigger = PaywallTrigger.generic});

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

enum _Plan { monthly, yearly }

class _PaywallSheetState extends State<PaywallSheet> {
  _Plan _selected = _Plan.yearly; // default: highlight annuale (con sconto)
  bool _purchasing = false;

  // Prezzi di fallback — usati quando lo store non è disponibile (es.
  // emulatore, app non firmata, country senza i prodotti configurati).
  // Quando i prodotti dello store sono caricati, vengono usati al loro
  // posto (vedi [_yearlyDisplayPrice] / [_monthlyDisplayPrice]).
  static const _monthlyFallbackPrice = '€2,99';
  static const _yearlyFallbackPrice = '€19,99';
  static const _yearlyMonthlyEquivalent = '€1,67';
  static const _trialDays = 14;

  ProductDetails? get _monthlyProduct =>
      SubscriptionManager().productById(ProProducts.monthly);
  ProductDetails? get _yearlyProduct =>
      SubscriptionManager().productById(ProProducts.yearly);

  String get _monthlyDisplayPrice =>
      _monthlyProduct?.price ?? _monthlyFallbackPrice;
  String get _yearlyDisplayPrice =>
      _yearlyProduct?.price ?? _yearlyFallbackPrice;

  String get _heroTitle {
    switch (widget.trigger) {
      case PaywallTrigger.mountainFinderAR:
        return 'Sblocca Mountain Finder AR';
      case PaywallTrigger.photoModePro:
        return 'Sblocca Photo Mode Pro';
      case PaywallTrigger.mapStylePro:
        return 'Sblocca le mappe Pro';
      case PaywallTrigger.discoveryUpsell:
        return 'Porta TrailShare al livello Pro';
      case PaywallTrigger.onboarding:
        return 'Inizia con tutto incluso';
      case PaywallTrigger.settingsManual:
      case PaywallTrigger.generic:
        return 'TrailShare Pro';
    }
  }

  String get _heroSubtitle {
    switch (widget.trigger) {
      case PaywallTrigger.mountainFinderAR:
        return 'Riconosci ogni cima in tempo reale con la fotocamera, '
            'come PeakFinder ma integrato nelle tue tracce.';
      case PaywallTrigger.photoModePro:
        return 'Cattura foto annotate con i nomi delle cime e condividile '
            'con amici e community.';
      case PaywallTrigger.mapStylePro:
        return 'Topografica dettagliata, satellite con etichette e mappa '
            'invernale per scialpinismo. Pensate per la montagna.';
      case PaywallTrigger.discoveryUpsell:
        return 'Funzioni AR, photo mode professionale e tutte le novità future, '
            'sempre incluse.';
      case PaywallTrigger.onboarding:
        return '14 giorni gratuiti, poi solo $_yearlyDisplayPrice/anno. '
            'Annulla quando vuoi.';
      case PaywallTrigger.settingsManual:
      case PaywallTrigger.generic:
        return 'Sblocca le funzioni avanzate per la montagna e supporta '
            'lo sviluppo dell\'app.';
    }
  }

  @override
  void initState() {
    super.initState();
    // Re-render quando i prodotti dello store finiscono di caricarsi
    // (initial query async) o cambia lo stato Pro (acquisto completato).
    SubscriptionManager().addListener(_onManagerChange);
    ProGateService().addListener(_onManagerChange);

    // Best-effort: se non ci sono ancora prodotti, refresh ora.
    final mgr = SubscriptionManager();
    if (mgr.isInitialized && mgr.isStoreAvailable && mgr.products.isEmpty) {
      mgr.refreshProducts();
    }
  }

  @override
  void dispose() {
    SubscriptionManager().removeListener(_onManagerChange);
    ProGateService().removeListener(_onManagerChange);
    super.dispose();
  }

  void _onManagerChange() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onCta() async {
    if (_purchasing) return;

    final mgr = SubscriptionManager();
    final productId = _selected == _Plan.yearly
        ? ProProducts.yearly
        : ProProducts.monthly;

    // Se lo store non è disponibile (emulatore, app non firmata, regione
    // non supportata) NON chiamiamo `purchase` — toccheremmo solo il
    // path di errore. Mostriamo invece un'info chiara.
    if (!mgr.isStoreAvailable || mgr.productById(productId) == null) {
      _showStoreUnavailableHint();
      return;
    }

    setState(() => _purchasing = true);
    final outcome = await mgr.purchase(productId);
    if (!mounted) return;
    setState(() => _purchasing = false);

    switch (outcome) {
      case PurchaseOutcome.success:
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Benvenuto in TrailShare Pro!'),
            backgroundColor: AppColors.success,
          ),
        );
        break;
      case PurchaseOutcome.canceled:
        // Silenzioso: l'utente ha consciously chiuso il flow.
        break;
      case PurchaseOutcome.pending:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Pagamento in attesa di conferma. Ti notificheremo quando è pronto.'),
          ),
        );
        break;
      case PurchaseOutcome.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mgr.lastError ?? 'Acquisto non riuscito. Riprova più tardi.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
        break;
    }
  }

  Future<void> _onRestore() async {
    final mgr = SubscriptionManager();
    if (!mgr.isStoreAvailable) {
      _showStoreUnavailableHint();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ripristino acquisti in corso…')),
    );
    await mgr.restore();
    if (!mounted) return;
    // Lo stream del manager aggiornerà ProGateService se ci sono acquisti
    // attivi — il listener di `_onManagerChange` rebuilda la sheet e
    // l'utente vede l'effetto. Mostriamo feedback solo se NON c'è stato
    // unlock entro 1.5s (tempo tipicamente sufficiente).
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (ProGateService().isPro) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Acquisti ripristinati. Sei Pro!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Nessun acquisto attivo trovato per questo account.'),
          ),
        );
      }
    });
  }

  void _showStoreUnavailableHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          SubscriptionManager().isStoreAvailable
              ? 'I prodotti non sono ancora disponibili. Riprova tra qualche secondo.'
              : 'Lo store non è disponibile su questo dispositivo.',
        ),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxHeight = size.height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: context.themedSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          // Contenuto scrollabile.
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(context),
                const SizedBox(height: 24),
                _buildFeatures(context),
                const SizedBox(height: 24),
                _buildPlanSelector(context),
                const SizedBox(height: 16),
                _buildPriceFooter(context),
                const SizedBox(height: 16),
                _buildCta(context),
                const SizedBox(height: 12),
                _buildLegalFooter(context),
              ],
            ),
          ),
          // Close button.
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.25),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context, false),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 20, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Hero ───────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF6D4C41), // marrone montagna
            Color(0xFFE07B4C), // arancio TrailShare
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle.
          Container(
            width: 48,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Pro badge.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.workspace_premium,
                    size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'TRAILSHARE PRO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _heroTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _heroSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Features list ──────────────────────────────────────────────────────

  Widget _buildFeatures(BuildContext context) {
    final features = <_Feature>[
      _Feature(
        icon: Icons.terrain,
        color: const Color(0xFF6D4C41),
        title: 'Mountain Finder AR',
        subtitle:
            'Riconosci 37.000+ cime italiane in tempo reale con la fotocamera.',
      ),
      _Feature(
        icon: Icons.camera_alt_outlined,
        color: const Color(0xFF1976D2),
        title: 'Photo Mode Pro',
        subtitle:
            'Foto panoramiche annotate con i nomi delle cime, pronte da condividere.',
      ),
      _Feature(
        icon: Icons.layers_outlined,
        color: const Color(0xFF2E7D32),
        title: 'Mappe topografiche premium',
        subtitle:
            'Topo dettagliata, satellite con etichette e mappa invernale per scialpinismo.',
      ),
      _Feature(
        icon: Icons.bookmark_outline,
        color: const Color(0xFFFFB300),
        title: 'Cime salvate illimitate',
        subtitle:
            'Crea il tuo album personale di vette riconosciute durante le escursioni.',
      ),
      _Feature(
        icon: Icons.auto_awesome,
        color: const Color(0xFF7C4DFF),
        title: 'Tutte le novità future',
        subtitle:
            '3D fly-through, allenamento HR e altro — sempre incluse.',
      ),
      _Feature(
        icon: Icons.favorite_outline,
        color: AppColors.danger,
        title: 'Senza pubblicità, senza compromessi',
        subtitle:
            'Niente ads, niente vendita di dati. Il tuo abbonamento è l\'unica '
            'cosa che fa andare avanti l\'app.',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (final f in features) ...[
            _buildFeatureRow(f),
            if (f != features.last) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildFeatureRow(_Feature f) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: f.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(f.icon, color: f.color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                f.subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Plan selector ──────────────────────────────────────────────────────

  Widget _buildPlanSelector(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildPlanTile(
            plan: _Plan.yearly,
            title: 'Annuale',
            price: _yearlyDisplayPrice,
            priceUnit: '/anno',
            secondary: '$_yearlyMonthlyEquivalent al mese',
            badgeText: 'Risparmi 44%',
            badgeColor: AppColors.success,
          ),
          const SizedBox(height: 10),
          _buildPlanTile(
            plan: _Plan.monthly,
            title: 'Mensile',
            price: _monthlyDisplayPrice,
            priceUnit: '/mese',
            secondary: 'Cancellazione in qualsiasi momento',
            badgeText: null,
            badgeColor: null,
          ),
        ],
      ),
    );
  }

  Widget _buildPlanTile({
    required _Plan plan,
    required String title,
    required String price,
    required String priceUnit,
    required String secondary,
    String? badgeText,
    Color? badgeColor,
  }) {
    final isSelected = _selected == plan;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _selected = plan),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : context.themedSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : context.themedBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio.
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : context.textMuted,
                  width: 2,
                ),
                color: isSelected ? AppColors.primary : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            // Title + secondary.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      if (badgeText != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? AppColors.success)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: badgeColor ?? AppColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Price.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  priceUnit,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Price footer ───────────────────────────────────────────────────────

  Widget _buildPriceFooter(BuildContext context) {
    final isYearly = _selected == _Plan.yearly;
    final caption = isYearly
        ? '$_trialDays giorni gratis, poi $_yearlyDisplayPrice/anno. Annulla quando vuoi.'
        : 'Nessun trial sul piano mensile. Annulla quando vuoi.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 14, color: context.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              caption,
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Main CTA ───────────────────────────────────────────────────────────

  Widget _buildCta(BuildContext context) {
    final label = _selected == _Plan.yearly
        ? 'Inizia $_trialDays giorni gratis'
        : 'Abbonati a $_monthlyDisplayPrice/mese';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _purchasing ? null : _onCta,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _purchasing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.4,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }

  // ─── Legal footer ───────────────────────────────────────────────────────

  Widget _buildLegalFooter(BuildContext context) {
    final muted = TextStyle(
      fontSize: 11,
      color: context.textSecondary,
    );
    final link = TextStyle(
      fontSize: 11,
      color: context.textSecondary,
      decoration: TextDecoration.underline,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          TextButton(
            onPressed: _purchasing ? null : _onRestore,
            child: const Text(
              'Ripristina acquisti',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Toccando «Inizia» accetti i nostri ', style: muted),
              GestureDetector(
                onTap: () =>
                    _openUrl('https://trailshare.app/terms'),
                child: Text('Termini', style: link),
              ),
              Text(' e la ', style: muted),
              GestureDetector(
                onTap: () =>
                    _openUrl('https://trailshare.app/privacy'),
                child: Text('Privacy', style: link),
              ),
              Text('.', style: muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
}

/// Sheet alternativa mostrata su Android quando la monetizzazione non è
/// ancora attiva. Niente prezzi, niente CTA di acquisto: comunichiamo
/// chiaramente che le funzioni Pro sono **gratis** su Android per ora.
class _AndroidFreeProSheet extends StatelessWidget {
  const _AndroidFreeProSheet();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.85),
      decoration: BoxDecoration(
        color: context.themedSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(context),
                const SizedBox(height: 24),
                _features(context),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Inizia a esplorare',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(
                    'In futuro TrailShare Pro potrebbe diventare un abbonamento '
                    'anche su Android — ti avviseremo prima con largo anticipo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.25),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 20, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6D4C41), Color(0xFFE07B4C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.celebration, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'TUTTO INCLUSO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'TrailShare Pro è gratis\nsu Android 🎉',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tutte le funzioni avanzate sono disponibili senza acquistare nulla. '
            'Goditi Mountain Finder AR, Photo Mode Pro e tutto il resto.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _features(BuildContext context) {
    final items = <_AndroidFeatureRow>[
      _AndroidFeatureRow(
        icon: Icons.terrain,
        color: const Color(0xFF6D4C41),
        title: 'Mountain Finder AR',
        subtitle: 'Riconoscimento di 37.000+ cime italiane in tempo reale.',
      ),
      _AndroidFeatureRow(
        icon: Icons.camera_alt_outlined,
        color: const Color(0xFF1976D2),
        title: 'Photo Mode Pro',
        subtitle: 'Foto panoramiche con i nomi delle cime annotati.',
      ),
      _AndroidFeatureRow(
        icon: Icons.bookmark_outline,
        color: const Color(0xFFFFB300),
        title: 'Cime salvate illimitate',
        subtitle: 'Costruisci il tuo album personale di vette riconosciute.',
      ),
      _AndroidFeatureRow(
        icon: Icons.favorite_outline,
        color: AppColors.danger,
        title: 'Senza pubblicità',
        subtitle: 'Niente ads, niente vendita di dati. Mai.',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (final f in items) ...[
            f.build(context),
            if (f != items.last) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _AndroidFeatureRow {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _AndroidFeatureRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.check_circle,
            color: AppColors.success, size: 22),
      ],
    );
  }
}

// ─── 6.B1.5 — Sheet "Sei già Pro" — variante per piano Annuale ─────────
//
// L'utente ha già il piano top (yearly). Niente upgrade possibile, mostriamo
// solo conferma + link manage.

class _AlreadyProYearlySheet extends StatelessWidget {
  const _AlreadyProYearlySheet();

  Future<void> _openManage() async {
    await launchUrl(
      Uri.parse(_manageSubscriptionUrl()),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.85),
      decoration: BoxDecoration(
        color: context.themedSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(
                  badgeIcon: Icons.workspace_premium,
                  badgeLabel: 'TRAILSHARE PRO ANNUALE',
                  title: 'Sei TrailShare Pro 🎉',
                  subtitle:
                      'Hai accesso a tutte le funzioni avanzate per la montagna. '
                      'Grazie per supportare lo sviluppo!',
                ),
                const SizedBox(height: 24),
                _buildFeaturesList(context),
                const SizedBox(height: 28),
                _buildManageButton(context),
                const SizedBox(height: 14),
                _buildFooterCaption(
                  context,
                  'Apri le impostazioni Apple per modificare o cancellare '
                  'l\'abbonamento.',
                ),
              ],
            ),
          ),
          _buildCloseButton(context),
        ],
      ),
    );
  }

  Widget _buildManageButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 54,
        child: OutlinedButton.icon(
          onPressed: _openManage,
          icon: const Icon(Icons.settings_outlined, size: 20),
          label: const Text(
            'Gestisci abbonamento',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 6.B1.5 — Sheet "Passa ad Annuale" — variante per piano Mensile ────
//
// L'utente ha il monthly: gli proponiamo upgrade ad annuale (gestito da
// Apple come crossgrade immediato grazie ai subscription levels). Layout
// più focalizzato: niente plan selector multiplo, una sola CTA che lancia
// il purchase del prodotto annuale.

class _UpgradeToYearlySheet extends StatefulWidget {
  const _UpgradeToYearlySheet();

  @override
  State<_UpgradeToYearlySheet> createState() => _UpgradeToYearlySheetState();
}

class _UpgradeToYearlySheetState extends State<_UpgradeToYearlySheet> {
  bool _purchasing = false;

  static const _yearlyFallbackPrice = '€19,99';
  static const _monthlyEquivalent = '€1,67';

  String get _yearlyDisplayPrice =>
      SubscriptionManager().productById(ProProducts.yearly)?.price ??
      _yearlyFallbackPrice;

  Future<void> _onUpgrade() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    final outcome =
        await SubscriptionManager().purchase(ProProducts.yearly);
    if (!mounted) return;
    setState(() => _purchasing = false);

    switch (outcome) {
      case PurchaseOutcome.success:
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Sei passato a TrailShare Pro Annuale!'),
            backgroundColor: AppColors.success,
          ),
        );
        break;
      case PurchaseOutcome.canceled:
        break;
      case PurchaseOutcome.pending:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upgrade in attesa di conferma.'),
          ),
        );
        break;
      case PurchaseOutcome.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              SubscriptionManager().lastError ??
                  'Upgrade non riuscito. Riprova più tardi.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
        break;
    }
  }

  Future<void> _openManage() async {
    await launchUrl(
      Uri.parse(_manageSubscriptionUrl()),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.92),
      decoration: BoxDecoration(
        color: context.themedSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(
                  badgeIcon: Icons.trending_up,
                  badgeLabel: 'OFFERTA UPGRADE',
                  title: 'Passa ad Annuale\ne risparmia 44%',
                  subtitle:
                      'Stai pagando il piano Mensile. Con l\'Annuale spendi '
                      'meno e supporti meglio lo sviluppo.',
                ),
                const SizedBox(height: 24),
                _buildPriceComparison(context),
                const SizedBox(height: 24),
                _buildUpgradeCta(context),
                const SizedBox(height: 12),
                _buildFooterCaption(
                  context,
                  'L\'upgrade è immediato. Apple rimborsa la parte non '
                  'utilizzata del piano mensile.',
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton(
                    onPressed: _purchasing ? null : _openManage,
                    child: const Text(
                      'Gestisci abbonamento',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildCloseButton(context),
        ],
      ),
    );
  }

  Widget _buildPriceComparison(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _PriceColumn(
                    label: 'Adesso',
                    price: '€2,99',
                    suffix: '/mese',
                    detail: '€35,88/anno',
                    isOld: true,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward,
                      color: AppColors.primary, size: 24),
                ),
                Expanded(
                  child: _PriceColumn(
                    label: 'Con Annuale',
                    price: _yearlyDisplayPrice,
                    suffix: '/anno',
                    detail: '$_monthlyEquivalent al mese',
                    isOld: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Risparmi €15,89 all\'anno',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeCta(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _purchasing ? null : _onUpgrade,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _purchasing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.4,
                  ),
                )
              : Text(
                  'Passa ad Annuale a $_yearlyDisplayPrice',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }
}

class _PriceColumn extends StatelessWidget {
  final String label;
  final String price;
  final String suffix;
  final String detail;
  final bool isOld;

  const _PriceColumn({
    required this.label,
    required this.price,
    required this.suffix,
    required this.detail,
    required this.isOld,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          price,
          style: TextStyle(
            fontSize: isOld ? 16 : 22,
            fontWeight: FontWeight.w800,
            color: isOld
                ? context.textSecondary
                : context.textPrimary,
            decoration:
                isOld ? TextDecoration.lineThrough : TextDecoration.none,
          ),
        ),
        Text(
          suffix,
          style: TextStyle(
            fontSize: 10,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─── Helpers condivisi tra le 2 sheet "già pro" ────────────────────────

Widget _buildHero({
  required IconData badgeIcon,
  required String badgeLabel,
  required String title,
  required String subtitle,
}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF6D4C41), Color(0xFFE07B4C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: Column(
      children: [
        Container(
          width: 48,
          height: 4,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                badgeLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.92),
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

Widget _buildFeaturesList(BuildContext context) {
  // Lista feature concise per la sheet "già pro yearly". Riusa lo stile
  // di _AndroidFeatureRow (icona + testo + check verde) ma compatto.
  final items = <_AndroidFeatureRow>[
    _AndroidFeatureRow(
      icon: Icons.terrain,
      color: const Color(0xFF6D4C41),
      title: 'Mountain Finder AR',
      subtitle: 'Riconoscimento cime in tempo reale.',
    ),
    _AndroidFeatureRow(
      icon: Icons.camera_alt_outlined,
      color: const Color(0xFF1976D2),
      title: 'Photo Mode Pro',
      subtitle: 'Foto annotate con i nomi delle cime.',
    ),
    _AndroidFeatureRow(
      icon: Icons.bookmark_outline,
      color: const Color(0xFFFFB300),
      title: 'Cime salvate illimitate',
      subtitle: 'Album personale di vette riconosciute.',
    ),
  ];

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      children: [
        for (final f in items) ...[
          f.build(context),
          if (f != items.last) const SizedBox(height: 14),
        ],
      ],
    ),
  );
}

Widget _buildFooterCaption(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        color: context.textSecondary,
        height: 1.4,
      ),
    ),
  );
}

Widget _buildCloseButton(BuildContext context) {
  return Positioned(
    top: 8,
    right: 8,
    child: Material(
      color: Colors.black.withValues(alpha: 0.25),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.pop(context),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.close, size: 20, color: Colors.white),
        ),
      ),
    ),
  );
}
