import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/health_service.dart';
import '../../../core/services/polar_service.dart';
import '../../../core/services/strava_service.dart';
import '../../widgets/app_snackbar.dart';
import '../settings/health_dashboard_page.dart';
import '../tracks/import_gpx_page.dart';
import 'garmin_pairing_page.dart';
import 'watch_import_page.dart';

/// Hub unico, scopribile, di **Dispositivi & sincronizzazione**: documenta in
/// modo onesto cosa è supportato per ogni canale (Salute/Apple Watch, Strava,
/// Garmin, fascia cardio) con le capacità reali per piattaforma + le azioni.
class DevicesSyncPage extends StatefulWidget {
  const DevicesSyncPage({super.key});

  @override
  State<DevicesSyncPage> createState() => _DevicesSyncPageState();
}

class _DevicesSyncPageState extends State<DevicesSyncPage> {
  final _strava = StravaService();
  final _polar = PolarService();
  bool _healthSync = false;
  bool _busyHealth = false;
  bool _autoUpload = false;

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  Future<void> _loadStates() async {
    final hs = await HealthService().isSyncEnabled();
    final au = await _strava.isAutoUploadEnabled();
    if (!mounted) return;
    setState(() {
      _healthSync = hs;
      _autoUpload = au;
    });
  }

  Future<void> _toggleHealth(bool v) async {
    setState(() => _busyHealth = true);
    if (v) {
      final granted = await HealthService().requestPermissions();
      if (!granted) {
        if (mounted) {
          setState(() => _busyHealth = false);
          AppSnackBar.info(context, 'Permesso Salute non concesso');
        }
        return;
      }
    }
    await HealthService().setSyncEnabled(v);
    if (mounted) {
      setState(() {
        _healthSync = v;
        _busyHealth = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;
    final healthName = isIOS ? 'Apple Health' : 'Health Connect';

    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivi & sync')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 0, 6, 12),
            child: Text(
              'Come collegare orologi, fasce e servizi a TrailShare. Ogni canale '
              'ha capacità diverse — qui trovi cosa funziona davvero.',
              style: TextStyle(color: Colors.grey),
            ),
          ),

          // ── Salute ────────────────────────────────────────────────
          _card(
            icon: Icons.favorite,
            color: AppColors.danger,
            title: healthName,
            badge: _healthSync ? 'Attivo' : null,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Salva le attività in Salute'),
                subtitle:
                    const Text('Le tue tracce TrailShare diventano workout'),
                value: _healthSync,
                onChanged: _busyHealth ? null : _toggleHealth,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.watch_outlined),
                title: const Text('Importa dall\'orologio'),
                subtitle: Text(isIOS
                    ? 'Apple Watch: importa i giri con percorso GPS'
                    : 'Importa i giri da $healthName (solo con percorso GPS)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WatchImportPage())),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Dashboard salute'),
                subtitle: const Text('Passi, FC a riposo, andamento settimanale'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const HealthDashboardPage())),
              ),
            ],
          ),

          // ── Strava ────────────────────────────────────────────────
          StreamBuilder<bool>(
            stream: _strava.connectedStream(),
            builder: (context, snap) {
              final connected = snap.data ?? false;
              return _card(
                icon: Icons.directions_run,
                color: const Color(0xFFFC4C02),
                title: 'Strava',
                badge: connected ? 'Connesso' : null,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      connected
                          ? 'Carica automaticamente le tue tracce su Strava. Le '
                              'attività da altri dispositivi sincronizzate su '
                              'Strava possono essere importate qui.'
                          : 'Collega Strava per caricare automaticamente le '
                              'tracce e importare attività da altri dispositivi.',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  if (connected)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Upload automatico'),
                      value: _autoUpload,
                      onChanged: (v) async {
                        await _strava.setAutoUploadEnabled(v);
                        if (mounted) setState(() => _autoUpload = v);
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: connected
                        ? TextButton.icon(
                            icon: const Icon(Icons.link_off, size: 18),
                            label: const Text('Disconnetti'),
                            onPressed: () => _strava.disconnect(),
                          )
                        : FilledButton.tonalIcon(
                            icon: const Icon(Icons.link, size: 18),
                            label: const Text('Connetti Strava'),
                            onPressed: () async {
                              final ok = await _strava.connect();
                              if (!ok && context.mounted) {
                                AppSnackBar.info(
                                    context, 'Impossibile aprire Strava');
                              }
                            },
                          ),
                  ),
                ],
              );
            },
          ),

          // ── Polar ─────────────────────────────────────────────────
          StreamBuilder<bool>(
            stream: _polar.connectedStream(),
            builder: (context, snap) {
              final connected = snap.data ?? false;
              return _card(
                icon: Icons.watch,
                color: const Color(0xFFD10027),
                title: 'Polar',
                badge: connected ? 'Connesso' : null,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      connected
                          ? 'Collegato a Polar Flow: gli allenamenti con GPS '
                              '(e battito) arrivano qui automaticamente appena '
                              'l\'orologio sincronizza.'
                          : 'Collega il tuo account Polar Flow: gli allenamenti '
                              'con GPS e battito arrivano in TrailShare '
                              'automaticamente, senza esportare nulla.',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: connected
                        ? TextButton.icon(
                            icon: const Icon(Icons.link_off, size: 18),
                            label: const Text('Disconnetti'),
                            onPressed: () async {
                              final ok = await _polar.disconnect();
                              if (!ok && context.mounted) {
                                AppSnackBar.info(
                                    context, 'Disconnessione non riuscita');
                              }
                            },
                          )
                        : FilledButton.tonalIcon(
                            icon: const Icon(Icons.link, size: 18),
                            label: const Text('Collega Polar'),
                            onPressed: () async {
                              final ok = await _polar.connect();
                              if (!ok && context.mounted) {
                                AppSnackBar.info(
                                    context, 'Impossibile aprire Polar Flow');
                              }
                            },
                          ),
                  ),
                ],
              );
            },
          ),

          // ── Garmin ────────────────────────────────────────────────
          _card(
            icon: Icons.watch,
            color: AppColors.primary,
            title: 'Garmin (e altri orologi)',
            children: [
              _bullet('Registra dal polso: con l\'app TrailShare per Connect IQ '
                  'sul Garmin, le attività arrivano qui automaticamente '
                  '(percorso + battito). Abbina l\'orologio col codice.'),
              _bullet('Importa un\'attività: in Garmin Connect apri l\'attività → '
                  'Esporta/Condividi il file (FIT o GPX) → "Apri con TrailShare". '
                  'Funziona con qualsiasi orologio (Garmin, Suunto, Coros…).'),
              _bullet('Trasmetti FC: attiva la trasmissione cardio sull\'orologio '
                  'e usalo come fascia durante la registrazione (battito live).'),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.watch, size: 18),
                      label: const Text('Abbina il tuo Garmin'),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const GarminPairingPage())),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Importa file attività'),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ImportGpxPage())),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Fascia cardio BLE ─────────────────────────────────────
          _card(
            icon: Icons.monitor_heart,
            color: AppColors.danger,
            title: 'Fascia cardio (Bluetooth)',
            children: [
              _bullet('Compatibile con qualsiasi fascia BLE standard: Polar H10, '
                  'Wahoo TICKR, Garmin HRM, e Garmin in modalità "Trasmetti FC".'),
              _bullet('Durante la registrazione tocca il widget cardio per '
                  'collegarla: il battito è mostrato in diretta e salvato nella '
                  'traccia.'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    String? badge,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(badge,
                        style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 6, color: Colors.grey),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
