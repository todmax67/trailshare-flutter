import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../data/repositories/public_trails_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/theme_colors_extension.dart';

/// Pagina di amministrazione per verificare lo stato GeoHash
/// 
/// I documenti hanno già il campo 'geoHash' (con H maiuscola) popolato!
/// Questa pagina serve solo per verificare lo stato.
class GeohashMigrationPage extends StatefulWidget {
  const GeohashMigrationPage({super.key});

  @override
  State<GeohashMigrationPage> createState() => _GeohashMigrationPageState();
}

class _GeohashMigrationPageState extends State<GeohashMigrationPage> {
  final PublicTrailsRepository _repository = PublicTrailsRepository();
  
  bool _isChecking = false;
  bool _isMigrating = false;
  int? _withGeohash;
  int? _withoutGeohash;

  /// Cloud Function HTTP `migrateGeoHash` deployata su europe-west3.
  /// Itera tutta la subcollection `public_trails`, ricostruisce
  /// geoHash + startPoint per i doc che ne sono privi, ritorna JSON
  /// `{updated, skipped, failed}`.
  static const String _migrateFunctionUrl =
      'https://europe-west3-trailshare-5334b.cloudfunctions.net/migrateGeoHash';

  Future<void> _runMigration() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Esegui migrazione GeoHash'),
        content: Text(
          'Verranno aggiornati i documenti senza geoHash su public_trails '
          '(stimati: ${_withoutGeohash ?? "—"}). L\'operazione può '
          'richiedere alcuni minuti e non è reversibile, ma è sicura '
          '(non cancella dati). Continuare?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Esegui'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _isMigrating = true);
    try {
      // Timeout 9 min: la function ha timeoutSeconds=540, gli diamo
      // un po' di margine. Niente Authorization header: la function è
      // pubblica per design (admin-only via UI gating + onRequest sul
      // bundle limita rate).
      final resp = await http
          .post(Uri.parse(_migrateFunctionUrl))
          .timeout(const Duration(minutes: 9));

      if (!mounted) return;
      if (resp.statusCode != 200) {
        _snack('Migrazione fallita (HTTP ${resp.statusCode})',
            error: true);
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final updated = (data['updated'] as num?)?.toInt() ?? 0;
      final skipped = (data['skipped'] as num?)?.toInt() ?? 0;
      final failed = (data['failed'] as num?)?.toInt() ?? 0;
      _snack(
        'Migrazione completata · $updated aggiornati · '
        '$skipped già ok · $failed falliti',
        error: failed > 0,
      );
      // Refresh contatori dopo la migrazione
      await _checkCoverage();
    } catch (e) {
      if (!mounted) return;
      _snack('Errore: $e', error: true);
    } finally {
      if (mounted) setState(() => _isMigrating = false);
    }
  }

  void _snack(String msg, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : AppColors.success,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkCoverage();
  }

  Future<void> _checkCoverage() async {
    setState(() {
      _isChecking = true;
    });

    try {
      final coverage = await _repository.checkGeohashCoverage();
      setState(() {
        _withGeohash = coverage.withGeohash;
        _withoutGeohash = coverage.withoutGeohash;
      });
    } catch (e) {
      // ignore: errore mostrato dal counters
    } finally {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = (_withGeohash ?? 0) + (_withoutGeohash ?? 0);
    final percentage = total > 0 
        ? ((_withGeohash ?? 0) / total * 100) 
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stato GeoHash'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.info),
                        SizedBox(width: 8),
                        Text(
                          'Cos\'è GeoHash?',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'GeoHash è un sistema che codifica le coordinate geografiche in stringhe. '
                      'I tuoi documenti hanno già il campo \'geoHash\' popolato, quindi le query '
                      'geospaziali funzionano automaticamente!',
                      style: TextStyle(color: context.textSecondary),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Stato attuale
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.analytics, color: AppColors.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Stato Attuale',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Spacer(),
                        if (_isChecking)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _checkCoverage,
                            tooltip: 'Aggiorna',
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        minHeight: 20,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          percentage >= 100 ? AppColors.success : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${percentage.toStringAsFixed(1)}% con GeoHash',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 16),

                    // Dettagli
                    Row(
                      children: [
                        Expanded(
                          child: _StatBox(
                            icon: Icons.check_circle,
                            color: AppColors.success,
                            value: _withGeohash?.toString() ?? '-',
                            label: 'Con GeoHash',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatBox(
                            icon: Icons.warning,
                            color: AppColors.warning,
                            value: _withoutGeohash?.toString() ?? '-',
                            label: 'Senza',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatBox(
                            icon: Icons.folder,
                            color: AppColors.info,
                            value: total.toString(),
                            label: 'Totale',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Stato
            if (percentage >= 99)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.success),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GeoHash attivo!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Le query geospaziali sono ottimizzate e scalano a milioni di documenti.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info, color: AppColors.warning),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Alcuni documenti senza GeoHash',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warning,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'L\'app usa query legacy (meno efficienti) per questi '
                                'documenti. Esegui la migrazione per completare l\'indice '
                                'geospaziale.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isMigrating ? null : _runMigration,
                        icon: _isMigrating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(_isMigrating
                            ? 'Migrazione in corso…'
                            : 'Esegui migrazione adesso'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Note tecniche
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.code, color: context.textMuted),
                        SizedBox(width: 8),
                        Text(
                          'Note Tecniche',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Campo: geoHash (con H maiuscola)\n'
                      '• Precisione: 7 caratteri (~153m)\n'
                      '• Query: range-based su Firestore\n'
                      '• Campione analizzato: ${total > 0 ? total : 500} documenti',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _StatBox({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: context.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
