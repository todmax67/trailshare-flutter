import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/group_brand.dart';
import '../../../data/repositories/groups_repository.dart';

/// Card invito brandizzata per gruppi Business L1.
///
/// Renderizza una "story card" 9:16 con cover/brand color, logo,
/// nome gruppo, QR del codice invito e CTA testuale. L'utente
/// admin può condividerla come PNG (Instagram stories, WhatsApp,
/// stampa, ecc.).
class BusinessInviteCardPage extends StatefulWidget {
  final Group group;

  const BusinessInviteCardPage({super.key, required this.group});

  @override
  State<BusinessInviteCardPage> createState() => _BusinessInviteCardPageState();
}

class _BusinessInviteCardPageState extends State<BusinessInviteCardPage> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // pixelRatio 3.0 = circa 1080x1920 per uno story-card 360x640.
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('RepaintBoundary not found');
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('PNG encode failed');
      }
      final Uint8List bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/trailshare_invito_${widget.group.id}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Invito al gruppo ${widget.group.name}',
          text:
              'Scansiona il QR con TrailShare per unirti al gruppo "${widget.group.name}".',
        ),
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

  @override
  Widget build(BuildContext context) {
    final code = widget.group.inviteCode;
    if (code == null || code.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Card invito')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Questo gruppo non ha ancora un codice invito. '
              'Generane uno dalla scheda Info del gruppo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Card invito')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: _cardKey,
                  child: _InviteCard(
                    group: widget.group,
                    code: code,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sharing ? null : _shareCard,
                  icon: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share),
                  label: Text(_sharing ? 'Condivisione…' : 'Condividi card'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final Group group;
  final String code;

  const _InviteCard({required this.group, required this.code});

  @override
  Widget build(BuildContext context) {
    final accent = groupAccentColor(group);
    // Card 9:16: dimensioni nominali 360x640. Il pixelRatio 3.0 al
    // capture porta a 1080x1920 = formato story Instagram.
    return Container(
      width: 360,
      height: 640,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header: cover image se presente, altrimenti gradient brand
          SizedBox(
            height: 180,
            width: double.infinity,
            child: group.hasCustomCover
                ? CachedNetworkImage(
                    imageUrl: group.coverUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        _gradientHeader(accent),
                    errorWidget: (_, __, ___) =>
                        _gradientHeader(accent),
                  )
                : _gradientHeader(accent),
          ),
          // Body
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Logo overlapping il bordo header/body
                Positioned(
                  top: -36,
                  left: 0,
                  right: 0,
                  child: Center(child: _LogoCircle(group: group, accent: accent)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                  child: Column(
                    children: [
                      // Nome gruppo
                      Text(
                        group.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Pill BUSINESS
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.4),
                              width: 1),
                        ),
                        child: Text(
                          'BUSINESS · TrailShare',
                          style: TextStyle(
                            color: accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // QR
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: QrImageView(
                          // URL https: la fotocamera lo riconosce come
                          // azionabile e apre la pagina ponte web, che
                          // a sua volta lancia il custom scheme
                          // trailshare://g/{code} per aprire l'app.
                          data: 'https://trailshare.app/g/$code',
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
                      const SizedBox(height: 12),
                      // Codice testuale di backup
                      Text(
                        code,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: accent,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Footer CTA
                      Text(
                        'Scansiona col telefono per unirti su TrailShare',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientHeader(Color accent) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            Color.alphaBlend(
              Colors.black.withValues(alpha: 0.25),
              accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoCircle extends StatelessWidget {
  final Group group;
  final Color accent;

  const _LogoCircle({required this.group, required this.accent});

  @override
  Widget build(BuildContext context) {
    final hasLogo = group.hasCustomLogo;
    final letter =
        group.name.isNotEmpty ? group.name[0].toUpperCase() : '?';
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? CachedNetworkImage(
              imageUrl: group.avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  _initialFallback(letter, accent),
              errorWidget: (_, __, ___) =>
                  _initialFallback(letter, accent),
            )
          : _initialFallback(letter, accent),
    );
  }

  Widget _initialFallback(String letter, Color accent) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.12),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
      ),
    );
  }
}
