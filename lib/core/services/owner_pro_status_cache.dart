import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Cache in-memory dello stato Pro letto da `user_profiles/{uid}.isPro`.
///
/// Usato per derivare i cap dei gruppi dal Pro status dell'OWNER del
/// gruppo (non del current user). user_profiles è public-read, quindi
/// qualunque utente può leggere il flag.
///
/// Il flag è scritto SOLO da Cloud Function (admin SDK) — vedi
/// `updateProStatus` in functions/index.js. Le rules Firestore non
/// includono `isPro` nella whitelist update client-side, quindi non è
/// fakeabile.
///
/// Cache TTL 5 minuti per ridurre le letture quando l'utente naviga
/// tra gruppi diversi dello stesso owner.
class OwnerProStatusCache {
  OwnerProStatusCache._();
  static final OwnerProStatusCache _instance = OwnerProStatusCache._();
  factory OwnerProStatusCache() => _instance;

  static const Duration _ttl = Duration(minutes: 5);

  final Map<String, _Entry> _cache = {};

  /// Ritorna `true` se l'owner ha Consumer Pro attivo.
  /// Cache TTL 5min, su errore network ritorna `false` (cap restano
  /// applicati = comportamento conservativo).
  Future<bool> isOwnerPro(String ownerId) async {
    if (ownerId.isEmpty) return false;
    final cached = _cache[ownerId];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _ttl) {
      return cached.isPro;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(ownerId)
          .get();
      final isPro = doc.data()?['isPro'] == true;
      // Verifica scadenza locale per safety (mirror potrebbe essere stale
      // tra cancellazione abbonamento e prossimo run del Cloud Function).
      final expiresAtMs = (doc.data()?['proExpiresAtMs'] as num?)?.toInt();
      final stillActive = isPro &&
          (expiresAtMs == null ||
              expiresAtMs > DateTime.now().millisecondsSinceEpoch);
      _cache[ownerId] = _Entry(stillActive, DateTime.now());
      return stillActive;
    } catch (e) {
      debugPrint('[OwnerProStatusCache] read error for $ownerId: $e');
      return false;
    }
  }

  /// Versione SINCRONA: ritorna il flag se in cache (TTL valido), altrimenti
  /// `null`. Usato dal layer di rendering (es. `groupAccentColor`) per
  /// scegliere il valore senza bloccare il build. Pattern atteso:
  /// chi mostra il gruppo chiama prima [isOwnerPro] (await) per popolare
  /// la cache, poi i widget figli leggono via [isOwnerProCached] e
  /// renderizzano con il flag corretto.
  bool? isOwnerProCached(String ownerId) {
    if (ownerId.isEmpty) return false;
    final cached = _cache[ownerId];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.fetchedAt) >= _ttl) return null;
    return cached.isPro;
  }

  /// Pre-fetch batch: garantisce che la cache sia popolata per una lista
  /// di owner. Le richieste già in cache (TTL valido) vengono saltate.
  /// Usato da `groups_list_page` e simili per evitare flicker del branding
  /// al primo render di una lista di gruppi.
  Future<void> primeOwners(Iterable<String> ownerIds) async {
    final missing = ownerIds.toSet().where((id) {
      if (id.isEmpty) return false;
      final cached = _cache[id];
      if (cached == null) return true;
      return DateTime.now().difference(cached.fetchedAt) >= _ttl;
    }).toList();
    if (missing.isEmpty) return;
    // Limito a 10 query parallele per non saturare la rete sui device deboli.
    const chunkSize = 10;
    for (var i = 0; i < missing.length; i += chunkSize) {
      final chunk =
          missing.sublist(i, (i + chunkSize).clamp(0, missing.length));
      await Future.wait(chunk.map(isOwnerPro));
    }
  }

  /// Forza il refresh per un owner (es. dopo che l'owner stesso ha
  /// completato un purchase nello stesso device).
  void invalidate(String ownerId) {
    _cache.remove(ownerId);
  }

  void clear() => _cache.clear();
}

class _Entry {
  final bool isPro;
  final DateTime fetchedAt;
  _Entry(this.isPro, this.fetchedAt);
}
