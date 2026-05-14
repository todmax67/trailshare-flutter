import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Modello utente per admin panel
class AppUser {
  final String uid;
  final String username;
  final String? email;
  final String? avatarUrl;
  final String? bio;
  final DateTime? createdAt;
  final DateTime? lastActive;
  final int level;
  final int xp;
  final bool isSuspended;
  final bool isAdmin;

  const AppUser({
    required this.uid,
    required this.username,
    this.email,
    this.avatarUrl,
    this.bio,
    this.createdAt,
    this.lastActive,
    this.level = 1,
    this.xp = 0,
    this.isSuspended = false,
    this.isAdmin = false,
  });

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AppUser(
      uid: doc.id,
      username: data['username'] ?? 'Utente',
      email: data['email'],
      avatarUrl: data['avatarUrl'],
      bio: data['bio'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastActive: (data['lastActive'] as Timestamp?)?.toDate(),
      level: (data['level'] as num?)?.toInt() ?? 1,
      xp: (data['xp'] as num?)?.toInt() ?? 0,
      isSuspended: data['isSuspended'] ?? false,
      isAdmin: data['admin'] == true,
    );
  }
}

/// Statistiche globali dell'app
class AppStats {
  final int totalUsers;
  final int totalCommunityTracks;
  final int totalGroups;

  const AppStats({
    this.totalUsers = 0,
    this.totalCommunityTracks = 0,
    this.totalGroups = 0,
  });
}

class AdminRepository {
  final _firestore = FirebaseFirestore.instance;

  /// Cache del flag admin per evitare letture ripetute
  static bool? _cachedIsAdmin;
  static String? _cachedUid;

  /// Verifica se l'utente corrente è admin leggendo il campo 'admin' (boolean) da Firestore.
  /// Il risultato è cachato in memoria per la sessione corrente.
  static Future<bool> isCurrentUserAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    // Se l'UID è lo stesso, usa la cache
    if (_cachedUid == uid && _cachedIsAdmin != null) return _cachedIsAdmin!;

    // Provo prima Source.server (più aggiornata). Se va in timeout
    // o fallisce, fallback alla cache locale Firestore: meglio mostrare
    // un valore eventually-stale piuttosto che far sparire il pannello
    // admin all'utente legittimo per uno stutter di rete.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      _cachedIsAdmin = doc.data()?['admin'] == true;
      _cachedUid = uid;
      return _cachedIsAdmin!;
    } catch (e) {
      debugPrint('[Admin] Source.server fallito: $e — fallback cache');
    }
    // Fallback: leggi dalla cache Firestore (locale, può essere stale
    // ma normalmente è popolata da una sessione precedente).
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(uid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 4));
      final isAdmin = doc.data()?['admin'] == true;
      _cachedIsAdmin = isAdmin;
      _cachedUid = uid;
      return isAdmin;
    } catch (e) {
      debugPrint('[Admin] Cache fallback fallito: $e');
      // Ultimo resort: lascia false ma NON cachare — al prossimo
      // tentativo riproveremo Source.server.
      return false;
    }
  }

  /// Invalida la cache (da chiamare al logout)
  static void clearCache() {
    _cachedIsAdmin = null;
    _cachedUid = null;
  }

  // ─────────────────────────────────────────────────────────────────────
  // STATISTICHE
  // ─────────────────────────────────────────────────────────────────────

  Future<AppStats> getAppStats() async {
    try {
      final results = await Future.wait([
        _firestore.collection('user_profiles').count().get(),
        _firestore.collection('community_tracks').count().get(),
        _firestore.collection('groups').count().get(),
      ]);

      return AppStats(
        totalUsers: results[0].count ?? 0,
        totalCommunityTracks: results[1].count ?? 0,
        totalGroups: results[2].count ?? 0,
      );
    } catch (e) {
      debugPrint('[Admin] Errore caricamento statistiche: $e');
      return const AppStats();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // UTENTI
  // ─────────────────────────────────────────────────────────────────────

  /// Carica tutti gli utenti (paginati)
  Future<List<AppUser>> getUsers({
    int limit = 50,
    DocumentSnapshot? startAfter,
    String? searchQuery,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('user_profiles')
          //.orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      var users = snapshot.docs.map((doc) => AppUser.fromFirestore(doc)).toList();

      // Filtro locale per ricerca (Firestore non supporta LIKE)
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        users = users.where((u) =>
            u.username.toLowerCase().contains(q) ||
            (u.email?.toLowerCase().contains(q) ?? false)
        ).toList();
      }

      return users;
    } catch (e) {
      debugPrint('[Admin] Errore caricamento utenti: $e');
      return [];
    }
  }

  /// Cerca utenti per username
  Future<List<AppUser>> searchUsers(String query) async {
    if (query.isEmpty) return [];

    try {
      // Ricerca prefix su username
      final snapshot = await _firestore
          .collection('user_profiles')
          .orderBy('username')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff'])
          .limit(20)
          .get();

      return snapshot.docs.map((doc) => AppUser.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('[Admin] Errore ricerca utenti: $e');
      // Fallback: carica tutti e filtra
      return getUsers(searchQuery: query);
    }
  }

  /// Dettaglio utente con statistiche
  Future<Map<String, dynamic>> getUserDetails(String uid) async {
    try {
      final results = await Future.wait([
        _firestore.collection('user_profiles').doc(uid).get(),
        _firestore.collection('users').doc(uid).collection('tracks').count().get(),
        _firestore.collection('community_tracks').where('ownerId', isEqualTo: uid).count().get(),
        _firestore.collection('groups').where('memberIds', arrayContains: uid).get(),
      ]);

      final profileDoc = results[0] as DocumentSnapshot;
      final tracksCount = results[1] as AggregateQuerySnapshot;
      final communityCount = results[2] as AggregateQuerySnapshot;
      final groupsSnapshot = results[3] as QuerySnapshot;

      return {
        'user': profileDoc.exists ? AppUser.fromFirestore(profileDoc) : null,
        'tracksCount': tracksCount.count ?? 0,
        'communityTracksCount': communityCount.count ?? 0,
        'groups': groupsSnapshot.docs.map((d) => {
          'id': d.id,
          'name': (d.data() as Map<String, dynamic>?)?['name'] ?? 'Gruppo',
        }).toList(),
      };
    } catch (e) {
      debugPrint('[Admin] Errore dettaglio utente: $e');
      return {};
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // AZIONI ADMIN
  // ─────────────────────────────────────────────────────────────────────

  /// Sospendi/Riattiva utente
  Future<bool> toggleSuspendUser(String uid, bool suspend) async {
    try {
      await _firestore.collection('user_profiles').doc(uid).update({
        'isSuspended': suspend,
        'suspendedAt': suspend ? FieldValue.serverTimestamp() : FieldValue.delete(),
      });
      debugPrint('[Admin] Utente $uid ${suspend ? "sospeso" : "riattivato"}');
      return true;
    } catch (e) {
      debugPrint('[Admin] Errore sospensione utente: $e');
      return false;
    }
  }

  /// Elimina traccia community
  Future<bool> deleteCommunityTrack(String trackId) async {
    try {
      await _firestore.collection('community_tracks').doc(trackId).delete();
      debugPrint('[Admin] Traccia community eliminata: $trackId');
      return true;
    } catch (e) {
      debugPrint('[Admin] Errore eliminazione traccia: $e');
      return false;
    }
  }

  /// Elimina gruppo
  Future<bool> deleteGroup(String groupId) async {
    try {
      await _firestore.collection('groups').doc(groupId).delete();
      debugPrint('[Admin] Gruppo eliminato: $groupId');
      return true;
    } catch (e) {
      debugPrint('[Admin] Errore eliminazione gruppo: $e');
      return false;
    }
  }
}
