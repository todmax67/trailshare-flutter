import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/csv_export.dart' show downloadBytes;
import '../../../data/models/business.dart';

/// 7.C9 — Card "Vetrina QR" brandizzata per uno Spazio Pro.
///
/// Genera un QR cliccabile che apre direttamente il profilo Spazio Pro
/// nell'app TrailShare (universal link `https://trailshare.app/b/{slug}`
/// con fallback custom scheme `trailshare://b/{id}` gestito dal
/// DeepLinkService).
///
/// L'utente owner può condividere la card (PNG 1080x1920 stampabile) via
/// share_plus: ideale per metterla in bacheca al rifugio, su volantini,
/// sui social.
class BusinessQrCardPage extends StatefulWidget {
  final Business business;

  const BusinessQrCardPage({super.key, required this.business});

  @override
  State<BusinessQrCardPage> createState() => _BusinessQrCardPageState();
}

class _BusinessQrCardPageState extends State<BusinessQrCardPage> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  String get _qrData {
    // Universal link friendly: preferiamo lo slug (URL human-readable +
    // condivisibile sul web). Fallback su scheme custom con doc id se
    // lo slug non è settato.
    final b = widget.business;
    if (b.slug.isNotEmpty) {
      return 'https://trailshare.app/b/${b.slug}';
    }
    return 'trailshare://b/${b.id}';
  }

  /// Genera il PNG dal RepaintBoundary e:
  /// - Su web: lancia download diretto via Blob+anchor (no dialog,
  ///   il file finisce nella cartella Download del browser)
  /// - Su mobile: scrive temp file e apre il share sheet del sistema
  ///   (l'utente sceglie WhatsApp/Drive/stampa/ecc.)
  ///
  /// Cross-platform via `downloadBytes` con conditional import
  /// (pattern già usato per CSV export).
  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('RepaintBoundary not found');
      }
      // pixelRatio 3.0 ≈ 1080x1920 PNG, ottimo per stampa A6 + IG stories.
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('PNG encode failed');
      }
      final Uint8List bytes = byteData.buffer.asUint8List();

      final slug = widget.business.slug.isNotEmpty
          ? widget.business.slug
          : widget.business.id ?? 'spazio-pro';
      final filename = 'trailshare-$slug-vetrina.png';

      await downloadBytes(
        bytes,
        filename,
        'image/png',
        shareSubject:
            'Spazio Pro ${widget.business.name} su TrailShare',
        shareText:
            'Scopri ${widget.business.name} su TrailShare. Scansiona il QR per aprire la vetrina.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nella condivisione: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Copia l'URL pubblico negli appunti. Universal link via slug,
  /// fallback su scheme custom (per app non installata + deep link).
  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _qrData));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copiato negli appunti'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    final accent = _parsePrimaryColor(b.branding.primaryColor) ?? AppColors.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vetrina QR'),
        actions: [
          IconButton(
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share),
            tooltip: 'Condividi',
            onPressed: _sharing ? null : _shareCard,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Stampa o condividi il QR. Chiunque lo scansiona arriva alla '
              'tua vetrina TrailShare e può seguirti.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            // Card story 9:16 condivisibile
            Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: RepaintBoundary(
                  key: _cardKey,
                  child: _buildCard(b, accent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sharing ? null : _shareCard,
              icon: Icon(kIsWeb ? Icons.download : Icons.share),
              label: Text(kIsWeb
                  ? 'Scarica PNG (1080×1920)'
                  : 'Condividi card PNG'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _copyLink,
              icon: const Icon(Icons.link),
              label: const Text('Copia link vetrina'),
            ),
            const SizedBox(height: 6),
            Text(
              _qrData,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Business b, Color accent) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.75)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo (se presente)
          if (b.branding.logoUrl != null && b.branding.logoUrl!.isNotEmpty)
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              clipBehavior: Clip.antiAlias,
              child: CachedNetworkImage(
                imageUrl: b.branding.logoUrl!,
                fit: BoxFit.cover,
                placeholder: (_, url) => Container(color: Colors.white),
                errorWidget: (_, url, err) => Icon(
                  Icons.business,
                  color: accent,
                  size: 40,
                ),
              ),
            )
          else
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.business, color: accent, size: 40),
            ),
          const SizedBox(height: 16),
          // Nome
          Text(
            b.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // Tagline (short description o tipo)
          Text(
            (b.shortDescription?.isNotEmpty == true)
                ? b.shortDescription!
                : _typeLabel(b.type),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          // QR su sfondo bianco
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: _qrData,
              version: QrVersions.auto,
              size: 180,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: accent,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF1A1A1A),
              ),
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          // CTA
          Text(
            'Scansiona con il telefono',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Apri TrailShare per seguire i miei aggiornamenti',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          // Branding TrailShare in fondo
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hiking, color: Colors.white.withValues(alpha: 0.8), size: 14),
              const SizedBox(width: 6),
              Text(
                'TrailShare',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.8),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Parse hex color stringa "#RRGGBB" o "#AARRGGBB". Ritorna null se
  /// non parseabile. Tolleriamo lo '#' iniziale opzionale.
  Color? _parsePrimaryColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceFirst('#', '');
    if (clean.length == 6) {
      final v = int.tryParse(clean, radix: 16);
      if (v == null) return null;
      return Color(0xFF000000 | v);
    }
    if (clean.length == 8) {
      final v = int.tryParse(clean, radix: 16);
      if (v == null) return null;
      return Color(v);
    }
    return null;
  }

  String _typeLabel(BusinessType t) {
    switch (t) {
      case BusinessType.rifugio:
        return 'Rifugio';
      case BusinessType.noleggio:
        return 'Noleggio';
      case BusinessType.guidaAlpina:
        return 'Guida alpina';
      case BusinessType.scuolaAlpinismo:
        return 'Scuola alpinismo';
      case BusinessType.shop:
        return 'Negozio outdoor';
      case BusinessType.tourOperator:
        return 'Tour operator';
      case BusinessType.consorzioTurismo:
        return 'Consorzio turismo';
      case BusinessType.altro:
        return 'Spazio Pro';
    }
  }
}
