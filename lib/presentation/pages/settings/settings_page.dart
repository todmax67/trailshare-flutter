import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/hud_prefs_service.dart';
import '../training/training_hr_page.dart';
import '../../../core/services/strava_service.dart';
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
import '../business/business_create_page.dart';
import '../business/business_profile_page.dart';
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

/// ID numerico dell'app su App Store Connect (necessario per
/// `in_app_review.openStoreListing` come fallback su iOS quando il
/// prompt nativo non è disponibile o è stato throttled da Apple).
/// TODO: aggiornare con l'ID reale quando l'app sarà pubblicata su App
/// Store (oggi è solo TestFlight beta).
const String _kAppStoreId = '0000000000';

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
            SizedBox(height: 16),
            TextField(
              controller: hrController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.maxHRLabel,
                hintText: context.l10n.maxHRHint,
                border: const OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            Text(context.l10n.orLabel, style: TextStyle(color: context.textMuted)),
            SizedBox(height: 12),
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
            Divider(height: 32),
          ],

          // Sezione Aspetto
          _buildSectionHeader(context.l10n.appearanceSection),
          _buildThemeTile(),
          const Divider(height: 32),

          // ─── Sezione TrailShare Pro (mockup paywall) ─────────────────
          _buildSectionHeader('TrailShare Pro'),
          _buildProTile(),
          // 6.5 — Entry alla pagina Allenamento HR personalizzato
          _buildListTile(
            icon: Icons.fitness_center,
            title: context.l10n.settingsHrTraining,
            subtitle: 'Zone cardio + suggerimenti settimanali (Pro)',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TrainingHrPage(),
                ),
              );
            },
          ),
          Divider(height: 32),

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
              leading: Icon(Icons.monitor_heart, color: AppColors.danger),
              title: Text(context.l10n.maxHeartRate),
              subtitle: Text(
                _maxHR > 0 ? '$_maxHR BPM' : context.l10n.setForCardioZones,
              ),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () => _showMaxHRDialog(),
            ),
            ListTile(
              leading: Icon(Icons.dashboard, color: AppColors.primary),
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

          // Sezione Strava
          _buildSectionHeader('Strava'),
          _buildStravaSection(),
          const Divider(height: 32),

          // Sezione Registrazione (1.D4 — auto-hide HUD)
          _buildSectionHeader('Registrazione'),
          _buildHudAutoHideSection(),
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

          // Sezione Privacy
          _buildSectionHeader('Privacy'),
          _buildSocialFeaturingToggle(),
          Divider(height: 32),

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
          Divider(height: 32),

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
            subtitle: 'info@trailshare.app',
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
          Divider(height: 32),

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
            Divider(height: 32),
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
            _buildListTile(
              icon: Icons.add_business,
              title: 'Crea Spazio Pro',
              subtitle: context.l10n.settingsAddBusinessProfileSub,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BusinessCreatePage()),
                );
              },
            ),
            _buildListTile(
              icon: Icons.business_center_outlined,
              title: 'Apri Spazio Pro (debug)',
              subtitle: context.l10n.settingsEnterBusinessId,
              onTap: () => _openBusinessByIdDialog(),
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
            Divider(height: 32),
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

  /// Toggle per consenso uso tracce dell'utente da parte del manager
  /// social TrailShare (account ufficiali IG/FB/TikTok). Default OFF:
  /// senza consenso esplicito, le tracce non vengono usate per post
  /// promozionali anche se sono `isPublic=true` (la pubblicazione in
  /// community è una cosa, l'uso a fini marketing un'altra).
  Widget _buildSocialFeaturingToggle() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final docStream = FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(uid)
        .snapshots();
    return StreamBuilder<DocumentSnapshot>(
      stream: docStream,
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final enabled = data?['socialFeaturingOptIn'] == true;
        return SwitchListTile(
          secondary: const Icon(Icons.share_outlined,
              color: AppColors.primary),
          title: const Text('Uso tracce sui canali social'),
          subtitle: const Text(
            'Permetti a TrailShare di pubblicare le tue tracce sugli '
            'account ufficiali (Instagram, Facebook). Le tracce restano '
            'tue, sempre attribuite con username.',
          ),
          value: enabled,
          onChanged: (v) async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await FirebaseFirestore.instance
                  .collection('user_profiles')
                  .doc(uid)
                  .set({'socialFeaturingOptIn': v},
                      SetOptions(merge: true));
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text(context.l10n.genericErrorWith(e.toString()))),
              );
            }
          },
        );
      },
    );
  }

  Future<void> _openBusinessByIdDialog() async {
    final ctrl = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apri Spazio Pro'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ID business (Firestore doc id)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Apri'),
          ),
        ],
      ),
    );
    if (id == null || id.isEmpty || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessProfilePage(businessId: id),
      ),
    );
  }

  Widget _buildStravaSection() {
    final stravaService = StravaService();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final l10n = context.l10n;

    if (uid == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(l10n.stravaSignInRequired),
      );
    }
    final docStream = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('integrations').doc('strava')
        .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: docStream,
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final connected = data != null && data['accessToken'] != null;
        final autoUpload = data?['autoUploadEnabled'] == true;
        final athleteName = [data?['athleteFirstname'], data?['athleteLastname']]
            .whereType<String>().where((s) => s.isNotEmpty).join(' ');

        if (!connected) {
          return ListTile(
            leading: const Icon(Icons.directions_run, color: Color(0xFFFC4C02)),
            title: Text(l10n.stravaConnect),
            subtitle: Text(l10n.stravaConnectSubtitle),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final ok = await stravaService.connect();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.stravaCannotOpen)),
                );
              }
            },
          );
        }

        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.directions_run, color: Color(0xFFFC4C02)),
              title: Text(l10n.stravaConnected),
              subtitle: Text(athleteName.isNotEmpty ? athleteName : l10n.stravaAuthorizedAccount),
              trailing: TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.stravaDisconnectQuestion),
                      content: Text(l10n.stravaDisconnectBody),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.stravaDisconnect)),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final ok = await stravaService.disconnect();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? l10n.stravaDisconnectedOk : l10n.stravaDisconnectError),
                      ));
                    }
                  }
                },
                child: Text(l10n.stravaDisconnect),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_upload_outlined),
              title: Text(l10n.stravaAutoUpload),
              subtitle: Text(l10n.stravaAutoUploadSubtitle),
              value: autoUpload,
              onChanged: (v) => stravaService.setAutoUploadEnabled(v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_download_outlined),
              title: Text(l10n.stravaImport),
              subtitle: Text(l10n.stravaImportSubtitle),
              value: data['importFromStravaEnabled'] == true,
              onChanged: (v) => stravaService.setImportFromStravaEnabled(v),
            ),
            // Force-sync manuale: utile quando il webhook Strava è in delay
            // o non scatta. Pulla ultime 10 attività e importa le nuove.
            if (data['importFromStravaEnabled'] == true)
              ListTile(
                leading: const Icon(Icons.sync, color: Color(0xFFFC4C02)),
                title: Text(l10n.stravaSyncNow),
                subtitle: Text(l10n.stravaSyncNowSubtitle),
                onTap: () => _runStravaImportNow(context),
              ),
          ],
        );
      },
    );
  }

  /// Chiama la Cloud Function `stravaImportRecent` per pullare le ultime
  /// attività Strava e importarle. Bypass del webhook quando in delay.
  Future<void> _runStravaImportNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(context.l10n.stravaSyncing)),
    );
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('stravaImportRecent');
      final res = await fn.call({'limit': 10});
      final data = Map<String, dynamic>.from(res.data as Map);
      final imported = (data['imported'] as List?)?.length ?? 0;
      final skipped = (data['skipped'] as List?)?.length ?? 0;
      final errors = (data['errors'] as List?)?.length ?? 0;
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('${context.l10n.stravaSyncDone} '
            '✓$imported · ⏭$skipped · ⚠$errors'),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(context.l10n.genericErrorWith(e.toString())),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  /// 1.D4 — Sezione "Registrazione": toggle auto-hide HUD + scelta
  /// secondi (5/10/20). Listener su HudPrefsService così la UI si
  /// aggiorna immediatamente al cambio.
  Widget _buildHudAutoHideSection() {
    return AnimatedBuilder(
      animation: HudPrefsService(),
      builder: (context, _) {
        final prefs = HudPrefsService();
        return Column(
          children: [
            SwitchListTile(
              secondary: Icon(
                Icons.visibility_off_outlined,
                color: prefs.enabled
                    ? AppColors.primary
                    : context.textSecondary,
              ),
              title: const Text('Nascondi HUD automaticamente'),
              subtitle: const Text(
                'Durante la registrazione le statistiche scompaiono '
                'dopo un periodo di inattività, lasciando più mappa visibile. '
                'Tap su mappa o sul chip per rimostrarle.',
              ),
              value: prefs.enabled,
              activeThumbColor: AppColors.primary,
              onChanged: (v) => prefs.setEnabled(v),
            ),
            if (prefs.enabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        color: context.textSecondary, size: 20),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Tempo prima del nascondimento',
                        style: TextStyle(color: context.textPrimary),
                      ),
                    ),
                    SegmentedButton<int>(
                      segments: HudPrefsService.allowedSeconds
                          .map((s) => ButtonSegment<int>(
                                value: s,
                                label: Text('${s}s'),
                              ))
                          .toList(),
                      selected: {prefs.seconds},
                      onSelectionChanged: (set) =>
                          prefs.setSeconds(set.first),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
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
      title: Text(context.l10n.themeLabel, style: TextStyle(fontWeight: FontWeight.w500)),
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
    // Su Android 11+ canLaunchUrl(mailto:) ritorna false anche con
    // client mail installati, a meno che AndroidManifest non dichiari
    // la query SENDTO (vedi android/app/src/main/AndroidManifest.xml).
    // Per maggiore robustezza tentiamo launchUrl direttamente in
    // externalApplication mode e gestiamo l'errore.
    final uri = Uri(
      scheme: 'mailto',
      path: 'info@trailshare.app',
      query: 'subject=TrailShare Support',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.cannotOpenEmail)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.cannotOpenEmail)),
        );
      }
    }
  }

  /// Apre il prompt nativo "Valuta app". Su iOS usa
  /// `SKStoreReviewController` (StoreKit), su Android la In-App Review API
  /// di Google Play Services — entrambi mostrano la review sheet
  /// IN-APP, l'utente non lascia TrailShare.
  ///
  /// Se il device non supporta il prompt nativo (es. Play Services
  /// assenti, iOS < 10.3, oppure il prompt è stato già mostrato troppe
  /// volte e Apple lo throttla), fallback su [openStoreListing] che
  /// apre la pagina dello store nel browser/app store nativa.
  Future<void> _openAppStore(BuildContext context) async {
    final InAppReview inAppReview = InAppReview.instance;
    try {
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
        return;
      }
    } catch (e) {
      debugPrint('[Settings] requestReview failed: $e');
    }
    // Fallback: apre la pagina store. appStoreId è l'ID numerico
    // dell'app su App Store Connect (lo prendiamo da una const così
    // resta facile da aggiornare quando l'app sarà pubblicata).
    try {
      await inAppReview.openStoreListing(
        appStoreId: _kAppStoreId,
        microsoftStoreId: null,
      );
    } catch (e) {
      debugPrint('[Settings] openStoreListing failed: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.appComingSoon)),
      );
    }
  }

  void _showChangelog(BuildContext context) {
    // Changelog inline mantenibile: aggiungi qui le entry per ogni
    // release. La versione corrente arriva in alto, in fondo le
    // più vecchie. Aggiornato in coordinazione con pubspec.yaml
    // version e ROADMAP.md.
    const releases = <_ReleaseEntry>[
      _ReleaseEntry(
        version: '2.6.5',
        title: 'Rivivi le tue tracce in 3D 🏔️',
        bullets: [
          'Nuova funzione Pro "Vedi in 3D": guarda il tuo percorso sorvolare il terreno in 3D con un fly-through animato, stile Relive',
          'Camera cinematografica che segue la traccia sul rilievo reale, con distanza e quota in tempo reale e controllo della velocità',
          'Funziona su tracce tue, della community e sui tour: nei cammini di più giorni mostra il nome di ogni tappa, nelle raccolte fa un "salto volante" morbido da una traccia all\'altra',
          'Gli Spazi Pro (rifugi, noleggi) lungo il percorso compaiono sulla mappa 3D e vengono segnalati quando il volo li raggiunge',
          'Fix registrazione: la pausa automatica dopo qualche minuto di sosta ora riprende da sola al movimento (prima restava bloccata)',
          'Quote altimetriche corrette via DEM anche più precise',
        ],
      ),
      _ReleaseEntry(
        version: '2.6.3',
        title: 'Quote altimetriche più precise (correzione DEM)',
        bullets: [
          'Le quote GPS dello smartphone hanno spesso errori sistematici di 30-100 metri rispetto alla realtà. Ora al salvataggio di una traccia le quote vengono corrette automaticamente usando un modello digitale del terreno (AWS Open Terrain), ottenendo accuratezza paragonabile a Strava e Komoot',
          'Grafici di altitudine più puliti, dislivello totale più preciso, difficoltà ricalcolata coerentemente',
          'Per le tracce vecchie: dal menu "⋮" della scheda traccia trovi "Correggi quote dal DEM" per aggiornarle a posteriori',
          'La correzione è gratuita (dati pubblici AWS Open Terrain Tiles)',
        ],
      ),
      _ReleaseEntry(
        version: '2.6.2',
        title: 'Difficoltà più precisa + override manuale',
        bullets: [
          'Algoritmo difficoltà ricalibrato: ora tiene conto del dislivello totale assoluto, non solo del rapporto m/km. Fix per escursioni con tanti km e dislivello importante (es. 1200m+ in 25km) che venivano classificate troppo facili',
          'Factor ebike ed e-MTB rivisti al rialzo: l\'assistenza riduce lo sforzo ma non lo azzera',
          'Override manuale: nella modifica di una traccia puoi impostare la difficoltà T1-T5 a mano. Il badge mostra una piccola icona ✏️ quando è stata impostata manualmente',
          'I filtri community usano la difficoltà manuale se presente, automatica altrimenti',
        ],
      ),
      _ReleaseEntry(
        version: '2.6.1',
        title: 'TrailShare Pro disponibile anche su Android',
        bullets: [
          'TrailShare Pro ora attivabile anche su Android: €3,69/mese o €23,99/anno con 14 giorni di prova gratuita sul piano annuale',
          'Grandfather policy: tutti gli utenti registrati prima del 26 maggio 2026 hanno TrailShare Pro gratis a vita su qualsiasi piattaforma (iOS e Android) come ringraziamento per averci sostenuto durante il periodo beta',
          'Allineamento esperienza Pro fra iOS e Android: stesse funzioni, stesso flusso di acquisto, gestione abbonamento dallo store di acquisto',
        ],
      ),
      _ReleaseEntry(
        version: '2.6.0',
        title: 'Komoot foundations: highlights, difficoltà T1-T5, surface profile',
        bullets: [
          'Highlights: collega un POI a uno Spazio Pro vicino, diventa cliccabile',
          'Difficoltà T1-T5 calcolata automaticamente da distanza, dislivello e attività',
          'Filtro community per difficoltà esatta (T1, T2, T3, T4, T5)',
          'Surface profile: la mappa del trail OSM colora il percorso per tipo di terreno (asfalto, sterrato, sentiero, roccia, ferrata)',
          'Toggle "Pendenza ↔ Terreno" sulla mappa fullscreen + legenda',
          'ETA terrain-aware: stima durata che tiene conto del fondo del sentiero',
          'Tour: distinzione "Cammino consecutivo" vs "Collezione tematica" con filtro dedicato',
          'Tour pubblici: grafico altimetrico cumulativo visibile anche sulla community',
          'Descrizioni lunghe ora si compattano a 3 righe con "Leggi di più" (track community, business, tour, ecc.)',
          'Carousel "Consigli per te" collassabile, si auto-collassa quando cambi tab',
          'Newsletter prodotto: infrastruttura email service-update + admin panel',
          'Tracciato pianificato: difficoltà calcolata anche per i percorsi da pianificatore',
          'Fix vari deliverability email + branding pulito (no S.r.l. nelle email automatiche)',
          'Sito web TrailShare ridisegnato (homepage, /pro, /business)',
        ],
      ),
      _ReleaseEntry(
        version: '2.5.1',
        title: 'Tour multi-giorno + polish track detail',
        bullets: [
          'Scheda Tour: gallery foto, sezioni descrizione, periodo migliore, difficoltà, rifugio per tappa',
          'Tour multi-giorno: hero design "poster" + descrizione espandibile',
          'Tour: tipo "Cammino" vs "Collezione" con grafico altimetria solo per i cammini',
          'Community Tour: list rinnovata con cover hero + ricerca + filtro difficoltà',
          'Track detail: fix titolo hero non più a cavallo tra mappa e sfondo (con titoli su 2 righe)',
        ],
      ),
      _ReleaseEntry(
        version: '2.5.0',
        title: 'Wearable e fitness integrato',
        bullets: [
          'HealthKit (iOS) + Health Connect (Android): sync attività, frequenza cardiaca, calorie, passi',
          'Strava bidirezionale: upload automatico a fine sessione + import attività recenti',
          'ConnectIQ Garmin: app dedicata per visualizzare metriche TrailShare sull\'orologio',
          'Lifeline + LiveTrack consolidati: contatti emergenza, posizione live, SOS manuale',
          'Outreach business automatizzato (Cloud Function + admin panel)',
        ],
      ),
      _ReleaseEntry(
        version: '2.4.0',
        title: 'Epic 3 + 4 chiuse, Community VIP, dark map, training HR',
        bullets: [
          'Auto-hide HUD configurabile durante registrazione',
          'Pianificatore: snap automatico 5km + waypoint problematico evidenziato',
          'Mentions @username nei commenti + notifica FCM',
          'Heatmap trail popolari (toggle Discover, geohash p4 weekly)',
          'Sfide gruppo: auto-progress su track save + FCM al vincitore',
          'Spazi Pro: Community VIP linkata (gruppo dedicato clienti)',
          'Navigazione guidata: ETA dinamico real-time + orario arrivo',
          'Discover: filtro per regione amministrativa (20 bbox)',
          'Ricerca testuale full-text accent-insensitive estesa',
          'Track detail: confronto con Personal Records (PR)',
          'Mappa "Notte Pro" MapTiler streets-v2-dark nativa',
          'Discovery prompt "Scopri Pro" per utenti free attivi',
          'Training HR personalizzato (4 settimane + suggerimento next session)',
          'Benefit reminder mensile FCM per utenti Pro',
          'Fix critico Firestore rules (Path.matches inesistente)',
          'Fix cache Pro post-purchase + "Valuta app" prompt nativo',
          '"Contattaci" ora funziona (mailto su Android 11+)',
        ],
      ),
      _ReleaseEntry(
        version: '2.3.0',
        title: 'POI OSM, Trail Conditions AI, AR Photo v2',
        bullets: [
          'AR Photo Mode v2: foto annotate con cime + rifugi + sorgenti',
          '20.4k POI OSM bundlati (rifugi, bivacchi, fontane, panorami)',
          'Trail Conditions AI: riassunto delle segnalazioni community (Pro)',
          'Mappe inline e fullscreen mostrano marker POI con dettaglio',
          'Pianificatore percorsi ridisegnato (sheet drag-to-collapse)',
          'Fix overflow card admin / trail detail / dark theme chat',
          '159 test unit aggiunti, 0 lint warning',
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
        title: Text(context.l10n.settingsNews),
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
