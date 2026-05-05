import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/extensions/theme_colors_extension.dart';
import '../../core/services/discovery_prompt_service.dart';
import '../../core/services/monthly_report_service.dart';
import '../../core/services/user_region_service.dart';
import '../../core/services/weekly_challenges_service.dart';
import '../../data/models/discovery_prompt.dart';
import 'discovery_prompts_registry.dart';

/// Carosello di [DiscoveryPrompt] in cima a una pagina principale.
///
/// Comportamento:
/// - Carica i prompt attivi la prima volta (async) + dopo ogni dismiss.
/// - PageView swipeable con indicatori dot.
/// - Auto-rotate ogni 6 secondi (si ferma quando l'utente interagisce).
/// - Ogni card è dismissibile individualmente (X in alto a destra).
/// - Se nessun prompt attivo, il carousel si collassa (height 0).
class DiscoveryCarousel extends StatefulWidget {
  const DiscoveryCarousel({super.key});

  @override
  State<DiscoveryCarousel> createState() => _DiscoveryCarouselState();
}

class _DiscoveryCarouselState extends State<DiscoveryCarousel> {
  final _service = DiscoveryPromptService();
  final _pageController = PageController();
  Timer? _autoRotate;

  List<DiscoveryPrompt>? _prompts;
  int _index = 0;
  bool _userInteracted = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[Discovery] Carousel initState — inizio caricamento prompts');
    // Chiamiamo _load dopo il primo frame: durante initState gli
    // InheritedWidget (context.l10n) non sono ancora accessibili perche'
    // il widget non ha ancora risolto le sue dipendenze.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _autoRotate?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Assicura che la sfida settimanale sia caricata prima del collect:
    // il prompt weekly_challenge valuta WeeklyChallengesService().cached.
    await WeeklyChallengesService().ensureCurrent();
    // Stessa cosa per il report mensile: il prompt monthly_report_ready
    // legge MonthlyReportService().hasNewReportCached (sync).
    await MonthlyReportService().refreshHasNewReportFlag();
    // Regione utente: necessaria per il prompt "imposta la tua regione".
    if (!UserRegionService().isLoaded) {
      await UserRegionService().load();
    }
    if (!mounted) return;
    final candidates = DiscoveryPromptsRegistry.all(context);
    final active = await _service.collect(candidates);
    if (!mounted) return;
    setState(() {
      _prompts = active;
      _index = 0;
    });
    _maybeStartRotation();
  }

  void _maybeStartRotation() {
    _autoRotate?.cancel();
    if (_userInteracted) return;
    if ((_prompts?.length ?? 0) < 2) return;
    _autoRotate = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _userInteracted) return;
      final total = _prompts?.length ?? 0;
      if (total < 2) return;
      final next = (_index + 1) % total;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _onDismiss(DiscoveryPrompt prompt) async {
    await _service.dismiss(prompt.id);
    if (!mounted) return;
    // Ricarica (rimuove il dismissato).
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final prompts = _prompts;
    if (prompts == null) {
      // Loading iniziale — non mostrare nulla (evita flash di layout).
      return const SizedBox.shrink();
    }
    if (prompts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        SizedBox(
          height: 148,
          child: PageView.builder(
            controller: _pageController,
            itemCount: prompts.length,
            onPageChanged: (i) {
              setState(() {
                _index = i;
                _userInteracted = true;
              });
              _autoRotate?.cancel();
            },
            itemBuilder: (_, i) => _DiscoveryCard(
              prompt: prompts[i],
              onDismiss: () => _onDismiss(prompts[i]),
            ),
          ),
        ),
        if (prompts.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < prompts.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? prompts[_index].accentColor
                          : context.themedBorder,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  final DiscoveryPrompt prompt;
  final VoidCallback onDismiss;

  const _DiscoveryCard({required this.prompt, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => prompt.onCta(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  prompt.accentColor.withValues(alpha: 0.14),
                  prompt.accentColor.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: prompt.accentColor.withValues(alpha: 0.28),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: prompt.accentColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(prompt.icon, color: prompt.accentColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              prompt.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: onDismiss,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        prompt.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            prompt.ctaLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: prompt.accentColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: prompt.accentColor,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
