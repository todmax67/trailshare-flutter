import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/italian_regions.dart';
import '../../../core/services/trail_import_service.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Pagina admin per importare sentieri da Waymarked Trails.
///
/// Refactor (Sprint admin import):
///  - A1: dropdown 20 regioni italiane ufficiali con bbox auto
///  - A2: import singolo da URL Waymarked
///  - A4: storico ultimi import
///  - C9: activity-type smart dal tag OSM `route` (lato service)
///  - C10: update mode invece di skip su trail esistente
class TrailImportPage extends StatefulWidget {
  const TrailImportPage({super.key});

  @override
  State<TrailImportPage> createState() => _TrailImportPageState();
}

class _TrailImportPageState extends State<TrailImportPage> {
  final TrailImportService _importService = TrailImportService();
  final TextEditingController _searchTermsController = TextEditingController();
  final TextEditingController _customRegionController = TextEditingController();
  final TextEditingController _singleUrlController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  ItalianRegion? _selectedRegion; // A1: regione ufficiale
  bool _useCustomRegion = false; // toggle "Area custom"
  bool _updateExisting = false; // C10: aggiorna invece di skip

  bool _isImporting = false;
  ImportProgress? _progress;
  ImportResult? _result;
  String _log = '';

  // Preset di ricerca per aree geografiche / catene montuose specifiche
  // (utili come termini di ricerca quando la regione amministrativa non
  // è sufficiente per nominare la zona).
  static const Map<String, List<String>> _presets = {
    'Orobie': [
      'pizzo coca', 'pizzo redorta', 'pizzo tre signori',
      'rifugio curò', 'rifugio brunone', 'rifugio fratelli calvi',
      'alta via delle orobie', 'sentiero delle orobie',
      'val brembana', 'val seriana', 'val di scalve',
    ],
    'Adamello-Brenta': [
      'monte adamello', 'cima tosa', 'cima brenta',
      'rifugio tuckett', 'rifugio brentei', 'rifugio mandrone',
      'sentiero delle bocchette', 'via delle bocchette',
      'val genova', 'val rendena',
    ],
    'Bergamo': [
      'resegone', 'monte arera', 'monte alben',
      'rifugio rosalba', 'rifugio lecco',
      'piani di bobbio', 'san pellegrino terme',
    ],
    'Valtellina': [
      'pizzo bernina', 'pizzo scalino', 'monte disgrazia',
      'rifugio marinelli', 'rifugio bignami',
      'sentiero roma', 'alta via della valmalenco',
    ],
    'Dolomiti': [
      'tre cime di lavaredo', 'marmolada', 'sassolungo',
      'rifugio auronzo', 'rifugio locatelli',
      'alta via dolomiti', 'sentiero degli alpini',
    ],
  };

  @override
  void dispose() {
    _searchTermsController.dispose();
    _customRegionController.dispose();
    _singleUrlController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _loadPreset(String presetName) {
    final terms = _presets[presetName];
    if (terms == null) return;
    setState(() {
      _searchTermsController.text = terms.join('\n');
      // Se l'utente non ha selezionato una regione ufficiale, usa il
      // preset come "area custom" per backward compat
      if (_selectedRegion == null) {
        _useCustomRegion = true;
        _customRegionController.text = presetName;
      }
    });
  }

  String get _effectiveRegionLabel {
    if (_useCustomRegion) return _customRegionController.text.trim();
    return _selectedRegion?.nameIt ?? '';
  }

  Future<void> _startImport() async {
    final region = _effectiveRegionLabel;
    final termsText = _searchTermsController.text.trim();

    if (region.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Seleziona una regione (o attiva "Area custom" e inserisci nome)')),
      );
      return;
    }
    // Se abbiamo una regione ufficiale con bbox, i termini diventano
    // opzionali: il service cerca direttamente per bbox e trova tutti i
    // sentieri della regione. Per "Area custom" invece i termini
    // restano obbligatori perché Nominatim può dare bbox poco precisi.
    final hasOfficialRegion = !_useCustomRegion && _selectedRegion != null;
    if (termsText.isEmpty && !hasOfficialRegion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Inserisci almeno un termine di ricerca (o seleziona una regione dal dropdown)')),
      );
      return;
    }

    final terms = termsText
        .split('\n')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    setState(() {
      _isImporting = true;
      _progress = null;
      _result = null;
      _log = '';
    });

    _addLog('🚀 Avvio import per: $region');
    _addLog('📝 Termini di ricerca: ${terms.length}');
    if (_updateExisting) _addLog('🔄 Update mode attivo (no skip)');
    _addLog('');

    try {
      List<double>? geoBbox;
      if (_useCustomRegion) {
        // Custom: usa Nominatim per geocoding
        _addLog('🗺️ Ricerca coordinate per: $region');
        final bbox = await _importService.getBboxFromPlaceName(region);
        if (bbox != null) {
          geoBbox = [
            bbox['minLat']!,
            bbox['maxLat']!,
            bbox['minLng']!,
            bbox['maxLng']!,
          ];
          _addLog('📍 Area trovata: ${_bboxLabel(geoBbox)}');
        } else {
          _addLog('⚠️ Area non trovata, uso ricerca per termini');
        }
      } else if (_selectedRegion != null) {
        // A1: usa bbox della regione italiana ufficiale (no Nominatim)
        final r = _selectedRegion!;
        geoBbox = [r.latMin, r.latMax, r.lngMin, r.lngMax];
        _addLog('📍 Bbox regione ${r.nameIt}: ${_bboxLabel(geoBbox)}');
      }
      _addLog('');

      final result = await _importService.importFromWaymarked(
        searchTerms: terms,
        geoBbox: geoBbox,
        region: region,
        updateExisting: _updateExisting,
        onProgress: (progress) {
          setState(() => _progress = progress);
          if (progress.phase == 'search') {
            _addLog('🔍 ${progress.message}');
          } else if (progress.current % 5 == 0) {
            _addLog('📥 ${progress.message}');
          }
        },
      );

      setState(() => _result = result);

      _addLog('');
      _addLog('═' * 40);
      _addLog('📊 RISULTATI');
      _addLog('═' * 40);
      _addLog('✅ Importati: ${result.imported.length}');
      _addLog('⏭️  Saltati: ${result.skipped.length}');
      _addLog('❌ Errori: ${result.errors.length}');

      if (result.imported.isNotEmpty) {
        final totalKm = result.imported
                .fold<double>(0, (sum, t) => sum + t.distance) /
            1000;
        final totalGain = result.imported
            .fold<double>(0, (sum, t) => sum + t.elevationGain);
        _addLog('');
        _addLog('📈 Statistiche:');
        _addLog('   Km totali: ${totalKm.toStringAsFixed(0)} km');
        _addLog('   Dislivello: +${totalGain.round()} m');
      }

      if (result.skipped.isNotEmpty && result.skipped.length <= 10) {
        _addLog('');
        _addLog('⏭️ Saltati:');
        for (final s in result.skipped) {
          _addLog('   - ${s.name}: ${s.reason}');
        }
      }
    } catch (e) {
      _addLog('❌ Errore fatale: $e');
    } finally {
      setState(() => _isImporting = false);
    }
  }

  Future<void> _startSingleImport() async {
    final raw = _singleUrlController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incolla URL o ID Waymarked')),
      );
      return;
    }
    final id = _importService.parseWaymarkedId(raw);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Formato non riconosciuto. Esempio: https://hiking.waymarkedtrails.org/#?route?id=12345')),
      );
      return;
    }
    final region = _effectiveRegionLabel.isEmpty ? 'manual' : _effectiveRegionLabel;

    setState(() {
      _isImporting = true;
      _progress = null;
      _result = null;
      _log = '';
    });

    _addLog('🚀 Import singolo: relation $id');
    _addLog('📍 Regione tag: $region');
    if (_updateExisting) _addLog('🔄 Update mode attivo');
    _addLog('');

    try {
      final result = await _importService.importSingleFromWaymarked(
        relationId: id,
        region: region,
        updateExisting: _updateExisting,
        onProgress: (p) {
          setState(() => _progress = p);
          _addLog('📥 ${p.message}');
        },
      );
      setState(() => _result = result);
      _addLog('');
      _addLog('📊 RISULTATI');
      _addLog('✅ Importati: ${result.imported.length}');
      _addLog('⏭️  Saltati: ${result.skipped.length}');
      _addLog('❌ Errori: ${result.errors.length}');
      for (final s in result.skipped) {
        _addLog('   - ${s.name}: ${s.reason}');
      }
      for (final e in result.errors) {
        _addLog('   - ${e.name}: ${e.error}');
      }
    } catch (e) {
      _addLog('❌ Errore: $e');
    } finally {
      setState(() => _isImporting = false);
    }
  }

  String _bboxLabel(List<double> bbox) =>
      '${bbox[0].toStringAsFixed(2)},${bbox[1].toStringAsFixed(2)} - ${bbox[2].toStringAsFixed(2)},${bbox[3].toStringAsFixed(2)}';

  void _addLog(String message) {
    setState(() => _log += '$message\n');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Sentieri')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 16),
            _buildSingleUrlCard(),
            const SizedBox(height: 16),
            _buildRegionCard(),
            const SizedBox(height: 16),
            _buildPresetCard(),
            const SizedBox(height: 16),
            _buildFormCard(),
            if (_progress != null) ...[
              const SizedBox(height: 16),
              _buildProgressCard(),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _buildResultsCard(),
            ],
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildLogCard(),
            ],
            const SizedBox(height: 16),
            _buildHistoryCard(),
            const SizedBox(height: 16),
            _buildMigrationCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.hiking, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Waymarked Trails Import',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Importa sentieri di alta qualità da Waymarked Trails (CAI, sentieri segnati, etc.). '
              'I sentieri vengono arricchiti con dati di elevazione da OpenTopoData.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleUrlCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.link, color: AppColors.primary, size: 20),
                SizedBox(width: 6),
                Text('Import singolo (URL Waymarked)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Incolla URL o ID relation per importare un singolo sentiero.',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _singleUrlController,
              enabled: !_isImporting,
              decoration: const InputDecoration(
                hintText: 'https://hiking.waymarkedtrails.org/#?route?id=12345',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.public),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isImporting ? null : _startSingleImport,
                icon: const Icon(Icons.download),
                label: const Text('Importa singolo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.map, color: AppColors.primary, size: 20),
                const SizedBox(width: 6),
                const Text('Regione',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  _useCustomRegion ? 'Custom' : 'Italia',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[600]),
                ),
                Switch(
                  value: _useCustomRegion,
                  onChanged: _isImporting
                      ? null
                      : (v) => setState(() {
                            _useCustomRegion = v;
                            if (!v) _customRegionController.clear();
                          }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_useCustomRegion)
              DropdownButtonFormField<ItalianRegion>(
                initialValue: _selectedRegion,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  hintText: 'Seleziona regione',
                ),
                items: ItalianRegions.all
                    .where((r) => r.code != 'international')
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text('${r.flag}  ${r.nameIt}'),
                        ))
                    .toList(),
                onChanged: _isImporting
                    ? null
                    : (v) => setState(() => _selectedRegion = v),
              )
            else
              TextField(
                controller: _customRegionController,
                enabled: !_isImporting,
                decoration: const InputDecoration(
                  hintText: 'Es: Orobie, Adamello-Brenta, Bergamo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            SizedBox(height: 12),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(context.l10n.updateAlreadyImported,
                  style: TextStyle(fontSize: 13)),
              subtitle: Text(
                'Se selezionato, sovrascrive geometria e stats invece di skip',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              value: _updateExisting,
              onChanged: _isImporting
                  ? null
                  : (v) => setState(() => _updateExisting = v ?? false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Preset termini',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Pre-popola i termini di ricerca con preset comuni',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.keys
                  .map((name) => ActionChip(
                        label: Text(name),
                        onPressed:
                            _isImporting ? null : () => _loadPreset(name),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedRegion != null && !_useCustomRegion
                  ? 'Termini opzionali: con regione dal dropdown la ricerca è geografica (bbox).'
                  : 'Inserisci almeno un termine.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchTermsController,
              decoration: InputDecoration(
                labelText:
                    'Termini di ricerca (uno per riga, opzionali con dropdown regione)',
                hintText:
                    'rifugio curò\npizzo coca\nalta via orobie',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                alignLabelWithHint: true,
              ),
              maxLines: 8,
              enabled: !_isImporting,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isImporting ? null : _startImport,
                icon: _isImporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download),
                label: Text(_isImporting ? 'Import in corso...' : 'Avvia import'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _progress!.phase == 'search' ? 'Ricerca...' : 'Importazione...',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('${_progress!.current}/${_progress!.total}'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress!.percentage),
            const SizedBox(height: 8),
            Text(_progress!.message,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsCard() {
    return Card(
      color: _result!.errors.isEmpty
          ? AppColors.success.withValues(alpha: 0.1)
          : AppColors.warning.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _StatBox(
              icon: Icons.check_circle,
              color: AppColors.success,
              value: '${_result!.imported.length}',
              label: 'Importati',
            ),
            const SizedBox(width: 16),
            _StatBox(
              icon: Icons.skip_next,
              color: AppColors.warning,
              value: '${_result!.skipped.length}',
              label: 'Saltati',
            ),
            const SizedBox(width: 16),
            _StatBox(
              icon: Icons.error,
              color: AppColors.danger,
              value: '${_result!.errors.length}',
              label: 'Errori',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child:
                Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: SingleChildScrollView(
              controller: _logScrollController,
              padding: const EdgeInsets.all(12),
              child: Text(
                _log,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A4 — Storico ultimi 10 import. Stream live così appare subito
  /// dopo un nuovo import senza dover ricaricare la pagina.
  Widget _buildHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history, color: AppColors.primary, size: 20),
                SizedBox(width: 6),
                Text('Storico import',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('trail_imports')
                  .orderBy('at', descending: true)
                  .limit(10)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Nessun import registrato',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  );
                }
                return Column(
                  children: docs.map((d) {
                    final data = d.data();
                    final at = data['at'];
                    final dt = at is Timestamp ? at.toDate() : null;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: (data['errors'] as int? ?? 0) > 0
                                  ? AppColors.warning
                                  : AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${data['regionName'] ?? 'sconosciuta'} · '
                                  '${data['imported'] ?? 0} OK · '
                                  '${data['skipped'] ?? 0} skip · '
                                  '${data['errors'] ?? 0} err',
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  data['source']?.toString() ?? '',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          if (dt != null)
                            Text(
                              _formatDateTime(dt),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600]),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} $h:$m';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MIGRAZIONE SPLIT public_trails → public_trail_geometries
  // ─────────────────────────────────────────────────────────────────────────
  bool _isMigrating = false;
  String _migrationLog = '';

  Future<void> _runMigration({bool dryRun = false}) async {
    setState(() {
      _isMigrating = true;
      _migrationLog = dryRun ? '🧪 DRY RUN avviato...\n' : '🚀 Migrazione avviata...\n';
    });
    final fn = FirebaseFunctions.instanceFor(region: 'europe-west3')
        .httpsCallable('migratePublicTrailsSplit');
    String? startAfter;
    int totalScanned = 0, totalMigrated = 0, totalAlready = 0, totalErrors = 0;
    try {
      while (true) {
        final res = await fn.call({
          'batchSize': 200,
          'dryRun': dryRun,
          if (startAfter != null) 'startAfter': startAfter,
        });
        final data = Map<String, dynamic>.from(res.data as Map);
        totalScanned += (data['scanned'] as int);
        totalMigrated += (data['migrated'] as int);
        totalAlready += (data['alreadyMigrated'] as int);
        totalErrors += (data['errors'] as int);
        setState(() {
          _migrationLog +=
              '📦 batch: scanned=${data['scanned']} migrated=${data['migrated']} already=${data['alreadyMigrated']} errors=${data['errors']}\n';
        });
        if (data['hasMore'] != true) break;
        startAfter = data['nextStartAfter'] as String?;
      }
      setState(() {
        _migrationLog +=
            '\n✅ FATTO: scanned=$totalScanned migrated=$totalMigrated already=$totalAlready errors=$totalErrors\n';
      });
    } catch (e) {
      setState(() => _migrationLog += '\n❌ Errore: $e\n');
    } finally {
      setState(() => _isMigrating = false);
    }
  }

  Widget _buildMigrationCard() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.swap_horiz, color: Colors.orange),
                SizedBox(width: 8),
                Text('Migrazione split geometry',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
                'One-shot: sposta `geometry.coordinatesJson` da public_trails a public_trail_geometries e aggiunge `simplifiedPoints` per Discover. Idempotente.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isMigrating ? null : () => _runMigration(dryRun: true),
                  icon: const Icon(Icons.science, size: 18),
                  label: const Text('Dry run'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isMigrating ? null : () => _runMigration(dryRun: false),
                  icon: _isMigrating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow, size: 18),
                  label: Text(_isMigrating ? 'In corso...' : 'Esegui migrazione'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                ),
              ],
            ),
            if (_migrationLog.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_migrationLog,
                    style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11)),
              ),
            ],
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
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
