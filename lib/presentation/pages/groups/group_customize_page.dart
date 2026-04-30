import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/groups_repository.dart';

/// Pagina di personalizzazione gruppo Business (Livello 1).
///
/// Disponibile solo se:
/// - L'utente e' admin del gruppo
/// - Il gruppo e' marcato come Business (isBusinessGroup=true)
///
/// Funzioni L1:
/// - Upload / sostituzione logo (square ~256x256, mostrato in lista
///   gruppi e header detail)
/// - Rimozione logo
///
/// L2 futuro: cover image 16:9, brand color picker.
class GroupCustomizePage extends StatefulWidget {
  final Group group;

  const GroupCustomizePage({super.key, required this.group});

  @override
  State<GroupCustomizePage> createState() => _GroupCustomizePageState();
}

class _GroupCustomizePageState extends State<GroupCustomizePage> {
  final _repo = GroupsRepository();
  final _picker = ImagePicker();
  bool _uploading = false;
  String? _currentLogoUrl;

  @override
  void initState() {
    super.initState();
    _currentLogoUrl = widget.group.avatarUrl;
  }

  Future<void> _pickAndUpload() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    final url = await _repo.uploadGroupLogo(
      widget.group.id,
      File(picked.path),
    );
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (url != null) _currentLogoUrl = url;
    });
    if (url != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo aggiornato')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante il caricamento')),
      );
    }
  }

  Future<void> _removeLogo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovere il logo?'),
        content: const Text(
          'Il gruppo tornera' ' a mostrare l\'avatar generico con la lettera iniziale.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _uploading = true);
    final ok = await _repo.removeGroupLogo(widget.group.id);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (ok) _currentLogoUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personalizza gruppo'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BusinessBanner(),
          const SizedBox(height: 24),

          // ── Logo del gruppo ──────────────────────────────────────
          Text('Logo', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Quadrato, formato JPG/PNG. Mostrato nella lista gruppi e '
            'nell\'header del dettaglio. Consigliato 512x512.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: _LogoPreview(
              logoUrl: _currentLogoUrl,
              groupName: widget.group.name,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _uploading ? null : _pickAndUpload,
                  icon: const Icon(Icons.upload),
                  label: Text(_currentLogoUrl == null
                      ? 'Carica logo'
                      : 'Sostituisci'),
                ),
              ),
              if (_currentLogoUrl != null) ...[
                const SizedBox(width: 12),
                IconButton.outlined(
                  onPressed: _uploading ? null : _removeLogo,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Rimuovi logo',
                ),
              ],
            ],
          ),

          if (_uploading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // ── Roadmap (cover, brand color) ─────────────────────────
          Text(
            'In arrivo',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _ComingSoonRow(
            icon: Icons.image_outlined,
            title: 'Immagine di copertina',
            subtitle: 'Banner 16:9 sopra il nome del gruppo',
          ),
          _ComingSoonRow(
            icon: Icons.palette_outlined,
            title: 'Colore brand personalizzato',
            subtitle: 'Sostituisce l\'arancio TrailShare negli accenti UI',
          ),
          _ComingSoonRow(
            icon: Icons.qr_code_2_outlined,
            title: 'Card invito brandizzata',
            subtitle: 'QR code con il tuo logo per onboarding clienti',
          ),
          _ComingSoonRow(
            icon: Icons.bar_chart,
            title: 'Statistiche aggregate',
            subtitle: 'Quante volte ogni percorso e\' stato seguito',
          ),
        ],
      ),
    );
  }
}

class _BusinessBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gruppo Business verificato',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Hai accesso alla personalizzazione visiva del gruppo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  final String? logoUrl;
  final String groupName;

  const _LogoPreview({required this.logoUrl, required this.groupName});

  @override
  Widget build(BuildContext context) {
    final letter = groupName.isNotEmpty ? groupName[0].toUpperCase() : '?';
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl != null
          ? CachedNetworkImage(
              imageUrl: logoUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) =>
                  Center(child: Text(letter, style: const TextStyle(fontSize: 48))),
            )
          : Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
    );
  }
}

class _ComingSoonRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ComingSoonRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
