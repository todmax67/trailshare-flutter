import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Pagina FAQ
class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAQ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.faqHowCanWeHelp,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.faqFindAnswers,
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Categorie FAQ
          _buildCategory(
            context,
            title: context.l10n.faqCategoryGeneral,
            faqs: _getGeneralFaqs(context),
          ),
          _buildCategory(
            context,
            title: context.l10n.faqCategoryTracking,
            faqs: _getTrackingFaqs(context),
          ),
          _buildCategory(
            context,
            title: context.l10n.faqCategorySocial,
            faqs: _getSocialFaqs(context),
          ),
          _buildCategory(
            context,
            title: context.l10n.faqCategoryGamification,
            faqs: _getGamificationFaqs(context),
          ),
          _buildCategory(
            context,
            title: context.l10n.faqCategoryTechnical,
            faqs: _getTechnicalFaqs(context),
          ),

          const SizedBox(height: 24),

          // Contatto supporto
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  context.l10n.faqNoAnswer,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.faqContactPrompt,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    // TODO: Aprire email
                  },
                  icon: const Icon(Icons.email_outlined),
                  label: Text(context.l10n.faqContactSupport),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCategory(
    BuildContext context, {
    required String title,
    required List<FaqItem> faqs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...faqs.map((faq) => _FaqTile(faq: faq)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  final FaqItem faq;

  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          faq.question,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        children: [
          Text(
            faq.answer,
            style: TextStyle(
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class FaqItem {
  final String question;
  final String answer;

  const FaqItem({
    required this.question,
    required this.answer,
  });
}

// ============================================
// FAQ DATA (localized)
// ============================================

List<FaqItem> _getGeneralFaqs(BuildContext context) => [
  FaqItem(
    question: context.l10n.faqGeneralQ1,
    answer: context.l10n.faqGeneralA1,
  ),
  FaqItem(
    question: context.l10n.faqGeneralQ2,
    answer: context.l10n.faqGeneralA2,
  ),
  FaqItem(
    question: context.l10n.faqGeneralQ3,
    answer: context.l10n.faqGeneralA3,
  ),
  FaqItem(
    question: context.l10n.faqGeneralQ4,
    answer: context.l10n.faqGeneralA4,
  ),
];

List<FaqItem> _getTrackingFaqs(BuildContext context) => [
  FaqItem(
    question: context.l10n.faqTrackingQ1,
    answer: context.l10n.faqTrackingA1,
  ),
  FaqItem(
    question: context.l10n.faqTrackingQ2,
    answer: context.l10n.faqTrackingA2,
  ),
  FaqItem(
    question: context.l10n.faqTrackingQ3,
    answer: context.l10n.faqTrackingA3,
  ),
  FaqItem(
    question: context.l10n.faqTrackingQ4,
    answer: context.l10n.faqTrackingA4,
  ),
  FaqItem(
    question: context.l10n.faqTrackingQ5,
    answer: context.l10n.faqTrackingA5,
  ),
  FaqItem(
    question: context.l10n.faqTrackingQ6,
    answer: context.l10n.faqTrackingA6,
  ),
  FaqItem(
    question: context.l10n.faqTrackingQ7,
    answer: context.l10n.faqTrackingA7,
  ),
];

List<FaqItem> _getSocialFaqs(BuildContext context) => [
  FaqItem(
    question: context.l10n.faqSocialQ1,
    answer: context.l10n.faqSocialA1,
  ),
  FaqItem(
    question: context.l10n.faqSocialQ2,
    answer: context.l10n.faqSocialA2,
  ),
  FaqItem(
    question: context.l10n.faqSocialQ3,
    answer: context.l10n.faqSocialA3,
  ),
  FaqItem(
    question: context.l10n.faqSocialQ4,
    answer: context.l10n.faqSocialA4,
  ),
  FaqItem(
    question: context.l10n.faqSocialQ5,
    answer: context.l10n.faqSocialA5,
  ),
];

List<FaqItem> _getGamificationFaqs(BuildContext context) => [
  FaqItem(
    question: context.l10n.faqGamificationQ1,
    answer: context.l10n.faqGamificationA1,
  ),
  FaqItem(
    question: context.l10n.faqGamificationQ2,
    answer: context.l10n.faqGamificationA2,
  ),
  FaqItem(
    question: context.l10n.faqGamificationQ3,
    answer: context.l10n.faqGamificationA3,
  ),
  FaqItem(
    question: context.l10n.faqGamificationQ4,
    answer: context.l10n.faqGamificationA4,
  ),
  FaqItem(
    question: context.l10n.faqGamificationQ5,
    answer: context.l10n.faqGamificationA5,
  ),
];

List<FaqItem> _getTechnicalFaqs(BuildContext context) => [
  FaqItem(
    question: context.l10n.faqTechnicalQ1,
    answer: context.l10n.faqTechnicalA1,
  ),
  FaqItem(
    question: context.l10n.faqTechnicalQ2,
    answer: context.l10n.faqTechnicalA2,
  ),
  FaqItem(
    question: context.l10n.faqTechnicalQ3,
    answer: context.l10n.faqTechnicalA3,
  ),
  FaqItem(
    question: context.l10n.faqTechnicalQ4,
    answer: context.l10n.faqTechnicalA4,
  ),
  FaqItem(
    question: context.l10n.faqTechnicalQ5,
    answer: context.l10n.faqTechnicalA5,
  ),
  FaqItem(
    question: context.l10n.faqTechnicalQ6,
    answer: context.l10n.faqTechnicalA6,
  ),
];
