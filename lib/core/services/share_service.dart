import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/track.dart';

class ShareService {
  /// Condividi traccia sui social con testo + immagine opzionale
  static Future<void> shareTrackSocial({
    required String name,
    required double distanceKm,
    required double elevationGain,
    required String durationFormatted,
    required String activityEmoji,
    String? activityName,
    Uint8List? mapScreenshot,
  }) async {
    final text = _buildShareText(
      name: name,
      distanceKm: distanceKm,
      elevationGain: elevationGain,
      durationFormatted: durationFormatted,
      activityEmoji: activityEmoji,
      activityName: activityName,
    );

    if (mapScreenshot != null) {
      // Condividi con immagine
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/trailshare_track.png');
      await file.writeAsBytes(mapScreenshot);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
        subject: 'La mia attività su TrailShare',
      );
    } else {
      // Solo testo
      await Share.share(text, subject: 'La mia attività su TrailShare');
    }
  }

  /// Genera il testo di condivisione
  static String _buildShareText({
    required String name,
    required double distanceKm,
    required double elevationGain,
    required String durationFormatted,
    required String activityEmoji,
    String? activityName,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('$activityEmoji ${activityName ?? "Attività"} completata con TrailShare!');
    buffer.writeln('');
    buffer.writeln('📍 $name');
    buffer.writeln('📏 ${distanceKm.toStringAsFixed(1)} km');
    
    if (elevationGain > 0) {
      buffer.writeln('⬆️ +${elevationGain.toStringAsFixed(0)} m');
    }
    
    if (durationFormatted.isNotEmpty && durationFormatted != '--') {
      buffer.writeln('⏱️ $durationFormatted');
    }

    buffer.writeln('');
    buffer.writeln('🗺️ Traccia le tue avventure con TrailShare!');
    buffer.writeln('📲 https://trailshare.app');

    return buffer.toString();
  }

  /// Cattura screenshot di un widget tramite GlobalKey
  static Future<Uint8List?> captureWidget(GlobalKey key) async {
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[Share] Errore cattura screenshot: $e');
      return null;
    }
  }

  /// Mostra bottom sheet con opzioni di condivisione
  static void showShareOptions({
    required BuildContext context,
    required String name,
    required double distanceKm,
    required double elevationGain,
    required String durationFormatted,
    required String activityEmoji,
    String? activityName,
    GlobalKey? mapKey,
    VoidCallback? onExportGpx,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Condividi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),

              // Condividi sui social
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.send, color: Colors.green),
                ),
                title: const Text('Condividi sui social'),
                subtitle: const Text('WhatsApp, Instagram, Telegram...'),
                onTap: () async {
                  Navigator.pop(ctx);

                  // Cattura screenshot mappa se disponibile
                  Uint8List? screenshot;
                  if (mapKey != null) {
                    screenshot = await captureWidget(mapKey);
                  }

                  await shareTrackSocial(
                    name: name,
                    distanceKm: distanceKm,
                    elevationGain: elevationGain,
                    durationFormatted: durationFormatted,
                    activityEmoji: activityEmoji,
                    activityName: activityName,
                    mapScreenshot: screenshot,
                  );
                },
              ),

              // Esporta GPX
              if (onExportGpx != null)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.file_download, color: Colors.blue),
                  ),
                  title: const Text('Esporta file GPX'),
                  subtitle: const Text('Per altre app GPS'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onExportGpx();
                  },
                ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
