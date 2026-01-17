import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';

/// Servizio per mostrare tooltip contestuali
/// 
/// Mostra suggerimenti al primo utilizzo di una feature.
class FeatureTipsService {
  static final FeatureTipsService _instance = FeatureTipsService._internal();
  factory FeatureTipsService() => _instance;
  FeatureTipsService._internal();

  static const String _prefix = 'tip_shown_';

  /// Verifica se un tip è già stato mostrato
  Future<bool> isTipShown(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$tipId') ?? false;
  }

  /// Segna un tip come mostrato
  Future<void> markTipShown(String tipId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$tipId', true);
  }

  /// Reset tutti i tip (utile per debug)
  Future<void> resetAllTips() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Mostra un tip se non è già stato mostrato
  Future<void> showTipIfNeeded({
    required BuildContext context,
    required String tipId,
    required String title,
    required String message,
    IconData? icon,
  }) async {
    if (await isTipShown(tipId)) return;

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (context) => _FeatureTipDialog(
        title: title,
        message: message,
        icon: icon,
        onDismiss: () {
          markTipShown(tipId);
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _FeatureTipDialog extends StatelessWidget {
  final String title;
  final String message;
  final IconData? icon;
  final VoidCallback onDismiss;

  const _FeatureTipDialog({
    required this.title,
    required this.message,
    this.icon,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onDismiss,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Ho capito!'),
          ),
        ),
      ],
    );
  }
}

/// Widget per mostrare un tooltip pulsante
class PulsatingTooltip extends StatefulWidget {
  final Widget child;
  final String message;
  final bool show;

  const PulsatingTooltip({
    super.key,
    required this.child,
    required this.message,
    this.show = true,
  });

  @override
  State<PulsatingTooltip> createState() => _PulsatingTooltipState();
}

class _PulsatingTooltipState extends State<PulsatingTooltip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return widget.child;

    return Tooltip(
      message: widget.message,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Transform.scale(
            scale: _animation.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Definizioni dei tip dell'app
class AppTips {
  // IDs dei tip
  static const String firstTrack = 'first_track';
  static const String liveTrack = 'live_track';
  static const String discover = 'discover';
  static const String wishlist = 'wishlist';
  static const String cheers = 'cheers';
  static const String leaderboard = 'leaderboard';
  static const String offlineMaps = 'offline_maps';
  static const String heartRate = 'heart_rate';
  static const String gpxExport = 'gpx_export';

  /// Mostra tip per prima traccia
  static Future<void> showFirstTrackTip(BuildContext context) async {
    await FeatureTipsService().showTipIfNeeded(
      context: context,
      tipId: firstTrack,
      title: '🎉 Prima registrazione!',
      message: 'Premi il pulsante verde per iniziare a registrare la tua prima traccia. Il GPS funziona anche in background!',
      icon: Icons.play_circle_filled,
    );
  }

  /// Mostra tip per LiveTrack
  static Future<void> showLiveTrackTip(BuildContext context) async {
    await FeatureTipsService().showTipIfNeeded(
      context: context,
      tipId: liveTrack,
      title: 'LiveTrack',
      message: 'Condividi la tua posizione in tempo reale con amici e familiari. Potranno seguirti sulla mappa durante l\'escursione.',
      icon: Icons.share_location,
    );
  }

  /// Mostra tip per Discover
  static Future<void> showDiscoverTip(BuildContext context) async {
    await FeatureTipsService().showTipIfNeeded(
      context: context,
      tipId: discover,
      title: 'Esplora',
      message: 'Scopri percorsi pubblicati da altri escursionisti. Usa i filtri per trovare tracce vicino a te o per difficoltà.',
      icon: Icons.explore,
    );
  }

  /// Mostra tip per Wishlist
  static Future<void> showWishlistTip(BuildContext context) async {
    await FeatureTipsService().showTipIfNeeded(
      context: context,
      tipId: wishlist,
      title: 'Wishlist',
      message: 'Salva i percorsi che ti interessano nella wishlist. Li troverai nel tuo profilo pronti per la prossima avventura!',
      icon: Icons.bookmark,
    );
  }

  /// Mostra tip per Cheers
  static Future<void> showCheersTip(BuildContext context) async {
    await FeatureTipsService().showTipIfNeeded(
      context: context,
      tipId: cheers,
      title: 'Cheers! 🎉',
      message: 'Lascia un "cheers" alle tracce che ti piacciono per supportare altri escursionisti e guadagnare XP!',
      icon: Icons.celebration,
    );
  }

  /// Mostra tip per Leaderboard
  static Future<void> showLeaderboardTip(BuildContext context) async {
    await FeatureTipsService().showTipIfNeeded(
      context: context,
      tipId: leaderboard,
      title: 'Classifica',
      message: 'Scala la classifica settimanale! Ogni km percorso e ogni metro di dislivello ti fanno guadagnare punti.',
      icon: Icons.leaderboard,
    );
  }

  /// Mostra tip per mappe offline
  static Future<void> showOfflineMapsTip(BuildContext context) async {
    await FeatureTipsService().showTipIfNeeded(
      context: context,
      tipId: offlineMaps,
      title: 'Mappe Offline',
      message: 'Scarica le mappe prima di partire! Vai in Impostazioni > Mappe Offline per salvare le aree che ti servono.',
      icon: Icons.download,
    );
  }

  /// Mostra tip per fascia cardio
  static Future<void> showHeartRateTip(BuildContext context) async {
    await FeatureTipsService().showTipIfNeeded(
      context: context,
      tipId: heartRate,
      title: 'Fascia Cardio',
      message: 'Collega una fascia cardio Bluetooth per monitorare il battito durante le tue attività.',
      icon: Icons.favorite,
    );
  }

  /// Mostra tip per export GPX
  static Future<void> showGpxExportTip(BuildContext context) async {
    await FeatureTipsService().showTipIfNeeded(
      context: context,
      tipId: gpxExport,
      title: 'Export GPX',
      message: 'Esporta le tue tracce in formato GPX per usarle con altre app o dispositivi GPS.',
      icon: Icons.file_download,
    );
  }
}
