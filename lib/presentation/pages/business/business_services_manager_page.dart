import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/business_photos_service.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Gestione listino servizi/prodotti del business.
/// Se [readOnly] = true mostra in sola lettura (vista cliente).
class BusinessServicesManagerPage extends StatelessWidget {
  final String businessId;
  final bool readOnly;
  const BusinessServicesManagerPage({
    super.key,
    required this.businessId,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final repo = BusinessRepository();
    return Scaffold(
      appBar: AppBar(
        title: Text(readOnly ? 'Listino' : 'Gestisci listino'),
        actions: [
          if (!readOnly)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _editService(context, repo, null),
            ),
        ],
      ),
      body: StreamBuilder<List<BusinessService>>(
        stream: repo.watchServices(businessId),
        builder: (context, snap) {
          final services = snap.data ?? [];
          if (services.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 64, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text(readOnly
                      ? 'Nessun servizio in listino'
                      : 'Nessuna voce. Tocca + per aggiungere.'),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: services.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = services[i];
              return ListTile(
                title: Text(s.name),
                subtitle: s.description != null
                    ? Text(s.description!,
                        maxLines: 2, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: s.price != null
                    ? Text('€${s.price!.toStringAsFixed(0)} ${s.priceUnit.displayName}')
                    : null,
                onTap: readOnly
                    ? null
                    : () => _editService(context, repo, s),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editService(
    BuildContext context,
    BusinessRepository repo,
    BusinessService? existing,
  ) async {
    final result = await showModalBottomSheet<BusinessService?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _ServiceEditSheet(
            initial: existing, businessId: businessId),
      ),
    );
    if (result == null) return;
    if (existing == null) {
      await repo.createService(businessId, result);
    } else if (result.name == '__DELETE__') {
      await repo.deleteService(businessId, existing.id!);
    } else {
      await repo.updateService(businessId, existing.id!, result.toMap());
    }
  }
}

class _ServiceEditSheet extends StatefulWidget {
  final BusinessService? initial;
  final String businessId;
  const _ServiceEditSheet({this.initial, required this.businessId});

  @override
  State<_ServiceEditSheet> createState() => _ServiceEditSheetState();
}

class _ServiceEditSheetState extends State<_ServiceEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _price;
  late PriceUnit _unit;
  late bool _isActive;
  String? _photoUrl;
  bool _uploading = false;
  final _photos = BusinessPhotosService();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _desc = TextEditingController(text: widget.initial?.description ?? '');
    _price = TextEditingController(
        text: widget.initial?.price?.toStringAsFixed(0) ?? '');
    _unit = widget.initial?.priceUnit ?? PriceUnit.day;
    _isActive = widget.initial?.isActive ?? true;
    _photoUrl = widget.initial?.photoUrl;
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploading = true);
    final url = await _photos.pickAndUpload(
      businessId: widget.businessId,
      kind: BusinessPhotoKind.services,
    );
    if (url != null) {
      // Cancella vecchia foto best-effort
      if (_photoUrl != null) {
        _photos.deletePhotoByUrl(_photoUrl!);
      }
      setState(() => _photoUrl = url);
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final result = BusinessService(
      id: widget.initial?.id,
      name: _name.text.trim(),
      description:
          _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      price: double.tryParse(_price.text),
      priceUnit: _unit,
      photoUrl: _photoUrl,
      order: widget.initial?.order ?? 0,
      isActive: _isActive,
    );
    if (result.name.isEmpty) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.initial == null ? 'Nuova voce' : 'Modifica voce',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Foto voce
          GestureDetector(
            onTap: _uploading ? null : _pickPhoto,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _uploading
                  ? const Center(child: CircularProgressIndicator())
                  : _photoUrl != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: _photoUrl!,
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit,
                                        size: 12, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text('Cambia',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo,
                                  color: AppColors.textSecondary),
                              SizedBox(height: 4),
                              Text('Foto (opzionale)',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nome (es. "E-MTB full suspension")',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descrizione (opzionale)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prezzo €',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<PriceUnit>(
                  initialValue: _unit,
                  decoration: const InputDecoration(
                    labelText: 'Unità',
                    border: OutlineInputBorder(),
                  ),
                  items: PriceUnit.values
                      .map((u) => DropdownMenuItem(
                            value: u,
                            child: Text(u.displayName),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _unit = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visibile in listino'),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.initial != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      const BusinessService(name: '__DELETE__'),
                    );
                  },
                  icon: Icon(Icons.delete, color: AppColors.danger),
                  label: Text(context.l10n.delete,
                      style: TextStyle(color: AppColors.danger)),
                ),
              Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel),
              ),
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: _save,
                child: Text(context.l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
