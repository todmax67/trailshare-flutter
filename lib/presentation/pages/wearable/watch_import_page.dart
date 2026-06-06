import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/health_import_service.dart';
import '../../../core/services/health_service.dart';
import '../../widgets/app_snackbar.dart';

/// Importa attività registrate sull'orologio (Apple Watch / Garmin & co.)
/// leggendole da Apple Health / Health Connect — senza app nativa sul polso.
class WatchImportPage extends StatefulWidget {
  const WatchImportPage({super.key});

  @override
  State<WatchImportPage> createState() => _WatchImportPageState();
}

class _WatchImportPageState extends State<WatchImportPage> {
  final _health = HealthService();
  final _import = HealthImportService();

  bool _loading = true;
  bool _permissionDenied = false;
  List<HealthWorkout> _workouts = const [];
  final Set<String> _imported = {};
  String? _importingKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _keyOf(HealthWorkout w) =>
      w.uuid ?? '${w.startTime.millisecondsSinceEpoch}_${w.type}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final granted = await _health.requestPermissions();
    if (!granted) {
      if (mounted) {
        setState(() {
          _loading = false;
          _permissionDenied = true;
        });
      }
      return;
    }
    final workouts = await _health.getRecentWorkouts(days: 30);
    if (!mounted) return;
    setState(() {
      _workouts = workouts;
      _loading = false;
    });
  }

  Future<void> _importOne(HealthWorkout w) async {
    final key = _keyOf(w);
    setState(() => _importingKey = key);
    try {
      final id = await _import.importWorkout(w);
      if (!mounted) return;
      if (id == null) {
        AppSnackBar.info(context,
            'Questa attività non ha una traccia GPS (indoor?) e non è importabile');
      } else {
        setState(() => _imported.add(key));
        AppSnackBar.success(context, 'Attività importata nelle tue tracce ✓');
      }
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'Import non riuscito: $e');
    } finally {
      if (mounted) setState(() => _importingKey = null);
    }
  }

  IconData _iconFor(String type) {
    final s = type.toUpperCase();
    if (s.contains('RUN')) return Icons.directions_run;
    if (s.contains('CYCL') || s.contains('BIK')) return Icons.directions_bike;
    if (s.contains('WALK')) return Icons.directions_walk;
    return Icons.terrain; // hiking/trekking & default
  }

  String _humanType(String type) {
    final s = type.toUpperCase();
    if (s.contains('HIK')) return 'Escursione';
    if (s.contains('RUN')) return 'Corsa';
    if (s.contains('CYCL') || s.contains('BIK')) return 'Bici';
    if (s.contains('WALK')) return 'Camminata';
    return type.replaceAll('_', ' ').toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importa dall\'orologio')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permissionDenied) {
      return _message(
        Icons.health_and_safety_outlined,
        'Serve l\'accesso a Salute',
        'Per importare i giri registrati sull\'orologio, concedi a TrailShare '
            'l\'accesso ad Apple Health / Health Connect (attività e percorso).',
        action: FilledButton(onPressed: _load, child: const Text('Riprova')),
      );
    }
    if (_workouts.isEmpty) {
      return _message(
        Icons.watch_outlined,
        'Nessuna attività trovata',
        'Non ci sono attività degli ultimi 30 giorni in Salute. Registra un '
            'giro sull\'orologio (con GPS) e assicurati che si sincronizzi con '
            'Apple Health / Health Connect.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _workouts.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Attività degli ultimi 30 giorni da Apple Health / Health Connect. '
              'Tocca per importarle come tracce (con percorso GPS e battito).',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          );
        }
        final w = _workouts[i - 1];
        final key = _keyOf(w);
        final importing = _importingKey == key;
        final done = _imported.contains(key);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Icon(_iconFor(w.type), color: AppColors.primary),
          ),
          title: Text('${_humanType(w.type)} · ${w.startTime.day}/'
              '${w.startTime.month}/${w.startTime.year}'),
          subtitle: Text(
            [
              w.distanceFormatted,
              w.durationFormatted,
              if (w.sourceName.isNotEmpty) w.sourceName,
            ].where((s) => s != '--' && s.isNotEmpty).join(' · '),
          ),
          trailing: done
              ? const Icon(Icons.check_circle, color: Colors.green)
              : importing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : FilledButton.tonal(
                      onPressed: _importingKey == null ? () => _importOne(w) : null,
                      child: const Text('Importa'),
                    ),
        );
      },
    );
  }

  Widget _message(IconData icon, String title, String body, {Widget? action}) {
    return ListView(
      // ListView (non Center) così il RefreshIndicator funziona anche vuoto.
      padding: const EdgeInsets.fromLTRB(28, 80, 28, 28),
      children: [
        Icon(icon, size: 56, color: Colors.grey),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey)),
        if (action != null) ...[
          const SizedBox(height: 20),
          Center(child: action),
        ],
      ],
    );
  }
}
