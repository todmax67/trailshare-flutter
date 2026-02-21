import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository per gestire il sistema Follow/Followers
class FollowRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Verifica se l'utente corrente segue un altro utente
  Future<bool> isFollowing(String targetUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();

      if (!doc.exists) return false;

      final following = List<String>.from(doc.data()?['following'] ?? []);
      return following.contains(targetUserId);
    } catch (e) {
      print('[FollowRepo] Errore isFollowing: $e');
      return false;
    }
  }

  /// Toggle follow/unfollow (con transazione atomica)
  Future<FollowResult> toggleFollow(String targetUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return FollowResult(
        success: false,
        error: 'Devi effettuare il login',
      );
    }

    if (user.uid == targetUserId) {
      return FollowResult(
        success: false,
        error: 'Non puoi seguire te stesso',
      );
    }

    try {
      final currentUserRef = _firestore.collection('user_profiles').doc(user.uid);
      final targetUserRef = _firestore.collection('user_profiles').doc(targetUserId);

      bool isNowFollowing = false;

      await _firestore.runTransaction((transaction) async {
        final currentUserDoc = await transaction.get(currentUserRef);
        final targetUserDoc = await transaction.get(targetUserRef);

        // Crea profilo se non esiste
        if (!currentUserDoc.exists) {
          transaction.set(currentUserRef, {'following': [], 'followers': []}, SetOptions(merge: true));
        }
        if (!targetUserDoc.exists) {
          transaction.set(targetUserRef, {'following': [], 'followers': []}, SetOptions(merge: true));
        }

        final currentUserData = currentUserDoc.data() ?? {};
        final isCurrentlyFollowing = (currentUserData['following'] as List? ?? []).contains(targetUserId);

        if (isCurrentlyFollowing) {
          // Unfollow
          transaction.update(currentUserRef, {
            'following': FieldValue.arrayRemove([targetUserId]),
          });
          transaction.update(targetUserRef, {
            'followers': FieldValue.arrayRemove([user.uid]),
          });
          isNowFollowing = false;
        } else {
          // Follow
          transaction.update(currentUserRef, {
            'following': FieldValue.arrayUnion([targetUserId]),
          });
          transaction.update(targetUserRef, {
            'followers': FieldValue.arrayUnion([user.uid]),
          });
          isNowFollowing = true;
        }
      });

      return FollowResult(
        success: true,
        isNowFollowing: isNowFollowing,
        message: isNowFollowing ? 'Ora segui questo utente' : 'Hai smesso di seguire',
      );
    } catch (e) {
      print('[FollowRepo] Errore toggleFollow: $e');
      return FollowResult(
        success: false,
        error: 'Errore durante l\'operazione. Riprova.',
      );
    }
  }

  /// Ottieni lista follower di un utente
  Future<List<String>> getFollowers(String userId) async {
    try {
      final doc = await _firestore.collection('user_profiles').doc(userId).get();
      if (!doc.exists) return [];
      return List<String>.from(doc.data()?['followers'] ?? []);
    } catch (e) {
      print('[FollowRepo] Errore getFollowers: $e');
      return [];
    }
  }

  /// Ottieni lista following di un utente
  Future<List<String>> getFollowing(String userId) async {
    try {
      final doc = await _firestore.collection('user_profiles').doc(userId).get();
      if (!doc.exists) return [];
      return List<String>.from(doc.data()?['following'] ?? []);
    } catch (e) {
      print('[FollowRepo] Errore getFollowing: $e');
      return [];
    }
  }

  /// Ottieni conteggi followers e following
  Future<FollowCounts> getFollowCounts(String userId) async {
    try {
      final doc = await _firestore.collection('user_profiles').doc(userId).get();
      if (!doc.exists) return const FollowCounts(followers: 0, following: 0);

      final data = doc.data()!;
      return FollowCounts(
        followers: (data['followers'] as List?)?.length ?? 0,
        following: (data['following'] as List?)?.length ?? 0,
      );
    } catch (e) {
      print('[FollowRepo] Errore getFollowCounts: $e');
      return const FollowCounts(followers: 0, following: 0);
    }
  }

  /// Ottieni profili degli utenti da una lista di ID
  Future<List<UserProfile>> getUserProfiles(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    try {
      // Firestore limita whereIn a 30 elementi
      final List<UserProfile> profiles = [];
      
      for (int i = 0; i < userIds.length; i += 30) {
        final batchIds = userIds.skip(i).take(30).toList();
        
        final snapshot = await _firestore
            .collection('user_profiles')
            .where(FieldPath.documentId, whereIn: batchIds)
            .get();

        for (final doc in snapshot.docs) {
          profiles.add(UserProfile.fromFirestore(doc));
        }
      }

      return profiles;
    } catch (e) {
      print('[FollowRepo] Errore getUserProfiles: $e');
      return [];
    }
  }

  /// Ottieni followers con profili completi
  Future<List<UserProfile>> getFollowersWithProfiles(String userId) async {
    final followerIds = await getFollowers(userId);
    return getUserProfiles(followerIds);
  }

  /// Ottieni following con profili completi
  Future<List<UserProfile>> getFollowingWithProfiles(String userId) async {
    final followingIds = await getFollowing(userId);
    return getUserProfiles(followingIds);
  }

  /// Cerca utenti per username (prefix search)
  Future<List<UserProfile>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];

    final q = query.trim().toLowerCase();
    
    try {
      // Ricerca per username (prefix match)
      final snapshot = await _firestore
          .collection('user_profiles')
          .orderBy('username')
          .startAt([q])
          .endAt([q + '\uf8ff'])
          .limit(20)
          .get();

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      return snapshot.docs
          .where((doc) => doc.id != currentUserId) // Escludi te stesso
          .map((doc) => UserProfile.fromFirestore(doc))
          .where((u) => u.username != 'Utente') // Escludi senza username
          .toList();
    } catch (e) {
      print('[FollowRepo] Errore searchUsers: $e');
      return [];
    }
  }

  /// Utenti suggeriti (attivi di recente, non già seguiti)
  Future<List<UserProfile>> getSuggestedUsers({int limit = 15}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      // Ottieni lista following attuale
      final myDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final following = List<String>.from(myDoc.data()?['following'] ?? []);

      // Carica utenti recenti (con lastActive o createdAt)
      final snapshot = await _firestore
          .collection('user_profiles')
          .orderBy('lastActive', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .where((doc) => doc.id != user.uid) // Escludi te stesso
          .where((doc) => !following.contains(doc.id)) // Escludi già seguiti
          .map((doc) => UserProfile.fromFirestore(doc))
          .where((u) => u.username != 'Utente') // Escludi senza username
          .take(limit)
          .toList();
    } catch (e) {
      print('[FollowRepo] Errore suggeriti: $e');
      
      // Fallback: carica per username
      try {
        final snapshot = await _firestore
            .collection('user_profiles')
            .orderBy('username')
            .limit(50)
            .get();

        final following = <String>[];
        try {
          final myDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
          following.addAll(List<String>.from(myDoc.data()?['following'] ?? []));
        } catch (_) {}

        return snapshot.docs
            .where((doc) => doc.id != user.uid)
            .where((doc) => !following.contains(doc.id))
            .map((doc) => UserProfile.fromFirestore(doc))
            .where((u) => u.username != 'Utente')
            .take(limit)
            .toList();
      } catch (e2) {
        print('[FollowRepo] Errore fallback suggeriti: $e2');
        return [];
      }
    }
  }

  /// Stream per conteggi in tempo reale
  Stream<FollowCounts> watchFollowCounts(String userId) {
    return _firestore
        .collection('user_profiles')
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return const FollowCounts(followers: 0, following: 0);
      final data = doc.data()!;
      return FollowCounts(
        followers: (data['followers'] as List?)?.length ?? 0,
        following: (data['following'] as List?)?.length ?? 0,
      );
    });
  }
}

/// Risultato operazione follow
class FollowResult {
  final bool success;
  final bool? isNowFollowing;
  final String? message;
  final String? error;

  const FollowResult({
    required this.success,
    this.isNowFollowing,
    this.message,
    this.error,
  });
}

/// Conteggi followers/following
class FollowCounts {
  final int followers;
  final int following;

  const FollowCounts({
    required this.followers,
    required this.following,
  });
}

/// Profilo utente semplificato
class UserProfile {
  final String id;
  final String username;
  final String? avatarUrl;
  final String? bio;
  final int level;
  final int xp;

  const UserProfile({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.bio,
    this.level = 1,
    this.xp = 0,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      return UserProfile(id: doc.id, username: 'Utente');
    }

    return UserProfile(
      id: doc.id,
      username: data['username'] ?? data['displayName'] ?? 'Utente',
      avatarUrl: data['avatarUrl'] ?? data['photoURL'],
      bio: data['bio'],
      level: data['level'] ?? 1,
      xp: data['xp'] ?? 0,
    );
  }

  /// Iniziale per avatar placeholder
  String get initial => username.isNotEmpty ? username[0].toUpperCase() : '?';
}
