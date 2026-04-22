import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/italian_regions.dart';

/// Servizio per leggere/scrivere la regione associata al profilo utente.
///
/// La regione è memorizzata in `user_profiles/{uid}.region` come `code`
/// (es. `lombardia`). È usata dalle classifiche regionali per filtrare
/// gli utenti e dal Discovery Carousel per suggerire di impostarla.
///
/// Il servizio è un singleton con cache in-memory, aggiornata al primo
/// accesso e dopo ogni setRegion.
class UserRegionService {
  UserRegionService._();
  static final UserRegionService _instance = UserRegionService._();
  factory UserRegionService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _cachedRegionCode;
  bool _loaded = false;

  /// Ritorna il code cached; può essere null se non settato o non ancora
  /// caricato. Vedi [load] per forzare il caricamento.
  String? get cachedRegionCode => _cachedRegionCode;

  /// Ritorna la regione (oggetto) cached o null se non settata.
  ItalianRegion? get cachedRegion =>
      ItalianRegions.byCode(_cachedRegionCode);

  /// True se l'utente ha una regione impostata nella cache locale.
  bool get hasRegionSet =>
      _loaded && _cachedRegionCode != null && _cachedRegionCode!.isNotEmpty;

  /// True se abbiamo completato almeno un [load] (anche se risultato è null).
  bool get isLoaded => _loaded;

  /// Legge il campo `region` dal profilo utente e lo cacha.
  Future<String?> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _cachedRegionCode = null;
      _loaded = true;
      return null;
    }
    try {
      final doc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();
      final code = doc.data()?['region']?.toString();
      _cachedRegionCode = (code != null && code.isNotEmpty) ? code : null;
      _loaded = true;
      debugPrint('[UserRegion] caricata regione: $_cachedRegionCode');
      return _cachedRegionCode;
    } catch (e) {
      debugPrint('[UserRegion] load error: $e');
      _loaded = true;
      return null;
    }
  }

  /// Salva la nuova regione sul profilo utente (merge).
  Future<bool> setRegion(String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _firestore.collection('user_profiles').doc(user.uid).set({
        'region': code,
        'regionSetAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _cachedRegionCode = code;
      _loaded = true;
      debugPrint('[UserRegion] salvata regione: $code');
      return true;
    } catch (e) {
      debugPrint('[UserRegion] set error: $e');
      return false;
    }
  }
}
