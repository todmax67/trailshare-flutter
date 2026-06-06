import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/garmin_pairing_service.dart';
import '../../widgets/app_snackbar.dart';

/// Abbina la watch app TrailShare per Garmin (Connect IQ) al proprio account:
/// genera un codice, lo incolli nelle impostazioni dell'app sul Garmin, e da lì
/// le attività registrate dal polso arrivano in TrailShare.
class GarminPairingPage extends StatefulWidget {
  const GarminPairingPage({super.key});

  @override
  State<GarminPairingPage> createState() => _GarminPairingPageState();
}

class _GarminPairingPageState extends State<GarminPairingPage> {
  final _service = GarminPairingService();
  bool _loading = true;
  bool _busy = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await _service.currentToken();
    if (!mounted) return;
    setState(() {
      _token = t;
      _loading = false;
    });
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    final t = await _service.createPairing();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (t != null) _token = t;
    });
    if (t == null) {
      AppSnackBar.error(context, 'Generazione codice non riuscita');
    }
  }

  Future<void> _revoke() async {
    setState(() => _busy = true);
    final ok = await _service.revoke();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _token = null;
    });
    AppSnackBar.info(context, ok ? 'Codice revocato' : 'Revoca non riuscita');
  }

  void _copy() {
    if (_token == null) return;
    Clipboard.setData(ClipboardData(text: _token!));
    AppSnackBar.success(context, 'Codice copiato');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abbina il tuo Garmin')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Registra le attività direttamente dal tuo Garmin con l\'app '
                  'TrailShare per Connect IQ: il percorso, le statistiche e il '
                  'battito arrivano qui automaticamente.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),

                // Codice
                if (_token != null) ...[
                  const Text('Il tuo codice di abbinamento',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _token!,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copia',
                          onPressed: _copy,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Rigenera'),
                        onPressed: _busy ? null : _generate,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('Revoca'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger),
                        onPressed: _busy ? null : _revoke,
                      ),
                    ],
                  ),
                ] else
                  Center(
                    child: FilledButton.icon(
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.4))
                          : const Icon(Icons.watch),
                      label: const Text('Genera codice di abbinamento'),
                      onPressed: _busy ? null : _generate,
                    ),
                  ),

                const SizedBox(height: 32),
                const Text('Come si usa',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                _step('1', 'Installa l\'app TrailShare sul tuo Garmin dal '
                    'Connect IQ Store.'),
                _step('2', 'Apri Garmin Connect Mobile → menu → I miei '
                    'dispositivi → App Connect IQ → TrailShare → Impostazioni.'),
                _step('3', 'Incolla il codice qui sopra nel campo "Codice '
                    'abbinamento" e salva.'),
                _step('4', 'Avvia l\'app TrailShare sull\'orologio e registra: '
                    'al salvataggio l\'attività compare nelle tue tracce.'),
              ],
            ),
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.primary,
            child: Text(n,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(height: 1.4)),
          ),
        ],
      ),
    );
  }
}
