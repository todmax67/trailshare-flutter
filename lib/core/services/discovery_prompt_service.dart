import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/discovery_prompt.dart';
import '../../data/repositories/emergency_contacts_repository.dart';
import '../../data/repositories/tours_repository.dart';
import '../../data/repositories/tracks_repository.dart';

/// Orchestrator dei [DiscoveryPrompt] da mostrare nel DiscoveryCarousel.
///
/// 1. Raccoglie uno [UserActivitySnapshot] dello stato utente (1 solo
///    round-trip per repository).
/// 2. Valuta le condizioni dei prompt passati da [collect] sulla snapshot.
/// 3. Filtra i prompt già dismissati (flag persistente in prefs).
/// 4. Ordina per priorità DESC.
/// 5. Restituisce i primi [maxPrompts] (default 5).
///
/// Non gestisce prompt remoti in questa prima iterazione: si aggiungerà
/// Firestore quando il carousel locale sarà validato sul campo.
class DiscoveryPromptService {
  static const String _dismissedPrefix = 'discovery_dismissed_';
  static const String _fitExportedKey = 'exported_fit_once';
  static const String _plannerUsedKey = 'planner_used_once';

  final TracksRepository _tracksRepo;
  final ToursRepository _toursRepo;
  final EmergencyContactsRepository _contactsRepo;

  DiscoveryPromptService({
    TracksRepository? tracksRepo,
    ToursRepository? toursRepo,
    EmergencyContactsRepository? contactsRepo,
  })  : _tracksRepo = tracksRepo ?? TracksRepository(),
        _toursRepo = toursRepo ?? ToursRepository(),
        _contactsRepo = contactsRepo ?? EmergencyContactsRepository();

  /// Calcola lo snapshot in parallelo (tutte le letture avvengono
  /// simultaneamente tramite Future.wait).
  Future<UserActivitySnapshot> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final results = await Future.wait([
      _tracksRepo.getMyTracks(),
      _toursRepo.getMyTours(),
      _contactsRepo.getContacts(),
    ]);
    final tracks = results[0] as List;
    final tours = results[1] as List;
    final contacts = results[2] as List;

    return UserActivitySnapshot(
      trackCount: tracks.length,
      hasLifelineContacts: contacts.isNotEmpty,
      hasPublishedTrack: tracks.any((t) => (t as dynamic).isPublic == true),
      tourCount: tours.length,
      hasExportedFit: prefs.getBool(_fitExportedKey) ?? false,
      hasUsedPlanner: prefs.getBool(_plannerUsedKey) ?? false,
    );
  }

  /// Valuta la lista dei prompt candidati contro lo snapshot e le preferenze
  /// di dismiss, ritornando al massimo [maxPrompts] ordinati per priorità.
  Future<List<DiscoveryPrompt>> collect(
    List<DiscoveryPrompt> candidates, {
    int maxPrompts = 5,
  }) async {
    final snap = await snapshot();
    final prefs = await SharedPreferences.getInstance();

    final active = <DiscoveryPrompt>[];
    for (final p in candidates) {
      if (prefs.getBool('$_dismissedPrefix${p.id}') == true) continue;
      if (p.condition != null && !p.condition!(snap)) continue;
      active.add(p);
    }
    active.sort((a, b) => b.priority.compareTo(a.priority));
    return active.take(maxPrompts).toList();
  }

  Future<void> dismiss(String promptId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_dismissedPrefix$promptId', true);
    debugPrint('[Discovery] prompt dismissato: $promptId');
  }

  /// Reset per debug: riabilita tutti i prompt dismissati.
  Future<void> resetAllDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_dismissedPrefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  /// Chiamato da chi ha appena eseguito un export FIT con successo.
  /// Fa scomparire il prompt "esporta in FIT" alla prossima apertura.
  static Future<void> markFitExported() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fitExportedKey, true);
  }

  /// Chiamato da chi ha usato il planner.
  static Future<void> markPlannerUsed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_plannerUsedKey, true);
  }
}
