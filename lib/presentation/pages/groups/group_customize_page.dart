import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/csv_export.dart';
import '../../../core/utils/group_brand.dart';
import '../../../core/utils/web_layout.dart';
import '../../../data/repositories/groups_repository.dart';
import 'business_invite_card_page.dart';
import 'group_stats_page.dart';

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
  bool _uploadingCover = false;
  String? _currentLogoUrl;
  String? _currentCoverUrl;
  int? _currentBrandColor;
  bool _savingBrand = false;

  @override
  void initState() {
    super.initState();
    _currentLogoUrl = widget.group.avatarUrl;
    _currentCoverUrl = widget.group.coverUrl;
    _currentBrandColor = widget.group.brandColor;
  }

  Future<void> _selectBrandColor(int? colorValue) async {
    setState(() => _savingBrand = true);
    final ok = colorValue == null
        ? await _repo.clearBrandColor(widget.group.id)
        : await _repo.setBrandColor(widget.group.id, colorValue);
    if (!mounted) return;
    setState(() {
      _savingBrand = false;
      if (ok) _currentBrandColor = colorValue;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore nel salvataggio del colore')),
      );
    }
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
      await picked.readAsBytes(),
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

  Future<void> _pickAndUploadCover() async {
    // Aspect ratio 16:9: chiediamo immagine ampia, lasciamo poi
    // BoxFit.cover renderizzare il crop. maxWidth 1920 = full HD,
    // dimensione raccomandata banner web/mobile.
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploadingCover = true);
    final url = await _repo.uploadGroupCover(
      widget.group.id,
      await picked.readAsBytes(),
    );
    if (!mounted) return;
    setState(() {
      _uploadingCover = false;
      if (url != null) _currentCoverUrl = url;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(url != null
            ? 'Copertina aggiornata'
            : 'Errore durante il caricamento'),
      ),
    );
  }

  Future<void> _removeCover() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovere la copertina?'),
        content: const Text(
          'Il gruppo tornera\' a mostrare il layout senza banner.',
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

    setState(() => _uploadingCover = true);
    final ok = await _repo.removeGroupCover(widget.group.id);
    if (!mounted) return;
    setState(() {
      _uploadingCover = false;
      if (ok) _currentCoverUrl = null;
    });
  }

  void _showPresetGallerySoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Galleria sfondi pronti in arrivo'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personalizza gruppo'),
      ),
      body: WebContentWrapper(
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BusinessBanner(group: widget.group),
          const SizedBox(height: 24),

          // ── Cover image 16:9 ─────────────────────────────────────
          Text('Copertina', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Banner 16:9 mostrato in cima alla scheda Info del gruppo. '
            'Consigliato 1920x1080.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _CoverPreview(coverUrl: _currentCoverUrl),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _uploadingCover ? null : _pickAndUploadCover,
                  icon: const Icon(Icons.upload),
                  label: Text(_currentCoverUrl == null
                      ? 'Carica copertina'
                      : 'Sostituisci'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _uploadingCover ? null : _showPresetGallerySoon,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Sfondi'),
              ),
              if (_currentCoverUrl != null) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: _uploadingCover ? null : _removeCover,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Rimuovi copertina',
                ),
              ],
            ],
          ),
          if (_uploadingCover) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

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

          // ── Colore brand ─────────────────────────────────────────
          Text('Colore brand', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Sostituisce l\'arancio TrailShare negli accenti UI delle '
            'viste interne al gruppo (tab attivo, badge, evidenziazioni).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _BrandColorPicker(
            selected: _currentBrandColor,
            onSelect: _savingBrand ? null : _selectBrandColor,
          ),
          if (_savingBrand) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // ── Card invito brandizzata ──────────────────────────────
          Text('Card invito brandizzata', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Genera una card 9:16 con logo, colore brand e QR del codice '
            'invito. Pronta per Instagram Stories, WhatsApp, stampa.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: widget.group.inviteCode == null
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BusinessInviteCardPage(
                            group: widget.group,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.qr_code_2),
              label: Text(widget.group.inviteCode == null
                  ? 'Genera prima un codice invito'
                  : 'Apri card invito'),
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // ── Statistiche aggregate ────────────────────────────────
          Text('Statistiche', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Vista d\'insieme: membri, iscritti via codice, tracce e '
            'eventi attivi. Statistiche dettagliate disponibili con Pro.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupStatsPage(group: widget.group),
                  ),
                );
              },
              icon: const Icon(Icons.bar_chart),
              label: const Text('Apri statistiche'),
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // ── Pinned post (Pro) ────────────────────────────────────
          _PinnedPostSection(
            group: widget.group,
            onSaved: () {
              // Forza rebuild del banner: nessun-op, la pagina
              // viene chiusa e GroupDetailPage ricarica al return.
              if (mounted) setState(() {});
            },
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // ── Esporta membri CSV (Pro) ─────────────────────────────
          _CsvExportSection(group: widget.group),
        ],
      ),
      ),
    );
  }
}

/// Sezione "Messaggio fisso" della pagina Personalizza. Comportamento
/// per tier:
/// - Pro / Enterprise: editor inline con preview, salva su Firestore
/// - Verified / Trial: teaser di upgrade verso Pro
/// - non-Business: nascosto
/// Sezione "Esporta membri (CSV)" della pagina Personalizza.
/// Tier Pro/Enterprise: bottone download. Verified/Trial: teaser
/// upgrade. Non-Business: hidden.
class _CsvExportSection extends StatefulWidget {
  final Group group;
  const _CsvExportSection({required this.group});

  @override
  State<_CsvExportSection> createState() => _CsvExportSectionState();
}

class _CsvExportSectionState extends State<_CsvExportSection> {
  final _repo = GroupsRepository();
  bool _busy = false;

  bool get _isProTier =>
      widget.group.businessTier == 'pro' ||
      widget.group.businessTier == 'enterprise';

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final csv = await _repo.exportMembersToCsv(widget.group.id);
      // Sanitizza il nome gruppo per usarlo come filename (no spazi,
      // no punti, max 30 char) — i sistemi share/download non amano
      // certi caratteri.
      final safe = widget.group.name
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
          .toLowerCase();
      final clipped = safe.length > 30 ? safe.substring(0, 30) : safe;
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 16);
      final filename = 'trailshare_${clipped}_membri_$ts.csv';
      await exportCsv(csv, filename);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export CSV pronto')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore export: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = groupAccentColor(widget.group);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Esporta membri', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Text(
                'PRO',
                style: TextStyle(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Scarica la lista membri in formato CSV per importarla nel '
          'tuo CRM (username, email, ruolo, data iscrizione).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (_isProTier)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
              label: Text(_busy ? 'Genero CSV…' : 'Scarica CSV membri'),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.workspace_premium, color: accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Disponibile con Business Pro',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'L\'export CSV dei membri è una feature Pro per '
                        'integrazione con CRM proprio. €49,99/mese o '
                        '€499/anno.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PinnedPostSection extends StatefulWidget {
  final Group group;
  final VoidCallback onSaved;

  const _PinnedPostSection({required this.group, required this.onSaved});

  @override
  State<_PinnedPostSection> createState() => _PinnedPostSectionState();
}

class _PinnedPostSectionState extends State<_PinnedPostSection> {
  late final TextEditingController _controller;
  final _repo = GroupsRepository();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.group.pinnedPostText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isProTier =>
      widget.group.businessTier == 'pro' ||
      widget.group.businessTier == 'enterprise';

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = _controller.text.trim().isEmpty
        ? await _repo.clearPinnedPost(widget.group.id)
        : await _repo.setPinnedPost(widget.group.id, _controller.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_controller.text.trim().isEmpty
              ? 'Messaggio fisso rimosso'
              : 'Messaggio fisso aggiornato'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore nel salvataggio')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = groupAccentColor(widget.group);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Messaggio fisso', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Text(
                'PRO',
                style: TextStyle(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Annuncio fisso in cima al chat del gruppo. Modificabile in '
          'qualsiasi momento, visibile a tutti i membri.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (_isProTier) ...[
          TextField(
            controller: _controller,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Es. "Domenica trail+grigliata, scrivici per i posti."',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.push_pin),
              label: Text(_controller.text.trim().isEmpty
                  ? 'Salva (rimuovi se vuoto)'
                  : 'Salva messaggio fisso'),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.workspace_premium, color: accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Disponibile con Business Pro',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Il messaggio fisso è una feature Pro. Passa a '
                        '€49,99/mese o €499/anno per sbloccarla.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BusinessBanner extends StatelessWidget {
  final Group group;
  const _BusinessBanner({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = groupAccentColor(group);
    final isTrial = group.businessTier == 'trial';
    final trialDays = group.trialDaysRemaining;

    final title = group.businessTierLabel;
    final subtitle = isTrial
        ? (trialDays > 0
            ? 'Trial attivo: $trialDays giorni rimasti. Configura subscription per continuare.'
            : 'Trial scaduto. Riattiva la subscription per ripristinare i privilegi Business.')
        : (group.businessTier == 'pro'
            ? 'Tier Pro: tracce ed eventi illimitati, statistiche avanzate, team admin.'
            : group.businessTier == 'enterprise'
                ? 'Tier Enterprise: multi-gruppo, white-label, API dedicate.'
                : 'Hai accesso a logo, cover, brand color, card invito e statistiche aggregate.');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.15),
            accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTrial ? Icons.schedule : Icons.verified,
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
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
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
              placeholder: (_, _) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (_, _, _) =>
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

class _CoverPreview extends StatelessWidget {
  final String? coverUrl;

  const _CoverPreview({required this.coverUrl});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: coverUrl != null
            ? CachedNetworkImage(
                imageUrl: coverUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 40),
                ),
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 40,
                      color: AppColors.primary.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Nessuna copertina',
                      style: TextStyle(
                        color: AppColors.primary.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _BrandColorPicker extends StatelessWidget {
  /// Valore ARGB attualmente salvato. null = default arancio.
  final int? selected;
  final void Function(int? colorValue)? onSelect;

  const _BrandColorPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (int i = 0; i < GroupBrandPalette.swatches.length; i++)
          _SwatchDot(
            swatch: GroupBrandPalette.swatches[i],
            // Index 0 = default arancio: salviamo null per "nessun custom".
            isSelected: i == 0
                ? selected == null
                : selected == GroupBrandPalette.swatches[i].color.toARGB32(),
            onTap: onSelect == null
                ? null
                : () => onSelect!(
                    i == 0 ? null : GroupBrandPalette.swatches[i].color.toARGB32(),
                  ),
          ),
      ],
    );
  }
}

class _SwatchDot extends StatelessWidget {
  final GroupBrandSwatch swatch;
  final bool isSelected;
  final VoidCallback? onTap;

  const _SwatchDot({
    required this.swatch,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: swatch.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: swatch.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.black.withValues(alpha: 0.1),
              width: isSelected ? 3 : 1,
            ),
          ),
          child: isSelected
              ? const Icon(Icons.check, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }
}

