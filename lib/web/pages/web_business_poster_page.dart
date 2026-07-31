import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/business.dart';
import '../../data/repositories/business_repository.dart';
import '../../presentation/pages/business/business_qr_card_page.dart';

/// `/b/{slug}/locandina` — la cartolina da stampare per il banco del rifugio.
///
/// Pubblica, senza login: è il regalo che apre la conversazione, non la
/// ricompensa per averla chiusa. L'email di outreach chiede al gestore di
/// rivendicare la scheda — cioè gli chiede di fare qualcosa per noi. Questa
/// pagina gli dà prima qualcosa: un cartoncino col QR che porta escursionisti
/// al suo rifugio, che può stampare anche se non rivendica niente.
///
/// Non è allegata all'email di proposito. Un allegato su posta a freddo alza
/// il punteggio spam, e su un dominio giovane il costo lo pagano anche le
/// email di verifica account. Un link invece si misura: sappiamo chi ha
/// scaricato la locandina anche se non ha ancora rivendicato, ed è un segnale
/// di interesse che altrimenti non avremmo.
class WebBusinessPosterPage extends StatefulWidget {
  final String slug;
  const WebBusinessPosterPage({super.key, required this.slug});

  @override
  State<WebBusinessPosterPage> createState() => _WebBusinessPosterPageState();
}

class _WebBusinessPosterPageState extends State<WebBusinessPosterPage> {
  final _repo = BusinessRepository();
  Business? _business;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await _repo.getBusinessBySlug(widget.slug);
      if (!mounted) return;
      setState(() {
        _business = b;
        _loading = false;
        _error = b == null ? 'Scheda non trovata' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Errore di caricamento';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final business = _business;
    if (business == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 56, color: AppColors.danger.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(_error ?? 'Scheda non trovata'),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/'),
                  child: const Text('Vai a trailshare.app'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // La card e il download li fa già `BusinessQrCardPage`, che su web
    // salva un PNG invece di aprire il foglio di condivisione. Qui sopra ci
    // mettiamo solo il contesto per chi arriva dall'email e non sa cos'è.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              color: AppColors.primary.withValues(alpha: 0.10),
              child: Column(
                children: [
                  Text(
                    'La locandina di ${business.name}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Stampala e appoggiala al banco. Chi la inquadra trova '
                    'la tua scheda, i sentieri che arrivano fin qui e i '
                    'percorsi che consigli.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),
            // Larghezza massima: la card e' pensata per un telefono, e su
            // desktop senza vincolo si allarga fino a spingere il QR sotto
            // la piega — proprio la cosa per cui si e' arrivati qui.
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: BusinessQrCardPage(
                    business: business,
                    showAppBar: false,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
