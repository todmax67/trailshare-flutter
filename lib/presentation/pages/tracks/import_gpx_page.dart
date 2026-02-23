import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/gpx_service.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../../../core/services/fit_service.dart';

class ImportGpxPage extends StatefulWidget {
  final String? initialFilePath;
  const ImportGpxPage({super.key, this.initialFilePath});

  @override
  State<ImportGpxPage> createState() => _ImportGpxPageState();
}

class _ImportGpxPageState extends State<ImportGpxPage> {
  final GpxService _gpxService = GpxService();
  final FitService _fitService = FitService();
  final TracksRepository _tracksRepository = TracksRepository();
  final TextEditingController _nameController = TextEditingController();

  Track? _parsedTrack;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  ActivityType _selectedActivity = ActivityType.trekking;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      // Auto-parse del file ricevuto da "Apri con"
      Future.microtask(() => _parseFileFromPath(widget.initialFilePath!));
    }
  }

  Future<void> _parseFileFromPath(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _parsedTrack = null;
    });

    try {
      final file = File(path);
      final ext = path.split('.').last.toLowerCase();
      Track? track;

      if (ext == 'fit') {
        track = await _fitService.parseFitFile(file);
      } else {
        track = await _gpxService.parseGpxFile(file);
      }

      if (track == null) {
        setState(() {
          _error = 'Impossibile leggere il file. Verifica che sia un file GPX o FIT valido.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _parsedTrack = track;
        _nameController.text = track!.name;
        _selectedActivity = track.activityType;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndParseFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _parsedTrack = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx', 'fit'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final file = result.files.first;
      final extension = file.name.split('.').last.toLowerCase();
      Track? track;

      if (extension == 'fit') {
        // Parse FIT
        if (file.bytes != null) {
          track = _fitService.parseFitBytes(file.bytes!, fileName: file.name);
        } else if (file.path != null) {
          track = await _fitService.parseFitFile(File(file.path!));
        }
      } else {
        // Parse GPX
        if (file.bytes != null) {
          final content = String.fromCharCodes(file.bytes!);
          track = _gpxService.parseGpxString(content, fileName: file.name);
        } else if (file.path != null) {
          track = await _gpxService.parseGpxFile(File(file.path!));
        }
      }

      if (track == null) {
        setState(() {
          _error = 'Impossibile leggere il file GPX. Verifica che sia un file valido.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _parsedTrack = track;
        _nameController.text = track!.name;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveTrack() async {
    if (_parsedTrack == null) return;

    setState(() => _isSaving = true);

    try {
      final trackToSave = _parsedTrack!.copyWith(
        name: _nameController.text.trim().isEmpty 
            ? _parsedTrack!.name 
            : _nameController.text.trim(),
        activityType: _selectedActivity,
      );

      await _tracksRepository.saveTrack(trackToSave);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Traccia importata con successo!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore salvataggio: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importa GPX')),
      body: _parsedTrack == null ? _buildPickerView() : _buildPreviewView(),
    );
  }

  Widget _buildPickerView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.upload_file, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            const Text('Importa un file GPX', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Seleziona un file .gpx dal tuo dispositivo', 
                style: TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: _pickAndParseFile,
                icon: const Icon(Icons.folder_open),
                label: const Text('Seleziona file GPX'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.danger),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_error!, style: TextStyle(color: AppColors.danger))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewView() {
    final track = _parsedTrack!;
    final stats = track.stats;

    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: 250, child: _buildMapPreview()),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nome traccia',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.edit),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Tipo di attività', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ActivityType.values.map((type) {
                    final isSelected = type == _selectedActivity;
                    return ChoiceChip(
                      label: Text(type.displayName),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedActivity = type),
                      selectedColor: AppColors.primary.withOpacity(0.2),
                      avatar: Text(type.icon),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                const Text('Statistiche', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                _buildStatsRow(stats),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _infoRow(Icons.location_on, 'Punti GPS', '${track.points.length}'),
                        _infoRow(Icons.calendar_today, 'Data', _formatDate(track.createdAt)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _parsedTrack = null;
                          _nameController.clear();
                        }),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Cambia'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveTrack,
                        icon: _isSaving
                            ? const SizedBox(width: 20, height: 20, 
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(_isSaving ? 'Salvataggio...' : 'Salva'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPreview() {
    final track = _parsedTrack!;
    if (track.points.isEmpty) {
      return Container(color: AppColors.background, child: const Center(child: Text('Nessun dato GPS')));
    }

    final points = track.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final maxDiff = (maxLat - minLat) > (maxLng - minLng) ? (maxLat - minLat) : (maxLng - minLng);
    double zoom = maxDiff > 0.5 ? 10 : maxDiff > 0.2 ? 11 : maxDiff > 0.1 ? 12 : maxDiff > 0.05 ? 13 : 14;

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.trailshare.app'),
        PolylineLayer(polylines: [Polyline(points: points, strokeWidth: 4, color: AppColors.primary)]),
        MarkerLayer(markers: [
          Marker(point: points.first, width: 24, height: 24,
            child: Container(decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 14))),
          Marker(point: points.last, width: 24, height: 24,
            child: Container(decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.flag, color: Colors.white, size: 12))),
        ]),
      ],
    );
  }

  Widget _buildStatsRow(TrackStats stats) {
    return Row(
      children: [
        _statCard(Icons.straighten, '${(stats.distance / 1000).toStringAsFixed(1)}', 'km', 'Distanza', AppColors.primary),
        const SizedBox(width: 8),
        _statCard(Icons.trending_up, '+${stats.elevationGain.toStringAsFixed(0)}', 'm', 'Dislivello', AppColors.success),
        const SizedBox(width: 8),
        _statCard(Icons.timer, stats.duration.inMinutes > 0 ? _formatDuration(stats.duration) : '--', '', 'Durata', AppColors.info),
      ],
    );
  }

  Widget _statCard(IconData icon, String value, String unit, String label, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              RichText(text: TextSpan(children: [
                TextSpan(text: value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                if (unit.isNotEmpty) TextSpan(text: ' $unit', style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
              ])),
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
}
