import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';

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
        child: _ServiceEditSheet(initial: existing),
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
  const _ServiceEditSheet({this.initial});

  @override
  State<_ServiceEditSheet> createState() => _ServiceEditSheetState();
}

class _ServiceEditSheetState extends State<_ServiceEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _price;
  late PriceUnit _unit;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _desc = TextEditingController(text: widget.initial?.description ?? '');
    _price = TextEditingController(
        text: widget.initial?.price?.toStringAsFixed(0) ?? '');
    _unit = widget.initial?.priceUnit ?? PriceUnit.day;
    _isActive = widget.initial?.isActive ?? true;
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
      photoUrl: widget.initial?.photoUrl,
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
                  icon: const Icon(Icons.delete, color: AppColors.danger),
                  label: const Text('Elimina',
                      style: TextStyle(color: AppColors.danger)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annulla'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Salva'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
