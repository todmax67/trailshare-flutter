import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/perf_trace.dart';

/// Stato della checklist "primi passi": quali azioni di attivazione il nuovo
/// utente ha già completato.
class OnboardingChecklistState {
  final bool recorded; // ha registrato almeno una traccia
  final bool explored; // ha aperto Discover almeno una volta
  final bool favorited; // ha salvato almeno un sentiero nei preferiti
  final bool profileDone; // ha avatar o bio

  const OnboardingChecklistState({
    required this.recorded,
    required this.explored,
    required this.favorited,
    required this.profileDone,
  });

  int get total => 4;
  int get doneCount =>
      (recorded ? 1 : 0) +
      (explored ? 1 : 0) +
      (favorited ? 1 : 0) +
      (profileDone ? 1 : 0);
  bool get allDone => doneCount >= total;
}

/// Onboarding ATTIVO (vs le 5 slide passive): guida il nuovo utente alle prime
/// azioni che lo rendono attivo. Rileva il completamento dai dati esistenti
/// (1 traccia, wishlist, profilo) + un flag "ha esplorato". Si auto-nasconde
/// quando è tutto fatto o quando l'utente la chiude.
class OnboardingChecklistService {
  static const _kDismissed = 'onboard_checklist_dismissed';
  static const _kExplored = 'onboard_explored';

  final FirebaseFirestore _fs;
  final FirebaseAuth _auth;

  /// Istanze iniettabili per i test (default = singleton in produzione).
  OnboardingChecklistService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _fs = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Segna che l'utente ha aperto Discover (chiamato da DiscoverPage).
  Future<void> markExplored() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_kExplored) ?? false)) {
      await prefs.setBool(_kExplored, true);
    }
  }

  /// Chiude definitivamente la checklist.
  Future<void> dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDismissed, true);
  }

  /// Stato corrente, oppure null se la checklist va NASCOSTA (chiusa
  /// dall'utente o tutti i passi completati). Non lancia mai: in caso di
  /// errore ritorna null per non bloccare l'home.
  Future<OnboardingChecklistState?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kDismissed) ?? false) return null;

      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;
      final fs = _fs;

      // 1) almeno una traccia? (read leggera: solo metadati, cap a 5).
      // Chi ha già >=5 tracce è "attivato": la checklist non gli serve più,
      // la nascondiamo per non infastidire gli utenti esistenti.
      // NB PERF: "leggera" solo nel numero di doc — i doc traccia legacy
      // arrivano INTERI (points GPS inline) via wire. Misurato con PerfTrace.
      final tracks = await PerfTrace.track(
        'checklist.tracksProbe',
        () => fs
            .collection('users')
            .doc(uid)
            .collection('tracks')
            .limit(5)
            .get(),
        describe: (s) => '${s.docs.length} doc, fromCache=${s.metadata.isFromCache}',
      );
      if (tracks.docs.length >= 5) return null;
      final recorded = tracks.docs.isNotEmpty;

      // 2+3) profilo e wishlist vivono nello STESSO doc → una sola read.
      final profileSnap =
          await fs.collection('user_profiles').doc(uid).get();
      final p = profileSnap.data() ?? const <String, dynamic>{};
      final avatar = (p['avatarUrl'] ?? p['photoURL'])?.toString() ?? '';
      final bio = (p['bio'] ?? '').toString().trim();
      final profileDone = avatar.isNotEmpty || bio.isNotEmpty;
      final wishlist = p['wishlist'];
      final favorited = wishlist is List && wishlist.isNotEmpty;

      // 4) ha esplorato? (flag locale)
      final explored = prefs.getBool(_kExplored) ?? false;

      final state = OnboardingChecklistState(
        recorded: recorded,
        explored: explored,
        favorited: favorited,
        profileDone: profileDone,
      );
      return state.allDone ? null : state;
    } catch (e) {
      debugPrint('[OnboardingChecklist] load error: $e');
      return null;
    }
  }
}
