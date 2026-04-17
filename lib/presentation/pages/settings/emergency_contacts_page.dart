import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/emergency_contact.dart';
import '../../../data/repositories/emergency_contacts_repository.dart';

/// Pagina gestione contatti di emergenza (max 3).
///
/// Accessibile da Impostazioni → Sicurezza → Contatti di emergenza.
/// Alimenta la feature Lifeline: questi contatti riceveranno il link
/// live + alert inattività/SOS quando l'utente attiva Lifeline durante
/// una registrazione.
class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({super.key});

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  final _repo = EmergencyContactsRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contatti di emergenza'),
      ),
      body: StreamBuilder<List<EmergencyContact>>(
        stream: _repo.watchContacts(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Errore: ${snap.error}'));
          }
          final contacts = snap.data ?? const [];

          return Column(
            children: [
              _buildIntroBanner(),
              Expanded(
                child: contacts.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          ...List.generate(
                            contacts.length * 2 - 1,
                            (i) => i.isEven
                                ? _buildContactTile(contacts[i ~/ 2])
                                : const Divider(height: 1),
                          ),
                          const SizedBox(height: 16),
                          _buildTemplateEditor(),
                        ],
                      ),
              ),
              if (contacts.length < EmergencyContactsRepository.maxContacts)
                _buildAddButton(),
              if (contacts.length >= EmergencyContactsRepository.maxContacts)
                _buildLimitReachedBanner(),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIntroBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Come funziona Lifeline',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configura fino a ${EmergencyContactsRepository.maxContacts} persone di fiducia. '
                  'Quando attivi Lifeline durante una registrazione, questi contatti '
                  'riceveranno un link per seguire la tua posizione in tempo reale. '
                  'In caso di inattività prolungata o SOS verranno avvisati '
                  'automaticamente.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _openLifelineTerms,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.open_in_new,
                          size: 13, color: AppColors.info),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Leggi i limiti di Lifeline',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.info,
                            decoration: TextDecoration.underline,
                          ),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contacts_outlined,
              size: 64, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 12),
          const Text(
            'Nessun contatto configurato',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Aggiungi almeno un contatto per abilitare Lifeline',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile(EmergencyContact c) {
    final subtitle = [
      if (c.phone != null && c.phone!.isNotEmpty) c.phone!,
      if (c.email != null && c.email!.isNotEmpty) c.email!,
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.info.withOpacity(0.15),
        child: Text(
          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.info,
          ),
        ),
      ),
      title: Text(
        c.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle.isEmpty ? 'Nessun contatto' : subtitle),
      trailing: PopupMenuButton<String>(
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Modifica')),
          PopupMenuItem(
            value: 'delete',
            child: Text('Elimina', style: TextStyle(color: AppColors.danger)),
          ),
        ],
        onSelected: (v) {
          if (v == 'edit') _editContact(c);
          if (v == 'delete') _deleteContact(c);
        },
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _addContact,
          icon: const Icon(Icons.add),
          label: const Text('Aggiungi contatto'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildLimitReachedBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Limite di ${EmergencyContactsRepository.maxContacts} contatti raggiunto. '
                'Elimina un contatto per aggiungerne altri.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateEditor() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          leading: const Icon(Icons.edit_note, color: AppColors.info),
          title: const Text(
            'Personalizza messaggio',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Testo inviato ai contatti all\'avvio di Lifeline',
            style: TextStyle(fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            FutureBuilder<String?>(
              future: _repo.getMessageTemplate(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  );
                }
                return _TemplateEditor(
                  initial: snap.data ??
                      EmergencyContactsRepository.defaultMessageTemplate,
                  onSaved: (text) async {
                    final toSave = text.trim() ==
                            EmergencyContactsRepository.defaultMessageTemplate.trim()
                        ? null
                        : text;
                    await _repo.setMessageTemplate(toSave);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          toSave == null
                              ? 'Ripristinato messaggio predefinito'
                              : 'Messaggio personalizzato salvato',
                        ),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Apre i Termini di Servizio direttamente alla sezione Lifeline/SOS.
  /// Usa l'anchor #7 che punta alla sezione 7 "Funzioni di sicurezza".
  Future<void> _openLifelineTerms() async {
    final uri = Uri.parse('https://trailshare.app/terms#7');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossibile aprire i Termini di Servizio'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Errore apertura ToS: $e');
    }
  }

  Future<void> _addContact() async {
    final newContact = await _showContactEditor();
    if (newContact == null) return;
    try {
      final count = (await _repo.getContacts()).length;
      await _repo.addContact(newContact.copyWith(order: count));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _editContact(EmergencyContact c) async {
    final updated = await _showContactEditor(initial: c);
    if (updated == null) return;
    try {
      await _repo.updateContact(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _deleteContact(EmergencyContact c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare contatto?'),
        content: Text('${c.name} non riceverà più notifiche Lifeline.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteContact(c.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<EmergencyContact?> _showContactEditor({EmergencyContact? initial}) {
    return showModalBottomSheet<EmergencyContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactEditorSheet(initial: initial),
    );
  }
}

/// Bottom sheet per creare/modificare un contatto.
class _ContactEditorSheet extends StatefulWidget {
  final EmergencyContact? initial;
  const _ContactEditorSheet({this.initial});

  @override
  State<_ContactEditorSheet> createState() => _ContactEditorSheetState();
}

class _ContactEditorSheetState extends State<_ContactEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _phone = TextEditingController(text: widget.initial?.phone ?? '');
    _email = TextEditingController(text: widget.initial?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  isEdit ? 'Modifica contatto' : 'Nuovo contatto',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nome *',
                    hintText: 'es. Marco fratello, Moglie',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefono',
                    hintText: '+39 333 1234567',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if ((v == null || v.trim().isEmpty) &&
                        _email.text.trim().isEmpty) {
                      return 'Inserisci telefono o email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'marco@example.com',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                Text(
                  'Almeno uno tra telefono ed email è obbligatorio.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annulla'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Salva'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final result = EmergencyContact(
      id: widget.initial?.id ?? '',
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      trailShareUserId: widget.initial?.trailShareUserId,
      order: widget.initial?.order ?? 0,
      createdAt: widget.initial?.createdAt,
    );
    Navigator.pop(context, result);
  }
}

/// Editor inline del template messaggio. Mostra il testo attuale + un
/// preview renderizzato con dati finti (Marco / Trekking / link fittizio)
/// così l'utente capisce dove finiranno i placeholder.
class _TemplateEditor extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onSaved;

  const _TemplateEditor({required this.initial, required this.onSaved});

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          maxLines: null,
          minLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          'Placeholder disponibili: {nome}, {attività}, {nomeTraccia}, {link}',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.info.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Anteprima',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                EmergencyContactsRepository.renderTemplate(
                  template: _ctrl.text,
                  contactName: 'Marco',
                  activityName: 'Trekking',
                  referenceName: 'Rifugio Brentei',
                  link: 'https://trailshare.app/live?id=abc&token=xyz',
                ),
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _ctrl.text =
                        EmergencyContactsRepository.defaultMessageTemplate;
                  });
                },
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Default'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _ctrl.text.trim().isEmpty
                    ? null
                    : () => widget.onSaved(_ctrl.text),
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Salva'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
