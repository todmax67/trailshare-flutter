import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Pagina Privacy Policy
/// 
/// Mostra la privacy policy dell'app, obbligatoria per App Store e Play Store.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  // URL della privacy policy online (opzionale)
  static const String _privacyPolicyUrl = 'https://trailshare.app/privacy';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.privacyPolicy),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  const Icon(Icons.privacy_tip_outlined, size: 48, color: AppColors.primary),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.privacyPolicy,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.privacyLastUpdated,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Sezioni
            _buildSection(
              context.l10n.privacyIntroTitle,
              context.l10n.privacyIntroContent,
            ),

            _buildSection(
              context.l10n.privacyDataCollectedTitle,
              context.l10n.privacyDataCollectedContent,
            ),

            _buildSection(
              context.l10n.privacyDataUsageTitle,
              context.l10n.privacyDataUsageContent,
            ),

            _buildSection(
              context.l10n.privacyDataSharingTitle,
              context.l10n.privacyDataSharingContent,
            ),

            _buildSection(
              context.l10n.privacyRetentionTitle,
              context.l10n.privacyRetentionContent,
            ),

            _buildSection(
              context.l10n.privacyRightsTitle,
              context.l10n.privacyRightsContent,
            ),

            _buildSection(
              context.l10n.privacySecurityTitle,
              context.l10n.privacySecurityContent,
            ),

            _buildSection(
              context.l10n.privacyMinorsTitle,
              context.l10n.privacyMinorsContent,
            ),

            _buildSection(
              context.l10n.privacyChangesTitle,
              context.l10n.privacyChangesContent,
            ),

            _buildSection(
              context.l10n.privacyContactTitle,
              context.l10n.privacyContactContent,
            ),

            const SizedBox(height: 24),

            // Link versione web
            Center(
              child: TextButton.icon(
                onPressed: () => _openPrivacyPolicyWeb(context),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(context.l10n.viewWebVersion),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPrivacyPolicyWeb(BuildContext context) async {
    final uri = Uri.parse(_privacyPolicyUrl);
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
}
