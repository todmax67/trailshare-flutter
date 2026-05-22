import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/poi_voice_prefs.dart';
import '../../../data/models/trail_poi.dart';

/// Pagina settings per configurare quali tipi di POI vengono annunciati
/// vocalmente durante la registrazione guidata.
///
/// Reacheable da: Impostazioni → Navigazione → Annunci POI.
class PoiVoiceSettingsPage extends StatefulWidget {
  const PoiVoiceSettingsPage({super.key});

  @override
  State<PoiVoiceSettingsPage> createState() => _PoiVoiceSettingsPageState();
}

class _PoiVoiceSettingsPageState extends State<PoiVoiceSettingsPage> {
  final _prefs = PoiVoicePrefs();
  final Map<PoiType, bool> _state = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final t in PoiType.values) {
      _state[t] = await _prefs.isAnnounceable(t);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(PoiType type, bool val) async {
    await _prefs.setAnnounceable(type, val);
    if (mounted) setState(() => _state[type] = val);
  }

  Future<void> _resetDefaults() async {
    for (final t in PoiType.values) {
      await _prefs.setAnnounceable(t, null);
      _state[t] = t.isDefaultAnnounceable;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annunci POI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Ripristina predefiniti',
            onPressed: _resetDefaults,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.info.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.record_voice_over,
                          color: AppColors.info),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Avvisi vocali POI',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Durante la registrazione guidata, l\'app ti avvisa a voce quando ti avvicini a un POI. '
                              'Scegli quali tipi annunciare. Soglie: 500m, 200m, 50m.',
                              style: TextStyle(
                                  fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Critici (consigliati)
                _sectionHeader('Tipi critici (consigliati)'),
                ...PoiType.values
                    .where((t) => t.isDefaultAnnounceable)
                    .map(_buildTile),

                const SizedBox(height: 12),

                // Non-critici
                _sectionHeader('Altri tipi'),
                ...PoiType.values
                    .where((t) => !t.isDefaultAnnounceable)
                    .map(_buildTile),

                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildTile(PoiType t) {
    final enabled = _state[t] ?? t.isDefaultAnnounceable;
    return SwitchListTile(
      value: enabled,
      onChanged: (v) => _toggle(t, v),
      secondary: CircleAvatar(
        backgroundColor: t.pinColor,
        child: Text(t.emoji, style: const TextStyle(fontSize: 16)),
      ),
      title: Text(t.displayName),
      subtitle: Text(
        t.description,
        style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      dense: true,
    );
  }
}
