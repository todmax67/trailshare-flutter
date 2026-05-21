import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/business.dart';
import '../../data/repositories/business_repository.dart';
import '../utils/outreach_pdf_generator.dart';
import '../utils/pdf_downloader.dart';

/// Epic 7.H10 — Outreach kit PDF (Fase 3a: pagina printable, admin
/// fa Cmd+P / Ctrl+P → "Salva come PDF" dal browser).
///
/// Route: `/admin/outreach/{businessId}` — admin only (AuthGate +
/// platform admin check nel pannello chiamante).
///
/// Layout pensato per stampa A4 verticale. Tutto il CSS è gestito
/// via Flutter widgets (Container + Padding + Column) senza media
/// queries print: il browser scala automaticamente per la stampa.
/// L'utente admin apre, sceglie "Stampa → Salva come PDF" e ottiene
/// un documento già impaginato.
///
/// In futuro (Fase 3b) la Cloud Function `generateOutreachPdf`
/// renderizzerà questa stessa pagina headless via Puppeteer →
/// nessun refactor lato UI.
class WebOutreachPdfPage extends StatefulWidget {
  final String businessId;
  const WebOutreachPdfPage({super.key, required this.businessId});

  @override
  State<WebOutreachPdfPage> createState() => _WebOutreachPdfPageState();
}

class _WebOutreachPdfPageState extends State<WebOutreachPdfPage> {
  final _repo = BusinessRepository();
  Business? _business;
  List<Business> _nearby = const [];
  bool _loading = true;
  String? _error;
  String? _nearbyDebugInfo;
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final business = await _repo.getBusiness(widget.businessId);
      if (business == null) {
        setState(() {
          _loading = false;
          _error = 'Scheda non trovata';
        });
        return;
      }
      // Competitor zone: schede entro 10km, escludo se stessa.
      List<Business> nearby = const [];
      String? debug;
      try {
        debugPrint('[Outreach] getNearby lat=${business.location.lat} '
            'lng=${business.location.lng} radius=10km');
        final raw = await _repo.getNearby(
          lat: business.location.lat,
          lng: business.location.lng,
          radiusKm: 10,
        );
        debugPrint('[Outreach] raw=${raw.length} schede dalla query, '
            'nomi: ${raw.map((b) => b.name).take(10).toList()}');
        nearby = raw.where((b) => b.id != business.id).toList();
        debug = 'Query OK · raw=${raw.length}, dopo escludere self=${nearby.length}';
      } catch (e, st) {
        debugPrint('[Outreach] getNearby ERRORE: $e\n$st');
        debug = 'Query FALLITA: $e';
      }
      if (!mounted) return;
      setState(() {
        _business = business;
        _nearby = nearby;
        _nearbyDebugInfo = debug;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _downloadPdf() async {
    final b = _business;
    if (b == null) return;
    setState(() => _generatingPdf = true);
    try {
      final bytes = await OutreachPdfGenerator.generate(
        business: b,
        nearby: _nearby,
      );
      // Download diretto via dart:html (no plugin `printing` su web —
      // richiederebbe setup JS in web/index.html). Su mobile la
      // funzione throw UnsupportedError ma questa pagina è raggiunta
      // solo dalla shell web (`/admin/outreach/{id}` route).
      downloadPdfBytes(bytes, 'TrailShare-${b.slug}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore generazione PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Outreach Kit'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // Bottone "Scarica PDF" che genera PDF nativo via package
          // `pdf` + apre dialog save via `printing`. Niente più Cmd+P
          // del browser (con Flutter CanvasKit produceva PDF mal
          // impaginati e tagliati).
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: FilledButton.icon(
                onPressed: (_loading || _generatingPdf || _business == null)
                    ? null
                    : _downloadPdf,
                icon: _generatingPdf
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.picture_as_pdf, size: 18),
                label: Text(
                    _generatingPdf ? 'Generazione...' : 'Scarica PDF'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Errore: $_error'))
              : SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      // A4 portrait a 96 DPI = 794×1123 px, ma il
                      // browser print applica margini default di ~12mm
                      // per lato → spazio utilizzabile ~700px. Usiamo
                      // 720 con padding 16 = content reale 688, dentro
                      // i margini Chrome/Safari default.
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                        child: _buildPdfContent(_business!),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildPdfContent(Business b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(b),
        const SizedBox(height: 16),
        _buildIntro(b),
        const SizedBox(height: 14),
        _buildFunnelStats(b),
        const SizedBox(height: 14),
        _buildMap(b),
        const SizedBox(height: 14),
        _buildCompetitorSection(b, _nearby),
        if (kDebugMode && _nearbyDebugInfo != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.yellow.shade50,
              border: Border.all(color: Colors.amber),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'DEBUG: $_nearbyDebugInfo',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _buildFooter(b),
      ],
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────────

  Widget _buildHeader(Business b) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.warning.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: b.branding.heroPhotoUrl != null
                  ? CachedNetworkImage(
                      imageUrl: b.branding.heroPhotoUrl!,
                      fit: BoxFit.cover,
                      placeholder: (c, _) => Container(
                        color: AppColors.surface,
                      ),
                    )
                  : Container(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      child: const Icon(Icons.storefront,
                          color: AppColors.primary, size: 40),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'TrailShare',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    Text(
                      'OUTREACH KIT — ${b.type.displayName.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  b.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (b.location.city != null) b.location.city,
                    if (b.location.address != null) b.location.address,
                    'lat ${b.location.lat.toStringAsFixed(4)}, lng ${b.location.lng.toStringAsFixed(4)}',
                  ].whereType<String>().join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── INTRO ──────────────────────────────────────────────────────────

  Widget _buildIntro(Business b) {
    final isUnclaimed = b.tier == BusinessTier.unclaimed;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Perché ti contattiamo',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            isUnclaimed
                ? 'Abbiamo creato una scheda pubblica del tuo ${b.type.displayName.toLowerCase()} '
                    'su TrailShare a partire da fonti pubbliche (OpenStreetMap, '
                    'sito CAI, registro imprese). La scheda è già online ed è '
                    'visitata da escursionisti che cercano informazioni nella '
                    'tua zona. Ti proponiamo di prenderne il controllo: '
                    'aggiornarla, aggiungere foto, listino, percorsi consigliati '
                    'e ricevere statistiche reali delle visite.'
                : 'TrailShare è il social per outdoor enthusiast che usano '
                    'l\'app per trovare percorsi, registrare le proprie '
                    'attività e scoprire i luoghi della montagna italiana. '
                    'La scheda del tuo ${b.type.displayName.toLowerCase()} '
                    'su TrailShare è attiva e ti porta visibilità.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── FUNNEL STATS ───────────────────────────────────────────────────

  Widget _buildFunnelStats(Business b) {
    final c = b.funnelCounters;
    final views = c['unclaimed_view'] ?? 0;
    final started = c['claim_started'] ?? 0;
    final completed = c['claim_completed'] ?? 0;
    final conversion = views > 0
        ? '${((completed / views) * 100).toStringAsFixed(1)}%'
        : '—';
    final hasData = views + started + completed > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cosa sta già succedendo',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (!hasData)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'La scheda è stata pubblicata da poco: non abbiamo ancora '
              'dati statistici significativi. Possiamo aggiornarli al '
              'prossimo contatto.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              // Mobile stretto: stack verticale (un box per riga full
              // width). Tablet/desktop: 3 colonne affiancate.
              final wide = constraints.maxWidth >= 480;
              final boxes = [
                _statBox('Visualizzazioni', '$views', AppColors.info),
                _statBox('Click "Rivendica"', '$started', AppColors.warning),
                _statBox('Conversione', conversion, AppColors.primary),
              ];
              if (wide) {
                return Row(
                  children: [
                    Expanded(child: boxes[0]),
                    const SizedBox(width: 8),
                    Expanded(child: boxes[1]),
                    const SizedBox(width: 8),
                    Expanded(child: boxes[2]),
                  ],
                );
              }
              return Column(
                children: [
                  for (final b in boxes) ...[
                    SizedBox(width: double.infinity, child: b),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ─── MAP ────────────────────────────────────────────────────────────

  Widget _buildMap(Business b) {
    final center = LatLng(b.location.lat, b.location.lng);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dove sei e chi c\'è intorno',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 11,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none, // statica
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'app.trailshare',
                ),
                MarkerLayer(
                  markers: [
                    // marker centrale (la scheda)
                    Marker(
                      point: center,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_pin,
                          color: AppColors.primary, size: 36),
                    ),
                    // marker concorrenti zona
                    ..._nearby.take(20).map((n) => Marker(
                          point: LatLng(n.location.lat, n.location.lng),
                          width: 16,
                          height: 16,
                          child: Container(
                            decoration: BoxDecoration(
                              color: n.tier == BusinessTier.unclaimed
                                  ? AppColors.textMuted
                                  : AppColors.success,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ),
                          ),
                        )),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _legend(AppColors.primary, 'La tua scheda'),
            _legend(AppColors.success, 'Schede rivendicate (Pro)'),
            _legend(AppColors.textMuted, 'Schede non rivendicate'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }

  // ─── COMPETITOR ─────────────────────────────────────────────────────

  Widget _buildCompetitorSection(Business b, List<Business> nearby) {
    final claimed = nearby.where((n) => n.tier != BusinessTier.unclaimed).length;
    final unclaimed = nearby.where((n) => n.tier == BusinessTier.unclaimed).length;
    final total = claimed + unclaimed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Concorrenza zona (entro 10 km)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (total == 0)
          const Text(
            'Sei l\'unico ${"Spazio Pro"} nella zona. Vantaggio: chi cerca '
            'servizi outdoor qui trova solo te.',
            style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total schede TrailShare nella zona, '
                  '$claimed già rivendicate.',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                if (claimed > 0)
                  Text(
                    'I tuoi colleghi stanno già usando TrailShare per '
                    'farsi trovare. Più aspetti, più il loro vantaggio '
                    'di visibilità cresce.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (nearby.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...nearby.take(8).map((n) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: n.tier == BusinessTier.unclaimed
                                    ? AppColors.textMuted
                                    : AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                n.name,
                                style: const TextStyle(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              n.tier == BusinessTier.unclaimed
                                  ? 'non rivendicata'
                                  : 'attiva',
                              style: TextStyle(
                                fontSize: 10,
                                color: n.tier == BusinessTier.unclaimed
                                    ? AppColors.textMuted
                                    : AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // ─── FOOTER ─────────────────────────────────────────────────────────

  Widget _buildFooter(Business b) {
    final url = 'https://trailshare.app/b/${b.slug}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cosa puoi fare adesso',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Apri la pagina della tua scheda',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          // Riga link + QR. Link è cliccabile (InkWell) quando si guarda
          // la pagina su schermo. Il QR è la versione "carta": una volta
          // stampato il PDF, il rifugista scansiona col telefono e arriva
          // direttamente alla scheda. Flutter CanvasKit renderizza tutto
          // su canvas → in stampa i link non restano cliccabili, il QR
          // è la soluzione robusta.
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 420;
              final urlText = InkWell(
                onTap: () => _openExternal(url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    url,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.primary,
                    ),
                  ),
                ),
              );
              final qr = Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 96,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  gapless: true,
                ),
              );
              if (wide) {
                return Padding(
                  padding: const EdgeInsets.only(left: 18, top: 2, bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: urlText),
                      const SizedBox(width: 14),
                      qr,
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(left: 18, top: 2, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    urlText,
                    const SizedBox(height: 8),
                    qr,
                    const SizedBox(height: 4),
                    const Text(
                      'Scansiona il QR con la fotocamera del telefono',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textMuted),
                    ),
                  ],
                ),
              );
            },
          ),
          const Text(
            '2. Clicca "Rivendica la scheda" e compila il form (5 minuti)',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            '3. Il team TrailShare verifica entro 48h. Da lì gestisci '
            'foto, orari, listino, percorsi consigliati, statistiche.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 6),
          const Text(
            'Per qualunque domanda: info@trailshare.app',
            style: TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternal(String url) async {
    try {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (e) {
      debugPrint('[Outreach] launchUrl failed: $e');
    }
  }
}
