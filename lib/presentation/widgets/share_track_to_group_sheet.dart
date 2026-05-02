import 'package:flutter/material.dart';

import '../../core/utils/business_caps.dart';
import '../../data/models/track.dart';
import '../../data/repositories/groups_repository.dart';
import '../../data/repositories/tracks_repository.dart';

/// Bottom sheet che mostra all'utente i suoi gruppi (in cui è admin)
/// con un toggle per ciascuno: condivide / rimuove la traccia [track]
/// dal gruppo.
///
/// Solo admin: i membri "normali" non possono condividere percorsi.
/// Questa scelta evita spam nei gruppi B2B (es. clienti del noleggio
/// ebike non possono inquinare la lista percorsi consigliati).
///
/// ```dart
/// await showShareTrackToGroupSheet(context, track: myTrack);
/// ```
Future<void> showShareTrackToGroupSheet(
  BuildContext context, {
  required Track track,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.7,
    ),
    builder: (ctx) => _ShareTrackToGroupSheet(track: track),
  );
}

class _ShareTrackToGroupSheet extends StatefulWidget {
  final Track track;

  const _ShareTrackToGroupSheet({required this.track});

  @override
  State<_ShareTrackToGroupSheet> createState() =>
      _ShareTrackToGroupSheetState();
}

class _ShareTrackToGroupSheetState extends State<_ShareTrackToGroupSheet> {
  final _groupsRepo = GroupsRepository();
  final _tracksRepo = TracksRepository();

  bool _loading = true;
  List<_GroupWithRole> _items = [];
  // Track local toggle state per gruppo per UI ottimistica
  late Set<String> _selectedGroupIds;

  @override
  void initState() {
    super.initState();
    _selectedGroupIds = {...widget.track.groupIds};
    _load();
  }

  Future<void> _load() async {
    final myGroups = await _groupsRepo.getMyGroups();
    // Per ognuno chiediamo se siamo admin (regola: solo admin condivide)
    final List<_GroupWithRole> items = [];
    for (final g in myGroups) {
      final admin = await _groupsRepo.isAdmin(g.id);
      items.add(_GroupWithRole(group: g, isAdmin: admin));
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _toggle(_GroupWithRole entry, bool wantShared) async {
    final trackId = widget.track.id;
    if (trackId == null) return;
    final groupId = entry.group.id;

    // Cap check: se il gruppo è Verified/Trial e ha già raggiunto
    // il limite di 10 tracce condivise, blocca l'aggiunta e propone
    // upgrade. La rimozione (wantShared=false) non è mai bloccata.
    if (wantShared && BusinessCaps.applies(entry.group)) {
      final current = await _tracksRepo.getGroupTracks(groupId);
      // Se la traccia è già condivisa (toggle off→on dopo rimozione)
      // l'array contiene il trackId: non conta come superamento.
      final alreadyIn =
          current.any((t) => t.id == trackId);
      if (!alreadyIn && current.length >= BusinessCaps.verifiedTrackCap) {
        if (!mounted) return;
        await showTracksCapReached(context, entry.group);
        return;
      }
    }

    // Aggiornamento ottimistico
    setState(() {
      if (wantShared) {
        _selectedGroupIds.add(groupId);
      } else {
        _selectedGroupIds.remove(groupId);
      }
    });

    try {
      if (wantShared) {
        await _tracksRepo.shareTrackToGroup(trackId, groupId);
      } else {
        await _tracksRepo.unshareTrackFromGroup(trackId, groupId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wantShared
                ? 'Aggiunta come percorso in "${entry.group.name}"'
                : 'Rimossa da "${entry.group.name}"',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Rollback su errore
      if (!mounted) return;
      setState(() {
        if (wantShared) {
          _selectedGroupIds.remove(groupId);
        } else {
          _selectedGroupIds.add(groupId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adminGroups = _items.where((e) => e.isAdmin).toList();
    final hasAdminGroups = adminGroups.isNotEmpty;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'Condividi nel gruppo',
              style: theme.textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Aggiungi questa traccia ai percorsi consigliati di un '
              'gruppo di cui sei admin.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!hasAdminGroups)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Non sei admin di nessun gruppo',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Crea un gruppo dalla sezione Gruppi per condividere '
                    'percorsi con i tuoi clienti o amici.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                shrinkWrap: true,
                itemCount: adminGroups.length,
                itemBuilder: (ctx, i) {
                  final entry = adminGroups[i];
                  final shared = _selectedGroupIds.contains(entry.group.id);
                  return SwitchListTile(
                    title: Text(entry.group.name),
                    subtitle: entry.group.description != null &&
                            entry.group.description!.isNotEmpty
                        ? Text(
                            entry.group.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    secondary: const Icon(Icons.group),
                    value: shared,
                    onChanged: (v) => _toggle(entry, v),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupWithRole {
  final Group group;
  final bool isAdmin;

  _GroupWithRole({required this.group, required this.isAdmin});
}
