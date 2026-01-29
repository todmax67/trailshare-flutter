import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/trail_import_service.dart';

/// Pagina admin per importare sentieri da Waymarked Trails
class TrailImportPage extends StatefulWidget {
  const TrailImportPage({super.key});

  @override
  State<TrailImportPage> createState() => _TrailImportPageState();
}

class _TrailImportPageState extends State<TrailImportPage> {
  final TrailImportService _importService = TrailImportService();
  final TextEditingController _searchTermsController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  
  bool _isImporting = false;
  ImportProgress? _progress;
  ImportResult? _result;
  String _log = '';
  
  // Preset di ricerca per aree geografiche
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
    _regionController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _loadPreset(String presetName) {
    final terms = _presets[presetName];
    if (terms != null) {
      _searchTermsController.text = terms.join('\n');
      _regionController.text = presetName;
    }
  }

  Future<void> _startImport() async {
    final termsText = _searchTermsController.text.trim();
    final region = _regionController.text.trim();
    
    if (termsText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci almeno un termine di ricerca')),
      );
      return;
    }
    
    if (region.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il nome della regione')),
      );
      return;
    }
    
    final terms = termsText.split('\n').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    
    setState(() {
      _isImporting = true;
      _progress = null;
      _result = null;
      _log = '';
    });
    
    _addLog('🚀 Avvio import per regione: $region');
    _addLog('📝 Termini di ricerca: ${terms.length}');
    _addLog('');
    
    try {
      // Geocoding: ottieni bbox dalla regione
      _addLog("🗺️ Ricerca coordinate per: $region");
      final bbox = await _importService.getBboxFromPlaceName(region);
      List<double>? geoBbox;
      if (bbox != null) {
        geoBbox = [bbox["minLat"]!, bbox["maxLat"]!, bbox["minLng"]!, bbox["maxLng"]!];
        _addLog("📍 Area trovata: ${geoBbox[0].toStringAsFixed(2)},${geoBbox[1].toStringAsFixed(2)} - ${geoBbox[2].toStringAsFixed(2)},${geoBbox[3].toStringAsFixed(2)}");
      } else {
        _addLog("⚠️ Area non trovata, uso ricerca per termini");
      }
      _addLog("");

      final result = await _importService.importFromWaymarked(
        searchTerms: terms,
        geoBbox: geoBbox,
        region: region,
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
        final totalKm = result.imported.fold<double>(0, (sum, t) => sum + t.distance) / 1000;
        final totalGain = result.imported.fold<double>(0, (sum, t) => sum + t.elevationGain);
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

  void _addLog(String message) {
    setState(() {
      _log += '$message\n';
    });
    // Auto-scroll al fondo
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
      appBar: AppBar(
        title: const Text('Import Sentieri'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            Card(
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
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
            ),
            
            const SizedBox(height: 16),
            
            // Preset Buttons
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Preset Aree', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presets.keys.map((name) => ActionChip(
                        label: Text(name),
                        onPressed: _isImporting ? null : () => _loadPreset(name),
                        backgroundColor: _regionController.text == name 
                            ? AppColors.primary.withOpacity(0.2) 
                            : null,
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Regione
                    TextField(
                      controller: _regionController,
                      decoration: const InputDecoration(
                        labelText: 'Nome Regione',
                        hintText: 'Es: Orobie, Adamello-Brenta',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.map),
                      ),
                      enabled: !_isImporting,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Termini di ricerca
                    TextField(
                      controller: _searchTermsController,
                      decoration: const InputDecoration(
                        labelText: 'Termini di Ricerca (uno per riga)',
                        hintText: 'rifugio curò\npizzo coca\nalta via orobie',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 8,
                      enabled: !_isImporting,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Pulsante Import
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isImporting ? null : _startImport,
                        icon: _isImporting
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.download),
                        label: Text(_isImporting ? 'Import in corso...' : 'Avvia Import'),
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
            ),
            
            // Progress
            if (_progress != null) ...[
              const SizedBox(height: 16),
              Card(
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
                      Text(_progress!.message, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
            
            // Results
            if (_result != null) ...[
              const SizedBox(height: 16),
              Card(
                color: _result!.errors.isEmpty ? AppColors.success.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
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
              ),
            ],
            
            // Log
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
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
              ),
            ],
            
            const SizedBox(height: 32),
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

  const _StatBox({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
