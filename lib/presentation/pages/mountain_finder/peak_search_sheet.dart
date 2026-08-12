import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/peaks_dataset_service.dart';
import '../../../core/utils/peak_search.dart';
import '../../../data/models/mountain_peak.dart';

/// «Dov'è il Monte Rosa da qui?»
///
/// È la domanda che il mirino non può porre, perché per riconoscere una cima
/// bisogna già averla davanti. Qui si fa il contrario: si dice il nome e l'app
/// dice da che parte girarsi.
///
/// Restituisce la cima scelta al chiamante, che la userà come bersaglio.
class PeakSearchSheet extends StatefulWidget {
  /// Da dove si guarda: serve a ordinare i risultati, non a filtrarli.
  final double? observerLat;
  final double? observerLng;

  const PeakSearchSheet({super.key, this.observerLat, this.observerLng});

  @override
  State<PeakSearchSheet> createState() => _PeakSearchSheetState();
}

class _PeakSearchSheetState extends State<PeakSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PeakSearchHit> _hits = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    // Trentasettemila confronti a ogni lettera sono pochi millisecondi, ma sono
    // sul thread che disegna: aspettare che il dito si fermi costa niente e
    // toglie ogni rischio di scatto mentre si scrive.
    _debounce = Timer(const Duration(milliseconds: 180), () => _run(q));
  }

  void _run(String q) {
    final ds = PeaksDatasetService();
    if (!ds.isLoaded) {
      setState(() => _searching = true);
      ds.ensureLoaded().then((_) {
        if (mounted) _run(q);
      });
      return;
    }
    setState(() {
      _searching = false;
      _hits = ds.searchByName(
        q,
        observerLat: widget.observerLat,
        observerLng: widget.observerLng,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    return Padding(
      // La tastiera non deve coprire i risultati: è l'unica schermata dell'app
      // dove si digita e si legge nello stesso momento.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.themedBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Cerca una cima: Monte Rosa, Coca…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _hits = const []);
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (query.length < 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Text(
                  'Scrivi almeno due lettere. I risultati più vicini a te '
                  'vengono prima.',
                  style: TextStyle(fontSize: 12, color: context.textMuted),
                ),
              )
            else if (_hits.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Text(
                  'Nessuna cima con questo nome nel catalogo.',
                  style: TextStyle(fontSize: 13, color: context.textMuted),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _hits.length,
                  itemBuilder: (context, i) => _Riga(
                    hit: _hits[i],
                    onTap: () => Navigator.pop<MountainPeak>(
                        context, _hits[i].peak),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Riga extends StatelessWidget {
  final PeakSearchHit hit;
  final VoidCallback onTap;
  const _Riga({required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final quota = hit.peak.elevation;
    final d = hit.distanceMeters;
    final dettagli = <String>[
      if (quota != null) '${quota.round()} m',
      if (d != null)
        d < 10000 ? '${(d / 1000).toStringAsFixed(1)} km' : '${(d / 1000).round()} km',
    ];

    return ListTile(
      dense: true,
      leading: Icon(
        hit.peak.type == 'volcano' ? Icons.volcano : Icons.terrain,
        color: hit.peak.type == 'volcano'
            ? AppColors.danger
            : AppColors.primary,
      ),
      title: Text(
        hit.peak.name,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: context.textPrimary,
        ),
      ),
      subtitle: dettagli.isEmpty
          ? null
          : Text(
              dettagli.join(' · '),
              style: TextStyle(fontSize: 12, color: context.textMuted),
            ),
      trailing: Icon(Icons.explore, size: 18, color: context.textMuted),
      onTap: onTap,
    );
  }
}
