import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/business.dart';
import '../../presentation/widgets/business_claim_request_form.dart';

/// Epic 7.H5 — Pagina web per rivendicare uno Spazio Pro pre-popolato
/// dal team TrailShare. Layout desktop-friendly con max-width + card.
/// Riusa [BusinessClaimRequestForm] (condiviso col mobile).
class WebClaimRequestPage extends StatelessWidget {
  final Business business;
  const WebClaimRequestPage({super.key, required this.business});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Rivendica: ${business.name}'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: BusinessClaimRequestForm(business: business),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
