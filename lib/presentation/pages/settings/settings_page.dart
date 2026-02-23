import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/theme_service.dart';
import 'privacy_policy_page.dart';
import '../../../core/services/delete_account_service.dart';
import 'offline_maps_page.dart';
import 'faq_page.dart';
import '../admin/geohash_migration_page.dart';
import '../admin/trail_import_page.dart';
import '../admin/database_stats_page.dart';
import '../admin/recalculate_stats_page.dart';
import 'dart:io';
import 'package:health/health.dart';
import '../../../core/services/health_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'health_dashboard_page.dart';

/// Pagina Impostazioni
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '';
  final ThemeService _themeService = ThemeService();
  final HealthService _healthService = HealthService();
  bool _healthSyncEnabled = false;
  int _maxHR = 0;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadHealthSync();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = '${info.version} (${info.buildNumber})';
      });
    } catch (e) {
      setState(() => _appVersion = '1.0.0');
    }
  }

  Future<void> _loadHealthSync() async {
    final enabled = await _healthService.isSyncEnabled();
    if (mounted) setState(() => _healthSyncEnabled = enabled);
  }

  Future<void> _loadMaxHR() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('user_max_hr') ?? 0;
    if (mounted) setState(() => _maxHR = saved);
  }

  Future<void> _showMaxHRDialog() async {
    final ageController = TextEditingController();
    final hrController = TextEditingController(
      text: _maxHR > 0 ? '$_maxHR' : '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Frequenza cardiaca massima'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Inserisci la tua FC max se la conosci, oppure inserisci la tua età per stimarla (220 - età).',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hrController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'FC Max (BPM)',
                hintText: 'Es: 185',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('oppure', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Età',
                hintText: 'Es: 35',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                final age = int.tryParse(val);
                if (age != null && age > 10 && age < 100) {
                  hrController.text = '${220 - age}';
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () async {
              final hr = int.tryParse(hrController.text);
              if (hr != null && hr > 100 && hr < 250) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('user_max_hr', hr);
                setState(() => _maxHR = hr);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  bool _isAdmin(User? user) {
    if (user == null) return false;
    
    const adminEmails = [
      'admin@trailshare.app',
      'todde.massimiliano@gmail.com',  // ← Metti la tua email!
    ];
    
    return adminEmails.contains(user.email?.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Sezione Account (solo se loggato)
          if (user != null) ...[
            _buildSectionHeader('Account'),
            _buildListTile(
              icon: Icons.person_outline,
              title: 'Email',
              subtitle: user.email ?? 'Non disponibile',
            ),
            _buildListTile(
              icon: Icons.logout,
              title: 'Esci',
              subtitle: 'Disconnetti il tuo account',
              onTap: () => _signOut(context),
            ),
            const Divider(height: 32),
          ],

          // Sezione Aspetto
          _buildSectionHeader('Aspetto'),
          _buildThemeTile(),
          const Divider(height: 32),

          // Sezione Salute
          _buildSectionHeader('Connessione Salute'),
          SwitchListTile(
            secondary: Icon(
              Icons.favorite_outline,
              color: _healthSyncEnabled ? AppColors.danger : AppColors.textSecondary,
            ),
            title: const Text('Sincronizza con Salute'),
            subtitle: Text(
              Platform.isIOS
                  ? 'Salva le attività su Apple Salute'
                  : 'Salva le attività su Health Connect',
            ),
            value: _healthSyncEnabled,
            activeColor: AppColors.primary,
            onChanged: (value) async {
              if (value) {
                if (Platform.isAndroid) {
                  final available = await _healthService.isHealthConnectAvailable();
                  if (!available) {
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Health Connect necessario'),
                          content: const Text(
                            'Per sincronizzare le attività è necessario installare '
                            'Health Connect dal Play Store.\n\n'
                            'Vuoi installarlo ora?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Annulla'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Health().installHealthConnect();
                              },
                              child: const Text('Installa'),
                            ),
                          ],
                        ),
                      );
                    }
                    return;
                  }
                }
                final granted = await _healthService.requestPermissions();
                debugPrint('[Settings] Permessi concessi: $granted');
                if (!granted && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Permessi non concessi. Riprova o abilita dalle impostazioni del dispositivo.'),
                      backgroundColor: AppColors.warning,
                    ),
                  );
                  return;
                }
              }
              await _healthService.setSyncEnabled(value);
              setState(() => _healthSyncEnabled = value);
            },
          ),
          if (_healthSyncEnabled) ...[
            ListTile(
              leading: const Icon(Icons.monitor_heart, color: AppColors.danger),
              title: const Text('Frequenza cardiaca massima'),
              subtitle: Text(
                _maxHR > 0 ? '$_maxHR BPM' : 'Imposta per calcolare le zone cardio',
              ),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () => _showMaxHRDialog(),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard, color: AppColors.primary),
              title: const Text('Dashboard Salute'),
              subtitle: const Text('Passi, battito, calorie settimanali'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HealthDashboardPage()),
              ),
            ),
          ],
          const Divider(height: 32),

          // Sezione Legale
          _buildSectionHeader('Legale'),
          _buildListTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'Come gestiamo i tuoi dati',
            onTap: () => _openPrivacyPolicy(context),
          ),
          _buildListTile(
            icon: Icons.description_outlined,
            title: 'Termini di Servizio',
            subtitle: 'Condizioni d\'uso dell\'app',
            onTap: () => _openTermsOfService(context),
          ),
          _buildListTile(
            icon: Icons.gavel_outlined,
            title: 'Licenze Open Source',
            subtitle: 'Librerie utilizzate',
            onTap: () => _openLicenses(context),
          ),
          const Divider(height: 32),

          // Sezione Supporto
          _buildSectionHeader('Supporto'),
          _buildListTile(
            icon: Icons.help_outline,
            title: 'Centro Assistenza',
            subtitle: 'FAQ e guide',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FaqPage()),
              );
            },
          ),
          _buildListTile(
            icon: Icons.email_outlined,
            title: 'Contattaci',
            subtitle: 'support@trailshare.app',
            onTap: () => _openEmail(context),
          ),
          _buildListTile(
            icon: Icons.star_outline,
            title: 'Valuta l\'app',
            subtitle: 'Lascia una recensione',
            onTap: () => _openAppStore(context),
          ),
          _buildListTile(
            icon: Icons.map_outlined,
            title: 'Mappe Offline',
            subtitle: 'Scarica mappe per uso senza connessione',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OfflineMapsPage()),
              );
            },
          ),
          const Divider(height: 32),

          // Sezione Info
          _buildSectionHeader('Informazioni'),
          _buildListTile(
            icon: Icons.info_outline,
            title: 'Versione',
            subtitle: _appVersion.isNotEmpty ? _appVersion : 'Caricamento...',
          ),
          _buildListTile(
            icon: Icons.update,
            title: 'Novità',
            subtitle: 'Cosa c\'è di nuovo',
            onTap: () => _showChangelog(context),
          ),

          // Sezione Admin (solo per admin/sviluppatori)
          // TODO: In produzione, controllare se l'utente è admin
          if (_isAdmin(user)) ...[
            const Divider(height: 32),
            _buildSectionHeader('Amministrazione', danger: false),
            _buildListTile(
              icon: Icons.download,
              title: 'Import Sentieri',
              subtitle: 'Importa sentieri da Waymarked Trails',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TrailImportPage()),
                );
              },
            ),
            _buildListTile(
              icon: Icons.location_on,
              title: 'Migrazione GeoHash',
              subtitle: 'Gestisci indici geospaziali per i sentieri',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GeohashMigrationPage()),
                );
              },
            ),
            _buildListTile(
              icon: Icons.analytics_outlined,
              title: 'Statistiche Database',
              subtitle: 'Visualizza metriche e utilizzo',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DatabaseStatsPage()),
                );
              },
            ),
          ],

          _buildListTile(
            icon: Icons.calculate,
            title: 'Ricalcola Statistiche',
            subtitle: 'Correggi dislivello e distanze dalle tracce GPS',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecalculateStatsPage()),
              );
            },
          ),

          // Zona pericolosa (solo se loggato)
          if (user != null) ...[
            const Divider(height: 32),
            _buildSectionHeader('Zona Pericolosa', danger: true),
            _buildListTile(
              icon: Icons.delete_forever,
              title: 'Elimina Account',
              subtitle: 'Elimina permanentemente tutti i tuoi dati',
              onTap: () => _deleteAccount(context),
              danger: true,
            ),
          ],

          const SizedBox(height: 32),

          // Footer
          Center(
            child: Column(
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 48,
                  height: 48,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.terrain,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'TrailShare',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  'Made with ❤️ for hikers',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: danger ? AppColors.danger : Theme.of(context).textTheme.bodySmall?.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: danger ? AppColors.danger : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: danger ? AppColors.danger : null,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: danger ? AppColors.danger.withOpacity(0.7) : null,
              ),
            )
          : null,
      trailing: onTap != null
          ? Icon(
              Icons.chevron_right,
              color: danger ? AppColors.danger : null,
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _buildThemeTile() {
    IconData icon;
    String subtitle;

    switch (_themeService.themeMode) {
      case ThemeMode.system:
        icon = Icons.brightness_auto;
        subtitle = 'Automatico';
        break;
      case ThemeMode.light:
        icon = Icons.light_mode;
        subtitle = 'Chiaro';
        break;
      case ThemeMode.dark:
        icon = Icons.dark_mode;
        subtitle = 'Scuro';
        break;
    }

    return ListTile(
      leading: Icon(icon),
      title: const Text('Tema', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      trailing: const Icon(Icons.chevron_right),
      onTap: _showThemeDialog,
    );
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleziona tema'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildThemeOption(
              icon: Icons.brightness_auto,
              label: 'Automatico',
              subtitle: 'Segue le impostazioni di sistema',
              mode: ThemeMode.system,
            ),
            _buildThemeOption(
              icon: Icons.light_mode,
              label: 'Chiaro',
              subtitle: 'Tema chiaro sempre attivo',
              mode: ThemeMode.light,
            ),
            _buildThemeOption(
              icon: Icons.dark_mode,
              label: 'Scuro',
              subtitle: 'Tema scuro sempre attivo',
              mode: ThemeMode.dark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required ThemeMode mode,
  }) {
    final isSelected = _themeService.themeMode == mode;

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(label),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        _themeService.setThemeMode(mode);
        Navigator.pop(context);
        setState(() {});
      },
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Esci'),
        content: const Text('Vuoi uscire dal tuo account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  void _openPrivacyPolicy(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
    );
  }

  Future<void> _openTermsOfService(BuildContext context) async {
    final uri = Uri.parse('https://trailshare.app/terms');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire il link')),
        );
      }
    }
  }

  void _openLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'TrailShare',
      applicationVersion: _appVersion,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.terrain, size: 48, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Future<void> _openHelpCenter(BuildContext context) async {
    final uri = Uri.parse('https://trailshare.app/help');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire il link')),
        );
      }
    }
  }

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri.parse('mailto:support@trailshare.app?subject=TrailShare%20Support');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire il client email')),
        );
      }
    }
  }

  Future<void> _openAppStore(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Grazie! L\'app sarà presto disponibile negli store.')),
    );
  }

  void _showChangelog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novità v1.0.0'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🎉 Prima release!', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('• Registrazione tracce GPS'),
              Text('• Tracking in background'),
              Text('• LiveTrack - condividi posizione'),
              Text('• Sistema social (follow, cheers)'),
              Text('• Classifica settimanale'),
              Text('• Wishlist percorsi'),
              Text('• Dashboard statistiche'),
              Text('• Import/Export GPX'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final result = await showDeleteAccountDialog(context);

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account eliminato con successo'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}