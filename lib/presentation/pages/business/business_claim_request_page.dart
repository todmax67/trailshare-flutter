import 'package:flutter/material.dart';

import '../../../data/models/business.dart';
import '../../widgets/business_claim_request_form.dart';

/// Epic 7.H5 — Pagina mobile per rivendicare uno Spazio Pro
/// pre-popolato dal team TrailShare (tier=unclaimed). Vedi
/// [BusinessClaimRequestForm] per la logica condivisa col web.
class BusinessClaimRequestPage extends StatelessWidget {
  final Business business;
  const BusinessClaimRequestPage({super.key, required this.business});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rivendica scheda')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: BusinessClaimRequestForm(business: business),
        ),
      ),
    );
  }
}
