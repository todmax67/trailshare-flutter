import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/constants/app_colors.dart';
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
        title: Text(context.l10n.maxHeartRate),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.maxHRDescription,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
            Text(context.l10n.orLabel, style: const TextStyle(color: AppColors.textMuted)),
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
          ],

          // Sezione Aspetto
          _buildSectionHeader(context.l10n.appearanceSection),
          _buildThemeTile(),
          const Divider(height: 32),

          // Sezione Salute
          _buildSectionHeader(context.l10n.healthConnectionSection),
          SwitchListTile(
            secondary: Icon(
              Icons.favorite_outline,
              color: _healthSyncEnabled ? AppColors.danger : AppColors.textSecondary,
            ),
            title: Text(context.l10n.syncWithHealth),
            subtitle: Text(
              Platform.isIOS
                  ? context.l10n.saveToAppleHealth
                  : context.l10n.saveToHealthConnect,
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
                if (!granted && mounted) {
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

          // Sezione Admin (solo per admin/sviluppatori)
          // TODO: In produzione, controllare se l'utente è admin
          if (_isAdmin(user)) ...[
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

  Future<void> _openHelpCenter(BuildContext context) async {
    final uri = Uri.parse('https://trailshare.app/help');
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.changelogTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.changelogFirstRelease, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('• ${context.l10n.changelogGpsTracking}'),
              Text('• ${context.l10n.changelogBackground}'),
              Text('• ${context.l10n.changelogLiveTrack}'),
              Text('• ${context.l10n.changelogSocial}'),
              Text('• ${context.l10n.changelogLeaderboard}'),
              Text('• ${context.l10n.changelogWishlist}'),
              Text('• ${context.l10n.changelogDashboard}'),
              Text('• ${context.l10n.changelogGpx}'),
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
        SnackBar(
          content: Text(context.l10n.accountDeleted),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}