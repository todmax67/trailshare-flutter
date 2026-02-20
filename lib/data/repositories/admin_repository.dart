import 'package:cloud_firestore/cloud_firestore.dart';

// UID Super Admin
const String superAdminUid = 'g4uPvD3VQcMiYb4dDTWs7kJgm4u1';

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

  /// Verifica se l'utente corrente è super admin
  static bool isSuperAdmin(String? uid) => uid == superAdminUid;

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
      print('[Admin] Errore caricamento statistiche: $e');
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
      print('[Admin] Errore caricamento utenti: $e');
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
          .endAt([query.toLowerCase() + '\uf8ff'])
          .limit(20)
          .get();

      return snapshot.docs.map((doc) => AppUser.fromFirestore(doc)).toList();
    } catch (e) {
      print('[Admin] Errore ricerca utenti: $e');
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
      print('[Admin] Errore dettaglio utente: $e');
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
      print('[Admin] Utente $uid ${suspend ? "sospeso" : "riattivato"}');
      return true;
    } catch (e) {
      print('[Admin] Errore sospensione utente: $e');
      return false;
    }
  }

  /// Elimina traccia community
  Future<bool> deleteCommunityTrack(String trackId) async {
    try {
      await _firestore.collection('community_tracks').doc(trackId).delete();
      print('[Admin] Traccia community eliminata: $trackId');
      return true;
    } catch (e) {
      print('[Admin] Errore eliminazione traccia: $e');
      return false;
    }
  }

  /// Elimina gruppo
  Future<bool> deleteGroup(String groupId) async {
    try {
      await _firestore.collection('groups').doc(groupId).delete();
      print('[Admin] Gruppo eliminato: $groupId');
      return true;
    } catch (e) {
      print('[Admin] Errore eliminazione gruppo: $e');
      return false;
    }
  }
}
