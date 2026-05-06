import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/constants/app_colors.dart';
import 'emergency_contacts_page.dart';
import 'poi_voice_settings_page.dart';
import '../../../core/extensions/l10n_extension.dart';
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
import '../../../data/repositories/admin_repository.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/pro_gate_service.dart';
import '../../widgets/paywall_sheet.dart';

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
  bool _isAdminUser = false;
  bool _newsUpdatesEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadHealthSync();
    _loadAdminStatus();
    _loadNewsUpdatesPref();
  }

  Future<void> _loadNewsUpdatesPref() async {
    final enabled = await PushNotificationService().getNewsUpdatesEnabled();
    if (mounted) setState(() => _newsUpdatesEnabled = enabled);
  }

  Future<void> _loadAdminStatus() async {
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (mounted) setState(() => _isAdminUser = isAdmin);
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

  Future<void> _showMaxHRDialog() async {
    final ageController = TextEditingController();
    final hrController = TextEditingController(
      text: _maxHR > 0 ? '$_maxHR' : '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.maxHeartRate),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.maxHRDescription,
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hrController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.maxHRLabel,
                hintText: context.l10n.maxHRHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(context.l10n.orLabel, style: TextStyle(color: context.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: ageController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.ageLabel,
                hintText: context.l10n.ageHint,
                border: const OutlineInputBorder(),
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
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final hr = int.tryParse(hrController.text);
              if (hr != null && hr > 100 && hr < 250) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('user_max_hr', hr);
                if (!ctx.mounted) return;
                setState(() => _maxHR = hr);
                Navigator.pop(ctx);
              }
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settings),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Sezione Account (solo se loggato)
          if (user != null) ...[
            _buildSectionHeader(context.l10n.accountSection),
            _buildListTile(
              icon: Icons.person_outline,
              title: context.l10n.emailLabel,
              subtitle: user.email ?? context.l10n.notAvailable,
            ),
            _buildListTile(
              icon: Icons.logout,
              title: context.l10n.signOutTitle,
              subtitle: context.l10n.signOutSubtitle,
              onTap: () => _signOut(context),
            ),
            const Divider(height: 32),

            // Sezione Notifiche
            _buildSectionHeader('Notifiche'),
            SwitchListTile(
              secondary: Icon(
                Icons.campaign_outlined,
                color: _newsUpdatesEnabled ? AppColors.primary : context.textSecondary,
              ),
              title: const Text('Novita e aggiornamenti'),
              subtitle: const Text(
                'Ricevi notifiche quando aggiungiamo nuove funzionalita',
              ),
              value: _newsUpdatesEnabled,
              activeThumbColor: AppColors.primary,
              onChanged: (value) async {
                setState(() => _newsUpdatesEnabled = value);
                await PushNotificationService().setNewsUpdatesEnabled(value);
              },
            ),
            const Divider(height: 32),
          ],

          // Sezione Aspetto
          _buildSectionHeader(context.l10n.appearanceSection),
          _buildThemeTile(),
          const Divider(height: 32),

          // ─── Sezione TrailShare Pro (mockup paywall) ─────────────────
          _buildSectionHeader('TrailShare Pro'),
          _buildProTile(),
          const Divider(height: 32),

          // Sezione Salute
          _buildSectionHeader(context.l10n.healthConnectionSection),
          SwitchListTile(
            secondary: Icon(
              Icons.favorite_outline,
              color: _healthSyncEnabled ? AppColors.danger : context.textSecondary,
            ),
            title: Text(context.l10n.syncWithHealth),
            subtitle: Text(
              Platform.isIOS
                  ? context.l10n.saveToAppleHealth
                  : context.l10n.saveToHealthConnect,
            ),
            value: _healthSyncEnabled,
            activeThumbColor: AppColors.primary,
            onChanged: (value) async {
              if (value) {
                if (Platform.isAndroid) {
                  final available = await _healthService.isHealthConnectAvailable();
                  if (!available) {
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(context.l10n.healthConnectRequired),
                          content: Text(
                            context.l10n.healthConnectInstallMessage,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(context.l10n.cancel),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Health().installHealthConnect();
                              },
                              child: Text(context.l10n.installAction),
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
                if (!granted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.permissionsNotGranted),
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
              title: Text(context.l10n.maxHeartRate),
              subtitle: Text(
                _maxHR > 0 ? '$_maxHR BPM' : context.l10n.setForCardioZones,
              ),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () => _showMaxHRDialog(),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard, color: AppColors.primary),
              title: Text(context.l10n.healthDashboard),
              subtitle: Text(context.l10n.healthDashboardSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HealthDashboardPage()),
              ),
            ),
          ],
          const Divider(height: 32),

          // Sezione Sicurezza
          _buildSectionHeader('Sicurezza'),
          _buildListTile(
            icon: Icons.shield_outlined,
            title: 'Contatti di emergenza',
            subtitle: 'Configura fino a 3 persone per Lifeline',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EmergencyContactsPage(),
                ),
              );
            },
          ),
          _buildListTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Annunci vocali POI',
            subtitle:
                'Scegli quali tipi di POI annunciare durante la navigazione',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PoiVoiceSettingsPage(),
                ),
              );
            },
          ),
          const Divider(height: 32),

          // Sezione Legale
          _buildSectionHeader(context.l10n.legalSection),
          _buildListTile(
            icon: Icons.privacy_tip_outlined,
            title: context.l10n.privacyPolicy,
            subtitle: context.l10n.privacyPolicySubtitle,
            onTap: () => _openPrivacyPolicy(context),
          ),
          _buildListTile(
            icon: Icons.description_outlined,
            title: context.l10n.termsOfService,
            subtitle: context.l10n.termsOfServiceSubtitle,
            onTap: () => _openTermsOfService(context),
          ),
          _buildListTile(
            icon: Icons.gavel_outlined,
            title: context.l10n.openSourceLicenses,
            subtitle: context.l10n.openSourceLicensesSubtitle,
            onTap: () => _openLicenses(context),
          ),
          const Divider(height: 32),

          // Sezione Supporto
          _buildSectionHeader(context.l10n.supportSection),
          _buildListTile(
            icon: Icons.help_outline,
            title: context.l10n.helpCenter,
            subtitle: context.l10n.helpCenterSubtitle,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FaqPage()),
              );
            },
          ),
          _buildListTile(
            icon: Icons.email_outlined,
            title: context.l10n.contactUs,
            subtitle: 'support@trailshare.app',
            onTap: () => _openEmail(context),
          ),
          _buildListTile(
            icon: Icons.star_outline,
            title: context.l10n.rateApp,
            subtitle: context.l10n.rateAppSubtitle,
            onTap: () => _openAppStore(context),
          ),
          _buildListTile(
            icon: Icons.map_outlined,
            title: context.l10n.offlineMaps,
            subtitle: context.l10n.offlineMapsSubtitle,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OfflineMapsPage()),
              );
            },
          ),
          const Divider(height: 32),

          // Sezione Info
          _buildSectionHeader(context.l10n.infoSection),
          _buildListTile(
            icon: Icons.info_outline,
            title: context.l10n.versionLabel,
            subtitle: _appVersion.isNotEmpty ? _appVersion : context.l10n.loadingEllipsis,
          ),
          _buildListTile(
            icon: Icons.update,
            title: context.l10n.whatsNew,
            subtitle: context.l10n.whatsNewSubtitle,
            onTap: () => _showChangelog(context),
          ),

          // Sezione Admin (solo per admin)
          if (_isAdminUser) ...[
            const Divider(height: 32),
            _buildSectionHeader(context.l10n.adminSection, danger: false),
            _buildListTile(
              icon: Icons.download,
              title: context.l10n.importTrails,
              subtitle: context.l10n.importTrailsSubtitle,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TrailImportPage()),
                );
              },
            ),
            _buildListTile(
              icon: Icons.location_on,
              title: context.l10n.geohashMigration,
              subtitle: context.l10n.geohashMigrationSubtitle,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GeohashMigrationPage()),
                );
              },
            ),
            _buildListTile(
              icon: Icons.analytics_outlined,
              title: context.l10n.databaseStats,
              subtitle: context.l10n.databaseStatsSubtitle,
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
            title: context.l10n.recalculateStats,
            subtitle: context.l10n.recalculateStatsSubtitle,
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
            _buildSectionHeader(context.l10n.dangerZone, danger: true),
            _buildListTile(
              icon: Icons.delete_forever,
              title: context.l10n.deleteAccount,
              subtitle: context.l10n.deleteAccountSubtitle,
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
                  errorBuilder: (_, _, _) => Icon(
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
                color: danger ? AppColors.danger.withValues(alpha: 0.7) : null,
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

  /// Tile TrailShare Pro: stato corrente + apertura paywall.
  ///
  /// Comportamento:
  /// - **iOS** (monetizzazione attiva): mostra "Passa a Pro" → apre il
  ///   paywall di acquisto reale.
  /// - **Android** (monetizzazione disattivata in attesa P.IVA): subtitle
  ///   spiega che Pro è gratis, tap apre la sheet informativa.
  Widget _buildProTile() {
    return AnimatedBuilder(
      animation: ProGateService(),
      builder: (context, _) {
        final gate = ProGateService();
        final isPro = gate.isPro;
        final canMonetize = gate.isMonetizationActive;

        // Testo dinamico in base a piattaforma + stato.
        final String tileTitle;
        final String tileSubtitle;
        if (!canMonetize) {
          // Android in attesa di P.IVA per attivare Play Billing: Pro
          // non è ancora disponibile. Comunichiamo chiaramente lo
          // stato "in arrivo" senza generare aspettativa di gratuità.
          tileTitle = 'TrailShare Pro — in arrivo su Android';
          tileSubtitle =
              'A breve potrai sbloccare AR Photo Mode, mappe Pro e altro';
        } else if (isPro) {
          tileTitle = 'TrailShare Pro attivo';
          tileSubtitle =
              'Mountain Finder AR, Photo Mode Pro e tutte le novità';
        } else {
          tileTitle = 'Passa a TrailShare Pro';
          tileSubtitle = 'Sblocca AR, photo annotate e funzioni avanzate';
        }

        return Column(
          children: [
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6D4C41), Color(0xFFE07B4C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              title: Text(
                tileTitle,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                tileSubtitle,
                style: const TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showPaywallSheet(
                context,
                trigger: PaywallTrigger.settingsManual,
              ),
            ),
            // Toggle dev: visibile SOLO in build debug (kDebugMode) +
            // su piattaforme con monetizzazione attiva (iOS) + se
            // l'utente è Pro. In release non deve mai apparire — un
            // utente che ha pagato non deve vedere un bottone per
            // bloccarsi Pro.
            if (kDebugMode && canMonetize && isPro)
              Padding(
                padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => ProGateService().setUnlocked(false),
                    icon: const Icon(Icons.lock_outline, size: 16),
                    label: const Text('Dev: blocca Pro per test paywall'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildThemeTile() {
    IconData icon;
    String subtitle;

    switch (_themeService.themeMode) {
      case ThemeMode.system:
        icon = Icons.brightness_auto;
        subtitle = context.l10n.themeAutomatic;
        break;
      case ThemeMode.light:
        icon = Icons.light_mode;
        subtitle = context.l10n.themeLight;
        break;
      case ThemeMode.dark:
        icon = Icons.dark_mode;
        subtitle = context.l10n.themeDark;
        break;
    }

    return ListTile(
      leading: Icon(icon),
      title: Text(context.l10n.themeLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      trailing: const Icon(Icons.chevron_right),
      onTap: _showThemeDialog,
    );
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.selectTheme),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildThemeOption(
              icon: Icons.brightness_auto,
              label: context.l10n.themeAutomatic,
              subtitle: context.l10n.themeAutomaticSubtitle,
              mode: ThemeMode.system,
            ),
            _buildThemeOption(
              icon: Icons.light_mode,
              label: context.l10n.themeLight,
              subtitle: context.l10n.themeLightSubtitle,
              mode: ThemeMode.light,
            ),
            _buildThemeOption(
              icon: Icons.dark_mode,
              label: context.l10n.themeDark,
              subtitle: context.l10n.themeDarkSubtitle,
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
        title: Text(context.l10n.signOutTitle),
        content: Text(context.l10n.signOutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.signOutTitle),
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
          SnackBar(content: Text(context.l10n.cannotOpenLink)),
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

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri.parse('mailto:support@trailshare.app?subject=TrailShare%20Support');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.cannotOpenEmail)),
        );
      }
    }
  }

  Future<void> _openAppStore(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.appComingSoon)),
    );
  }

  void _showChangelog(BuildContext context) {
    // Changelog inline mantenibile: aggiungi qui le entry per ogni
    // release. La versione corrente arriva in alto, in fondo le
    // più vecchie. Aggiornato in coordinazione con pubspec.yaml
    // version e ROADMAP.md.
    const releases = <_ReleaseEntry>[
      _ReleaseEntry(
        version: '2.2.1',
        title: 'POI OSM, Trail Conditions AI, AR Photo v2',
        bullets: [
          'AR Photo Mode v2: foto annotate con cime + rifugi + sorgenti',
          '20.4k POI OSM bundlati (rifugi, bivacchi, fontane, panorami)',
          'Trail Conditions AI: riassunto delle segnalazioni community (Pro)',
          'Mappe inline e fullscreen mostrano marker POI con dettaglio',
          'Pianificatore percorsi ridisegnato (sheet drag-to-collapse)',
          'Fix overflow card admin / trail detail',
          '148 test unit aggiunti, 0 lint warning',
        ],
      ),
      _ReleaseEntry(
        version: '2.2.0',
        title: 'B2B Groups L1',
        bullets: [
          'Logo personalizzato e badge ✓ verificato per gruppi Business',
          'Tracce condivise nei gruppi (tab Percorsi)',
          'Pagina "Personalizza gruppo" per admin',
          'Admin panel: marca gruppi come Business',
        ],
      ),
      _ReleaseEntry(
        version: '2.1.x',
        title: 'Mountain Recognition + Mappe Pro',
        bullets: [
          'Mountain Finder AR live (37k+ cime italiane)',
          'Photo Mode Pro (foto annotate)',
          'Mappe Pro: Topo, Hybrid Satellite, Inverno (MapTiler)',
          'Paywall foundation con StoreKit 2 e validazione receipt',
          'Cross-device Pro sync via Firestore',
        ],
      ),
      _ReleaseEntry(
        version: '1.9.0',
        title: 'Engagement',
        bullets: [
          'Sfide settimanali personalizzate',
          'Classifiche regionali',
          'Commenti sulle tracce community',
          'Report mensile "Il mio mese"',
          'Compass-up navigation in registrazione',
        ],
      ),
      _ReleaseEntry(
        version: '1.8.x',
        title: 'Completezza funzionale',
        bullets: [
          'POI / Highlights lungo il percorso',
          'Notifica vocale geolocata ai POI',
          'Multi-day tours',
          'Sharing link pubblico web',
          'Esportazione TCX / FIT / KML',
          'Dark mode app-wide',
          'Onboarding interattivo',
        ],
      ),
      _ReleaseEntry(
        version: '1.7.0',
        title: 'Sicurezza',
        bullets: [
          'Lifeline: contatti emergenza + invio link live',
          'Pulsante SOS integrato con 112',
          'Auto-alert inattività',
          'Re-routing automatico',
          'Modalità battery saver',
        ],
      ),
      _ReleaseEntry(
        version: '1.0.0',
        title: 'Prima release',
        bullets: [
          'Registrazione tracce GPS',
          'Tracking in background',
          'LiveTrack - condividi posizione',
          'Sistema social (follow, cheers)',
          'Classifica settimanale',
          'Wishlist percorsi',
          'Dashboard statistiche',
          'Import/Export GPX',
        ],
      ),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novità'),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < releases.length; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  _buildReleaseEntry(ctx, releases[i], isCurrent: i == 0),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseEntry(
    BuildContext context,
    _ReleaseEntry entry, {
    required bool isCurrent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'v${entry.version}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isCurrent ? Colors.white : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final b in entry.bullets)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text('• $b', style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final result = await showDeleteAccountDialog(context);

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.accountDeleted),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}

/// Entry del changelog interno mostrato dal settings dialog "Novità".
/// Aggiungi nuove versioni in cima alla lista in [_showChangelog].
class _ReleaseEntry {
  final String version;
  final String title;
  final List<String> bullets;
  const _ReleaseEntry({
    required this.version,
    required this.title,
    required this.bullets,
  });
}
