import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/offline_maps_service.dart';

/// Pagina gestione mappe offline
class OfflineMapsPage extends StatefulWidget {
  const OfflineMapsPage({super.key});

  @override
  State<OfflineMapsPage> createState() => _OfflineMapsPageState();
}

class _OfflineMapsPageState extends State<OfflineMapsPage> {
  final OfflineMapsService _service = OfflineMapsService();
  
  List<OfflineRegion> _regions = [];
  int _storageUsed = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final regions = await _service.getDownloadedRegions();
    final storage = await _service.getStorageUsed();
    
    if (mounted) {
      setState(() {
        _regions = regions;
        _storageUsed = storage;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mappe Offline'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _regions.isEmpty ? null : _confirmClearAll,
            tooltip: 'Elimina tutto',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _downloadNewRegion,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.download),
        label: const Text('Scarica Area'),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Storage info
        _buildStorageCard(),
        
        // Lista regioni
        Expanded(
          child: _regions.isEmpty
              ? _buildEmptyState()
              : _buildRegionsList(),
        ),
      ],
    );
  }

  Widget _buildStorageCard() {
    final storageMB = _storageUsed / (1024 * 1024);
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.storage, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Spazio utilizzato',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${storageMB.toStringAsFixed(1)} MB',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${_regions.length} ${_regions.length == 1 ? 'area' : 'aree'}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text(
              'Nessuna mappa offline',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Scarica mappe per usarle quando sei senza connessione',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _regions.length,
      itemBuilder: (context, index) {
        final region = _regions[index];
        return _RegionCard(
          region: region,
          onDelete: () => _deleteRegion(region),
        );
      },
    );
  }

  Future<void> _downloadNewRegion() async {
    final result = await Navigator.push<MapBounds>(
      context,
      MaterialPageRoute(
        builder: (_) => const _SelectAreaPage(),
      ),
    );

    if (result != null && mounted) {
      await _showDownloadDialog(result);
    }
  }

  Future<void> _showDownloadDialog(MapBounds bounds) async {
    final nameController = TextEditingController();
    int minZoom = 10;
    int maxZoom = 15;
    String nameValue = '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Listener per aggiornare stato quando si digita
          nameController.addListener(() {
            if (nameValue != nameController.text) {
              nameValue = nameController.text;
              setDialogState(() {});
            }
          });
          
          final tileCount = _service.estimateTileCount(bounds, minZoom, maxZoom);
          final sizeMB = _service.estimateDownloadSize(tileCount);

          return AlertDialog(
            title: const Text('Scarica Area'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome area',
                      hintText: 'Es: Dolomiti, Appennino...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Zoom minimo: $minZoom'),
                  Slider(
                    value: minZoom.toDouble(),
                    min: 8,
                    max: maxZoom.toDouble(),
                    divisions: maxZoom - 8,
                    onChanged: (v) => setDialogState(() => minZoom = v.toInt()),
                  ),
                  Text('Zoom massimo: $maxZoom'),
                  Slider(
                    value: maxZoom.toDouble(),
                    min: minZoom.toDouble(),
                    max: 17,
                    divisions: 17 - minZoom,
                    onChanged: (v) => setDialogState(() => maxZoom = v.toInt()),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tile da scaricare:'),
                      Text('$tileCount', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Dimensione stimata:'),
                      Text('~${sizeMB.toStringAsFixed(1)} MB', 
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: nameController.text.trim().isNotEmpty
                    ? () => Navigator.pop(context, true)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Scarica'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      await _startDownload(
        nameController.text.trim(),
        bounds,
        minZoom,
        maxZoom,
      );
    }
  }

  Future<void> _startDownload(
    String name,
    MapBounds bounds,
    int minZoom,
    int maxZoom,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(
        service: _service,
        regionName: name,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
      ),
    );
  }

  Future<void> _deleteRegion(OfflineRegion region) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina area'),
        content: Text('Vuoi eliminare "${region.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.deleteRegion(region.name);
      _loadData();
    }
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina tutte le mappe'),
        content: const Text('Vuoi eliminare tutte le mappe offline? Questa azione non può essere annullata.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Elimina tutto'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.clearAllTiles();
      _loadData();
    }
  }
}

/// Card per una regione offline
class _RegionCard extends StatelessWidget {
  final OfflineRegion region;
  final VoidCallback onDelete;

  const _RegionCard({
    required this.region,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.check_circle, color: AppColors.success),
        ),
        title: Text(region.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${region.tileCount} tile • ~${region.estimatedSizeMB.toStringAsFixed(1)} MB\n'
          'Zoom ${region.minZoom}-${region.maxZoom}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
          color: AppColors.danger,
        ),
      ),
    );
  }
}

/// Pagina per selezionare l'area da scaricare
class _SelectAreaPage extends StatefulWidget {
  const _SelectAreaPage();

  @override
  State<_SelectAreaPage> createState() => _SelectAreaPageState();
}

class _SelectAreaPageState extends State<_SelectAreaPage> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(45.5, 11.0); // Nord Italia default
  double _radiusKm = 5.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleziona Area'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text('Conferma'),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Mappa
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 10,
              onTap: (_, point) {
                setState(() => _center = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.trailshare',
              ),
              // Cerchio area selezionata
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _center,
                    radius: _radiusKm * 1000, // metri
                    useRadiusInMeter: true,
                    color: AppColors.primary.withOpacity(0.2),
                    borderColor: AppColors.primary,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              // Marker centro
              MarkerLayer(
                markers: [
                  Marker(
                    point: _center,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_on,
                      color: AppColors.primary,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          // Controllo raggio
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tocca la mappa per selezionare il centro',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Raggio:'),
                        Expanded(
                          child: Slider(
                            value: _radiusKm,
                            min: 1,
                            max: 20,
                            divisions: 19,
                            label: '${_radiusKm.toStringAsFixed(0)} km',
                            onChanged: (v) => setState(() => _radiusKm = v),
                          ),
                        ),
                        Text('${_radiusKm.toStringAsFixed(0)} km'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirm() {
    final bounds = MapBounds.fromCenter(
      lat: _center.latitude,
      lon: _center.longitude,
      radiusKm: _radiusKm,
    );
    Navigator.pop(context, bounds);
  }
}

/// Dialog progresso download
class _DownloadProgressDialog extends StatefulWidget {
  final OfflineMapsService service;
  final String regionName;
  final MapBounds bounds;
  final int minZoom;
  final int maxZoom;

  const _DownloadProgressDialog({
    required this.service,
    required this.regionName,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  int _downloaded = 0;
  int _total = 0;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final result = await widget.service.downloadArea(
        bounds: widget.bounds,
        minZoom: widget.minZoom,
        maxZoom: widget.maxZoom,
        regionName: widget.regionName,
        onProgress: (progress, downloaded, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _downloaded = downloaded;
              _total = total;
            });
          }
        },
      );

      if (mounted) {
        setState(() => _completed = true);
        
        await Future.delayed(const Duration(seconds: 1));
        
        if (mounted) {
          Navigator.pop(context);
          // Ricarica la lista
          if (context.mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const OfflineMapsPage()),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_completed ? '✓ Completato!' : 'Download in corso...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger))
          else ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            Text('$_downloaded / $_total tile'),
            Text('${(_progress * 100).toStringAsFixed(0)}%'),
          ],
        ],
      ),
      actions: _completed || _error != null
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Chiudi'),
              ),
            ]
          : null,
    );
  }
}
