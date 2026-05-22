import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// Hero della scheda Tour: cover photo full-bleed con gradient
/// nero sfumato in fondo + titolo sovrapposto, mappa polyline
/// rounded sotto con padding laterale.
///
/// Sostituisce il blocco "AspectRatio cover + SizedBox mappa" che
/// faceva sembrare due elementi separati incollati. Adesso è una
/// composizione unica più "magazine".
class TourHero extends StatelessWidget {
  final String? coverPhotoUrl;
  final String title;
  final String? subtitle;
  final Widget map;
  final double mapHeight;
  final double coverHeight;

  const TourHero({
    super.key,
    required this.coverPhotoUrl,
    required this.title,
    required this.map,
    this.subtitle,
    this.mapHeight = 280,
    this.coverHeight = 280,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (coverPhotoUrl != null)
          SizedBox(
            height: coverHeight,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: coverPhotoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (c, _) =>
                      Container(color: AppColors.surface),
                ),
                // Gradient nero sfumato sotto per leggibilità titolo
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                // Titolo + subtitle in basso
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 8,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        // Mappa rounded con padding laterale per dare il senso di
        // "sezione" separata dalla cover, ma senza enorme stacco.
        Padding(
          padding: EdgeInsets.only(
            top: coverPhotoUrl != null ? 12 : 0,
            left: 12,
            right: 12,
            bottom: 8,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: mapHeight,
              child: map,
            ),
          ),
        ),
      ],
    );
  }
}
