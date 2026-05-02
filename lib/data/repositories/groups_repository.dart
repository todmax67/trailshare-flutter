import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:math';

// ═══════════════════════════════════════════════════════════════════════════
// MODELLI
// ═══════════════════════════════════════════════════════════════════════════

class Group {
  final String id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String? coverUrl;
  /// Colore brand custom in formato ARGB int (0xFFRRGGBB). Sostituisce
  /// l'arancio TrailShare negli accenti UI delle viste interne al
  /// gruppo (TabBar, badge, ecc.). null = usa default AppColors.primary.
  final int? brandColor;
  final String createdBy;
  final DateTime createdAt;
  final List<String> memberIds;
  final int memberCount;
  final String visibility; // 'public' | 'private' | 'secret'
  final String? inviteCode;

  /// Marca il gruppo come **Business** (B2B): abilita il logo
  /// personalizzato (avatarUrl), il badge "verificato" accanto al
  /// nome e — in futuro — cover image, brand color, statistiche
  /// aggregate.
  ///
  /// Settato manualmente dal super admin per i primi clienti gratis.
  /// Quando lanceremo il piano Business sara' autoset al pagamento.
  final bool isBusinessGroup;

  bool get isPublic => visibility == 'public';
  bool get isPrivate => visibility == 'private';
  bool get isSecret => visibility == 'secret';
  bool get isDiscoverable => visibility != 'secret';

  /// Vero quando il gruppo ha una rappresentazione visuale custom
  /// (logo caricato dall'admin, possibile solo per gruppi Business).
  bool get hasCustomLogo => isBusinessGroup && avatarUrl != null && avatarUrl!.isNotEmpty;

  /// Vero quando il gruppo ha una cover image 16:9 caricata
  /// (banner mostrato in cima al tab Info, gruppi Business).
  bool get hasCustomCover => isBusinessGroup && coverUrl != null && coverUrl!.isNotEmpty;

  const Group({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    this.coverUrl,
    this.brandColor,
    required this.createdBy,
    required this.createdAt,
    required this.memberIds,
    this.memberCount = 0,
    this.visibility = 'secret',
    this.inviteCode,
    this.isBusinessGroup = false,
  });

  factory Group.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Group(
      id: doc.id,
      name: data['name'] ?? 'Gruppo',
      description: data['description'],
      avatarUrl: data['avatarUrl'],
      coverUrl: data['coverUrl'],
      brandColor: (data['brandColor'] as num?)?.toInt(),
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      memberIds: List<String>.from(data['memberIds'] ?? []),
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      visibility: _parseVisibility(data),
      inviteCode: data['inviteCode'],
      isBusinessGroup: data['isBusinessGroup'] == true,
    );
  }
}
/// Helper retrocompatibilità: vecchi gruppi hanno isPublic, nuovi hanno visibility
String _parseVisibility(Map<String, dynamic> data) {
  if (data['visibility'] != null) return data['visibility'];
  if (data['isPublic'] == true) return 'public';
  return 'secret';
}

class GroupMember {
  final String userId;
  final String username;
  final String? avatarUrl;
  final String role; // 'admin' | 'member'
  final DateTime joinedAt;

  const GroupMember({
    required this.userId,
    required this.username,
    this.avatarUrl,
    this.role = 'member',
    required this.joinedAt,
  });

  factory GroupMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GroupMember(
      userId: doc.id,
      username: data['username'] ?? 'Utente',
      avatarUrl: data['avatarUrl'],
      role: data['role'] ?? 'member',
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  bool get isAdmin => role == 'admin';
}

class GroupEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime date;
  final GeoPoint? meetingPoint;
  final String? meetingPointName;
  final String? trailId;
  final String? trailName;
  final String createdBy;
  final String createdByName;
  final List<String> participants;
  final int? maxParticipants;
  final String status; // 'upcoming' | 'completed' | 'cancelled'
  final String? difficulty;
  final double? estimatedDistance;
  final double? estimatedElevation;
  final String? notes;
  final String? coverImageUrl;

  const GroupEvent({
    required this.id,
    required this.title,
    this.description,
    required this.date,
    this.meetingPoint,
    this.meetingPointName,
    this.trailId,
    this.trailName,
    required this.createdBy,
    this.createdByName = '',
    this.participants = const [],
    this.maxParticipants,
    this.status = 'upcoming',
    this.difficulty,
    this.estimatedDistance,
    this.estimatedElevation,
    this.notes,
    this.coverImageUrl,
  });

  factory GroupEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GroupEvent(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'],
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      meetingPoint: data['meetingPoint'] as GeoPoint?,
      meetingPointName: data['meetingPointName'],
      trailId: data['trailId'],
      trailName: data['trailName'],
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
      participants: List<String>.from(data['participants'] ?? []),
      maxParticipants: (data['maxParticipants'] as num?)?.toInt(),
      status: data['status'] ?? 'upcoming',
      difficulty: data['difficulty'],
      estimatedDistance: (data['estimatedDistance'] as num?)?.toDouble(),
      estimatedElevation: (data['estimatedElevation'] as num?)?.toDouble(),
      notes: data['notes'],
      coverImageUrl: data['coverImageUrl'],
    );
  }

  bool get isFull => maxParticipants != null && participants.length >= maxParticipants!;
  bool get isUpcoming => status == 'upcoming' && date.isAfter(DateTime.now());
  bool get isPast => date.isBefore(DateTime.now());
}

class GroupChallenge {
  final String id;
  final String title;
  final String type; // 'distance' | 'elevation' | 'tracks' | 'streak'
  final double target;
  final DateTime startDate;
  final DateTime endDate;
  final String createdBy;
  final String createdByName;

  const GroupChallenge({
    required this.id,
    required this.title,
    required this.type,
    required this.target,
    required this.startDate,
    required this.endDate,
    required this.createdBy,
    this.createdByName = '',
  });

  factory GroupChallenge.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GroupChallenge(
      id: doc.id,
      title: data['title'] ?? '',
      type: data['type'] ?? 'distance',
      target: (data['target'] as num?)?.toDouble() ?? 0,
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
    );
  }

  bool get isActive => DateTime.now().isAfter(startDate) && DateTime.now().isBefore(endDate);
  bool get isCompleted => DateTime.now().isAfter(endDate);

  String get typeIcon {
    switch (type) {
      case 'distance': return '🏃';
      case 'elevation': return '⛰️';
      case 'tracks': return '🗺️';
      case 'streak': return '🔥';
      default: return '🏆';
    }
  }

  String get typeLabel {
    switch (type) {
      case 'distance': return 'Distanza';
      case 'elevation': return 'Dislivello';
      case 'tracks': return 'Tracce';
      case 'streak': return 'Giorni consecutivi';
      default: return type;
    }
  }

  String get targetFormatted {
    switch (type) {
      case 'distance': return '${(target / 1000).toStringAsFixed(1)} km';
      case 'elevation': return '${target.toStringAsFixed(0)} m';
      case 'tracks': return '${target.toStringAsFixed(0)} tracce';
      case 'streak': return '${target.toStringAsFixed(0)} giorni';
      default: return target.toString();
    }
  }
}

class ChallengeStanding {
  final String userId;
  final String username;
  final double value;
  final DateTime lastUpdated;

  const ChallengeStanding({
    required this.userId,
    required this.username,
    required this.value,
    required this.lastUpdated,
  });

  factory ChallengeStanding.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ChallengeStanding(
      userId: doc.id,
      username: data['username'] ?? 'Utente',
      value: (data['value'] as num?)?.toDouble() ?? 0,
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Evento con info del gruppo di appartenenza (per vista cross-gruppo)
class GroupEventWithInfo {
  final GroupEvent event;
  final String groupId;
  final String groupName;
  final String visibility;

  bool get isPublic => visibility == 'public';

  const GroupEventWithInfo({
    required this.event,
    required this.groupId,
    required this.groupName,
    this.visibility = 'secret',
  });
}

/// Sfida con info del gruppo di appartenenza (per vista cross-gruppo)
class GroupChallengeWithInfo {
  final GroupChallenge challenge;
  final String groupId;
  final String groupName;

  const GroupChallengeWithInfo({
    required this.challenge,
    required this.groupId,
    required this.groupName,
  });
}

class GroupMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final DateTime timestamp;
  final String type; // 'text' | 'track' | 'event' | 'image'
  final String? referenceId;
  final String? imageUrl;

  const GroupMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.timestamp,
    this.type = 'text',
    this.referenceId,
    this.imageUrl,
  });

  factory GroupMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GroupMessage(
      id: doc.id,
      text: data['text'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Utente',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type: data['type'] ?? 'text',
      referenceId: data['referenceId'],
      imageUrl: data['imageUrl'],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REPOSITORY
// ═══════════════════════════════════════════════════════════════════════════

class GroupsRepository {
  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _groupsRef =>
      _firestore.collection('groups');

  DocumentReference<Map<String, dynamic>> _groupDoc(String groupId) =>
      _groupsRef.doc(groupId);

  /// Genera un codice invito univoco (6 caratteri alfanumerici maiuscoli)
  static String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Senza I,O,0,1 per evitare confusione
    final random = Random();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }    

  // ─────────────────────────────────────────────────────────────────────
  // CRUD GRUPPO
  // ─────────────────────────────────────────────────────────────────────

  /// Crea un nuovo gruppo
  Future<String?> createGroup({
    required String name,
    String? description,
    String visibility = 'secret',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      // Carica username
      final profileDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final username = profileDoc.data()?['username'] ?? user.displayName ?? 'Utente';
      final avatarUrl = profileDoc.data()?['avatarUrl'];

      final docRef = await _groupsRef.add({
        'name': name,
        'description': description,
        'avatarUrl': null,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'memberIds': [user.uid],
        'memberCount': 1,
        'visibility': visibility,
        'isPublic': visibility == 'public',
        'inviteCode': _generateInviteCode(),
      });

      // Aggiungi creatore come admin
      await docRef.collection('members').doc(user.uid).set({
        'username': username,
        'avatarUrl': avatarUrl,
        'role': 'admin',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[Groups] Gruppo creato: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('[Groups] Errore creazione: $e');
      return null;
    }
  }

  /// Carica gruppi dell'utente corrente
  Future<List<Group>> getMyGroups({bool forceServer = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      // Source.server forza Firestore a ignorare la cache locale e
      // rifetchare dal server. Utile dopo upload logo o cambio
      // isBusinessGroup, altrimenti la lista resta stale.
      final snapshot = await _groupsRef
          .where('memberIds', arrayContains: user.uid)
          .orderBy('createdAt', descending: true)
          .get(forceServer ? const GetOptions(source: Source.server) : null);

      return snapshot.docs.map((doc) => Group.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('[Groups] Errore caricamento gruppi: $e');
      return [];
    }
  }

  /// Carica gruppi pubblici a cui non sei già iscritto
  Future<List<Group>> getDiscoverableGroups() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      // Query 1: nuovi gruppi con visibility
      final snapshot1 = await _groupsRef
          .where('visibility', whereIn: ['public', 'private'])
          .limit(50)
          .get();

      // Query 2: vecchi gruppi con isPublic (retrocompatibilità)
      final snapshot2 = await _groupsRef
          .where('isPublic', isEqualTo: true)
          .limit(50)
          .get();

      // Merge e deduplica
      final allDocs = <String, QueryDocumentSnapshot>{};
      for (final doc in snapshot1.docs) allDocs[doc.id] = doc;
      for (final doc in snapshot2.docs) allDocs[doc.id] = doc;

      return allDocs.values
          .map((doc) => Group.fromFirestore(doc))
          .where((g) => !g.memberIds.contains(user.uid) && g.isDiscoverable)
          .toList();

    } catch (e) {
      debugPrint('[Groups] Errore caricamento gruppi pubblici: $e');
      return [];
    }
  }

  /// Carica dettaglio gruppo
  Future<Group?> getGroup(String groupId) async {
    try {
      final doc = await _groupDoc(groupId).get();
      if (!doc.exists) return null;
      return Group.fromFirestore(doc);
    } catch (e) {
      debugPrint('[Groups] Errore caricamento gruppo: $e');
      return null;
    }
  }

  /// Aggiorna nome e/o descrizione del gruppo
  Future<bool> updateGroup(String groupId, {String? name, String? description}) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;
      if (updates.isEmpty) return false;

      await _groupDoc(groupId).update(updates);
      debugPrint('[Groups] Gruppo $groupId aggiornato');
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore aggiornamento gruppo: $e');
      return false;
    }
  }

  /// Elimina gruppo (solo admin/creatore)
  Future<bool> deleteGroup(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final groupDoc = await _groupDoc(groupId).get();
      if (groupDoc.data()?['createdBy'] != user.uid) return false;

      await _groupDoc(groupId).delete();
      debugPrint('[Groups] Gruppo eliminato: $groupId');
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore eliminazione: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // MEMBRI
  // ─────────────────────────────────────────────────────────────────────

  /// Carica membri del gruppo
  Future<List<GroupMember>> getMembers(String groupId) async {
    try {
      final snapshot = await _groupDoc(groupId)
          .collection('members')
          .orderBy('joinedAt')
          .get();

      return snapshot.docs.map((doc) => GroupMember.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('[Groups] Errore caricamento membri: $e');
      return [];
    }
  }

  /// Unisciti al gruppo
  Future<bool> joinGroup(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final profileDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final username = profileDoc.data()?['username'] ?? user.displayName ?? 'Utente';
      final avatarUrl = profileDoc.data()?['avatarUrl'];

      await _firestore.runTransaction((transaction) async {
        transaction.set(
          _groupDoc(groupId).collection('members').doc(user.uid),
          {
            'username': username,
            'avatarUrl': avatarUrl,
            'role': 'member',
            'joinedAt': FieldValue.serverTimestamp(),
          },
        );

        transaction.update(_groupDoc(groupId), {
          'memberIds': FieldValue.arrayUnion([user.uid]),
          'memberCount': FieldValue.increment(1),
        });
      });

      debugPrint('[Groups] Utente ${user.uid} entrato in $groupId');
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore join: $e');
      return false;
    }
  }

  /// Esci dal gruppo
  Future<bool> leaveGroup(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      await _firestore.runTransaction((transaction) async {
        transaction.delete(
          _groupDoc(groupId).collection('members').doc(user.uid),
        );

        transaction.update(_groupDoc(groupId), {
          'memberIds': FieldValue.arrayRemove([user.uid]),
          'memberCount': FieldValue.increment(-1),
        });
      });

      debugPrint('[Groups] Utente ${user.uid} uscito da $groupId');
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore leave: $e');
      return false;
    }
  }

  /// Invita utente (per userId)
  Future<bool> addMember(String groupId, String targetUserId) async {
    try {
      final profileDoc = await _firestore.collection('user_profiles').doc(targetUserId).get();
      final username = profileDoc.data()?['username'] ?? 'Utente';
      final avatarUrl = profileDoc.data()?['avatarUrl'];

      await _firestore.runTransaction((transaction) async {
        transaction.set(
          _groupDoc(groupId).collection('members').doc(targetUserId),
          {
            'username': username,
            'avatarUrl': avatarUrl,
            'role': 'member',
            'joinedAt': FieldValue.serverTimestamp(),
          },
        );

        transaction.update(_groupDoc(groupId), {
          'memberIds': FieldValue.arrayUnion([targetUserId]),
          'memberCount': FieldValue.increment(1),
        });
      });

      return true;
    } catch (e) {
      debugPrint('[Groups] Errore aggiunta membro: $e');
      return false;
    }
  }

  /// Rimuovi membro (solo admin)
  Future<bool> removeMember(String groupId, String targetUserId) async {
    try {
      await _firestore.runTransaction((transaction) async {
        transaction.delete(
          _groupDoc(groupId).collection('members').doc(targetUserId),
        );

        transaction.update(_groupDoc(groupId), {
          'memberIds': FieldValue.arrayRemove([targetUserId]),
          'memberCount': FieldValue.increment(-1),
        });
      });

      return true;
    } catch (e) {
      debugPrint('[Groups] Errore rimozione membro: $e');
      return false;
    }
  }

  /// Verifica se l'utente è admin del gruppo
  Future<bool> isAdmin(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final memberDoc = await _groupDoc(groupId).collection('members').doc(user.uid).get();
      return memberDoc.data()?['role'] == 'admin';
    } catch (e) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // MESSAGGI / CHAT
  // ─────────────────────────────────────────────────────────────────────

  /// Stream messaggi in tempo reale
  Stream<List<GroupMessage>> messagesStream(String groupId, {int limit = 50}) {
    return _groupDoc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => GroupMessage.fromFirestore(doc)).toList());
  }

  /// Invia messaggio
  Future<bool> sendMessage(String groupId, String text, {String type = 'text', String? referenceId, String? imageUrl}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final profileDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final username = profileDoc.data()?['username'] ?? user.displayName ?? 'Utente';

      await _groupDoc(groupId).collection('messages').add({
        'text': text,
        'senderId': user.uid,
        'senderName': username,
        'timestamp': FieldValue.serverTimestamp(),
        'type': type,
        'referenceId': referenceId,
        'imageUrl': imageUrl,
      });

      return true;
    } catch (e) {
      debugPrint('[Groups] Errore invio messaggio: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // EVENTI
  // ─────────────────────────────────────────────────────────────────────

  /// Carica eventi del gruppo
  Future<List<GroupEvent>> getEvents(String groupId, {bool upcomingOnly = true}) async {
    try {
      var query = _groupDoc(groupId)
          .collection('events')
          .orderBy('date', descending: false);

      if (upcomingOnly) {
        query = query.where('date', isGreaterThanOrEqualTo: Timestamp.now());
      }

      final snapshot = await query.get();
      return snapshot.docs.map((doc) => GroupEvent.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('[Groups] Errore caricamento eventi: $e');
      return [];
    }
  }

  /// Crea evento
  Future<String?> createEvent(String groupId, {
    required String title,
    String? description,
    required DateTime date,
    GeoPoint? meetingPoint,
    String? meetingPointName,
    String? trailId,
    String? trailName,
    int? maxParticipants,
    String? difficulty,
    double? estimatedDistance,
    double? estimatedElevation,
    String? notes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final profileDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final username = profileDoc.data()?['username'] ?? 'Utente';

      final docRef = await _groupDoc(groupId).collection('events').add({
        'title': title,
        'description': description,
        'date': Timestamp.fromDate(date),
        'meetingPoint': meetingPoint,
        'meetingPointName': meetingPointName,
        'trailId': trailId,
        'trailName': trailName,
        'createdBy': user.uid,
        'createdByName': username,
        'participants': [user.uid],
        'maxParticipants': maxParticipants,
        'status': 'upcoming',
        'difficulty': difficulty,
        'estimatedDistance': estimatedDistance,
        'estimatedElevation': estimatedElevation,
        'notes': notes,
      });

      // Notifica nel chat
      await sendMessage(
        groupId,
        '📅 Nuovo evento: $title - ${_formatDate(date)}',
        type: 'event',
        referenceId: docRef.id,
      );

      return docRef.id;
    } catch (e) {
      debugPrint('[Groups] Errore creazione evento: $e');
      return null;
    }
  }

  /// Partecipa/ritirati da evento
  Future<bool> toggleEventParticipation(String groupId, String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final eventDoc = await _groupDoc(groupId).collection('events').doc(eventId).get();
      final participants = List<String>.from(eventDoc.data()?['participants'] ?? []);

      if (participants.contains(user.uid)) {
        await _groupDoc(groupId).collection('events').doc(eventId).update({
          'participants': FieldValue.arrayRemove([user.uid]),
        });
      } else {
        final maxP = (eventDoc.data()?['maxParticipants'] as num?)?.toInt();
        if (maxP != null && participants.length >= maxP) return false;

        await _groupDoc(groupId).collection('events').doc(eventId).update({
          'participants': FieldValue.arrayUnion([user.uid]),
        });
      }

      return true;
    } catch (e) {
      debugPrint('[Groups] Errore toggle partecipazione: $e');
      return false;
    }
  }

  /// Aggiorna evento
  Future<bool> updateEvent(String groupId, String eventId, Map<String, dynamic> data) async {
    try {
      await _groupDoc(groupId).collection('events').doc(eventId).update(data);
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore aggiornamento evento: $e');
      return false;
    }
  }

  /// Ottieni singolo evento
  Future<GroupEvent?> getEvent(String groupId, String eventId) async {
    try {
      final doc = await _groupDoc(groupId).collection('events').doc(eventId).get();
      if (!doc.exists) return null;
      return GroupEvent.fromFirestore(doc);
    } catch (e) {
      debugPrint('[Groups] Errore caricamento evento: $e');
      return null;
    }
  }

  /// Elimina evento
  Future<bool> deleteEvent(String groupId, String eventId) async {
    try {
      await _groupDoc(groupId).collection('events').doc(eventId).delete();
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore eliminazione evento: $e');
      return false;
    }
  }

  /// Aggiungi post/aggiornamento all'evento
  Future<bool> addEventPost(String groupId, String eventId, {
    required String text,
    String? imageUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final profileDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final username = profileDoc.data()?['username'] ?? 'Utente';

      await _groupDoc(groupId)
          .collection('events')
          .doc(eventId)
          .collection('posts')
          .add({
        'text': text,
        'imageUrl': imageUrl,
        'authorId': user.uid,
        'authorName': username,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore aggiunta post evento: $e');
      return false;
    }
  }

  /// Ottieni post dell'evento
  Future<List<Map<String, dynamic>>> getEventPosts(String groupId, String eventId) async {
    try {
      final snapshot = await _groupDoc(groupId)
          .collection('events')
          .doc(eventId)
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('[Groups] Errore caricamento post evento: $e');
      return [];
    }
  }

  /// Elimina post dell'evento
  Future<bool> deleteEventPost(String groupId, String eventId, String postId) async {
    try {
      await _groupDoc(groupId)
          .collection('events')
          .doc(eventId)
          .collection('posts')
          .doc(postId)
          .delete();
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore eliminazione post: $e');
      return false;
    }
  }

  /// Ottieni username di un partecipante
  Future<Map<String, String>> getParticipantNames(List<String> userIds) async {
    final names = <String, String>{};
    for (final uid in userIds) {
      try {
        final doc = await _firestore.collection('user_profiles').doc(uid).get();
        names[uid] = doc.data()?['username'] ?? 'Utente';
      } catch (_) {
        names[uid] = 'Utente';
      }
    }
    return names;
  }

  // ─────────────────────────────────────────────────────────────────────
  // SFIDE
  // ─────────────────────────────────────────────────────────────────────

  /// Carica sfide del gruppo
  Future<List<GroupChallenge>> getChallenges(String groupId, {bool activeOnly = true}) async {
    try {
      final snapshot = await _groupDoc(groupId)
          .collection('challenges')
          .orderBy('endDate', descending: false)
          .get();

      var challenges = snapshot.docs.map((doc) => GroupChallenge.fromFirestore(doc)).toList();

      if (activeOnly) {
        challenges = challenges.where((c) => c.isActive).toList();
      }

      return challenges;
    } catch (e) {
      debugPrint('[Groups] Errore caricamento sfide: $e');
      return [];
    }
  }

  /// Crea sfida
  Future<String?> createChallenge(String groupId, {
    required String title,
    required String type,
    required double target,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final profileDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final username = profileDoc.data()?['username'] ?? 'Utente';

      final docRef = await _groupDoc(groupId).collection('challenges').add({
        'title': title,
        'type': type,
        'target': target,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'createdBy': user.uid,
        'createdByName': username,
      });

      // Notifica nel chat
      final typeLabel = type == 'distance' ? 'km' : type == 'elevation' ? 'm dislivello' : 'tracce';
      await sendMessage(
        groupId,
        '🏆 Nuova sfida: $title - Obiettivo: ${type == 'distance' ? (target / 1000).toStringAsFixed(0) : target.toStringAsFixed(0)} $typeLabel',
        type: 'event',
        referenceId: docRef.id,
      );

      return docRef.id;
    } catch (e) {
      debugPrint('[Groups] Errore creazione sfida: $e');
      return null;
    }
  }

  /// Carica classifica sfida
  Future<List<ChallengeStanding>> getChallengeStandings(String groupId, String challengeId) async {
    try {
      final snapshot = await _groupDoc(groupId)
          .collection('challenges')
          .doc(challengeId)
          .collection('standings')
          .orderBy('value', descending: true)
          .get();

      return snapshot.docs.map((doc) => ChallengeStanding.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('[Groups] Errore caricamento classifica: $e');
      return [];
    }
  }

  /// Aggiorna punteggio utente nella sfida
  Future<void> updateChallengeStanding(String groupId, String challengeId, double value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final profileDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final username = profileDoc.data()?['username'] ?? 'Utente';

      await _groupDoc(groupId)
          .collection('challenges')
          .doc(challengeId)
          .collection('standings')
          .doc(user.uid)
          .set({
        'username': username,
        'value': value,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Groups] Errore aggiornamento standing: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // CODICE INVITO
  // ─────────────────────────────────────────────────────────────────────

  /// Cerca gruppo per codice invito
  Future<Group?> findGroupByInviteCode(String code) async {
    try {
      final snapshot = await _groupsRef
          .where('inviteCode', isEqualTo: code.toUpperCase().trim())
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return Group.fromFirestore(snapshot.docs.first);
    } catch (e) {
      debugPrint('[Groups] Errore ricerca codice invito: $e');
      return null;
    }
  }

  /// Unisciti a un gruppo tramite codice invito
  Future<Map<String, dynamic>> joinByInviteCode(String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'success': false, 'error': 'Non autenticato'};

    try {
      // Cerca il gruppo
      final group = await findGroupByInviteCode(code);
      if (group == null) {
        return {'success': false, 'error': 'Codice invito non valido'};
      }

      // Controlla se già membro
      if (group.memberIds.contains(user.uid)) {
        return {'success': false, 'error': 'Sei già membro di "${group.name}"', 'groupName': group.name};
      }

      // Unisciti
      final success = await joinGroup(group.id);
      if (success) {
        return {'success': true, 'groupId': group.id, 'groupName': group.name};
      } else {
        return {'success': false, 'error': 'Errore nell\'unirsi al gruppo'};
      }
    } catch (e) {
      debugPrint('[Groups] Errore join con codice: $e');
      return {'success': false, 'error': 'Errore: $e'};
    }
  }

  /// Rigenera codice invito (solo admin)
  Future<String?> regenerateInviteCode(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      // Verifica admin
      final isAdminUser = await isAdmin(groupId);
      if (!isAdminUser) return null;

      final newCode = _generateInviteCode();
      await _groupDoc(groupId).update({'inviteCode': newCode});
      debugPrint('[Groups] Codice invito rigenerato per $groupId: $newCode');
      return newCode;
    } catch (e) {
      debugPrint('[Groups] Errore rigenerazione codice: $e');
      return null;
    }
  }

  /// Assicura che un gruppo abbia un codice invito (per gruppi pre-esistenti)
  Future<String?> ensureInviteCode(String groupId) async {
    try {
      final doc = await _groupDoc(groupId).get();
      final data = doc.data();
      if (data == null) return null;

      final existingCode = data['inviteCode'] as String?;
      if (existingCode != null && existingCode.isNotEmpty) {
        return existingCode;
      }

      final newCode = _generateInviteCode();
      await _groupDoc(groupId).update({'inviteCode': newCode});
      debugPrint('[Groups] Codice invito generato per gruppo esistente $groupId: $newCode');
      return newCode;
    } catch (e) {
      debugPrint('[Groups] Errore ensureInviteCode: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // CROSS-GROUP QUERIES (per Community Page)
  // ─────────────────────────────────────────────────────────────────────

  /// Carica prossimi eventi da TUTTI i gruppi dell'utente
  Future<List<GroupEventWithInfo>> getAllUpcomingEvents() async {
    final groups = await getMyGroups();
    final allEvents = <GroupEventWithInfo>[];

    for (final group in groups) {
      try {
        final events = await getEvents(group.id, upcomingOnly: true);
        for (final event in events) {
          allEvents.add(GroupEventWithInfo(
            event: event,
            groupId: group.id,
            groupName: group.name,
            visibility: group.visibility,
          ));
        }
      } catch (e) {
        debugPrint('[Groups] Errore caricamento eventi per ${group.name}: $e');
      }
    }

    // Ordina per data (prossimi prima)
    allEvents.sort((a, b) => a.event.date.compareTo(b.event.date));
    return allEvents;
  }

  /// Carica sfide attive da TUTTI i gruppi dell'utente
  Future<List<GroupChallengeWithInfo>> getAllActiveChallenges() async {
    final groups = await getMyGroups();
    final allChallenges = <GroupChallengeWithInfo>[];

    for (final group in groups) {
      try {
        final challenges = await getChallenges(group.id, activeOnly: true);
        for (final challenge in challenges) {
          allChallenges.add(GroupChallengeWithInfo(
            challenge: challenge,
            groupId: group.id,
            groupName: group.name,
          ));
        }
      } catch (e) {
        debugPrint('[Groups] Errore caricamento sfide per ${group.name}: $e');
      }
    }

    return allChallenges;
  }

  /// Carica eventi pubblici (da gruppi pubblici a cui NON sei iscritto)
  Future<List<GroupEventWithInfo>> getPublicUpcomingEvents() async {
    final publicGroups = await getDiscoverableGroups();
    final allEvents = <GroupEventWithInfo>[];

    for (final group in publicGroups) {
      try {
        final events = await getEvents(group.id, upcomingOnly: true);
        for (final event in events) {
          allEvents.add(GroupEventWithInfo(
            event: event,
            groupId: group.id,
            groupName: group.name,
            visibility: group.visibility,
          ));
        }
      } catch (e) {
        debugPrint('[Groups] Errore caricamento eventi pubblici per ${group.name}: $e');
      }
    }

    allEvents.sort((a, b) => a.event.date.compareTo(b.event.date));
    return allEvents;
  }
  // ─────────────────────────────────────────────────────────────────────
  // RICHIESTE DI ACCESSO (per gruppi privati)
  // ─────────────────────────────────────────────────────────────────────

  /// Invia richiesta di accesso a un gruppo privato
  Future<bool> requestJoin(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final profileDoc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final username = profileDoc.data()?['username'] ?? 'Utente';
      final avatarUrl = profileDoc.data()?['avatarUrl'];

      await _groupDoc(groupId).collection('join_requests').doc(user.uid).set({
        'username': username,
        'avatarUrl': avatarUrl,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      debugPrint('[Groups] Richiesta accesso inviata per $groupId');
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore richiesta accesso: $e');
      return false;
    }
  }

  /// Controlla se l'utente ha già una richiesta pendente
  Future<bool> hasPendingRequest(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final doc = await _groupDoc(groupId)
          .collection('join_requests')
          .doc(user.uid)
          .get();
      return doc.exists && doc.data()?['status'] == 'pending';
    } catch (e) {
      return false;
    }
  }

  /// Carica richieste pendenti (per admin)
  Future<List<Map<String, dynamic>>> getPendingRequests(String groupId) async {
    try {
      final snapshot = await _groupDoc(groupId)
          .collection('join_requests')
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('[Groups] Errore caricamento richieste: $e');
      return [];
    }
  }

  /// Approva richiesta di accesso
  Future<bool> approveJoinRequest(String groupId, String userId) async {
    try {
      final profileDoc = await _firestore.collection('user_profiles').doc(userId).get();
      final username = profileDoc.data()?['username'] ?? 'Utente';
      final avatarUrl = profileDoc.data()?['avatarUrl'];

      await _groupDoc(groupId).update({
        'memberIds': FieldValue.arrayUnion([userId]),
        'memberCount': FieldValue.increment(1),
      });

      await _groupDoc(groupId).collection('members').doc(userId).set({
        'username': username,
        'avatarUrl': avatarUrl,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await _groupDoc(groupId).collection('join_requests').doc(userId).update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[Groups] Richiesta approvata: $userId in $groupId');
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore approvazione: $e');
      return false;
    }
  }

  /// Rifiuta richiesta di accesso
  Future<bool> rejectJoinRequest(String groupId, String userId) async {
    try {
      await _groupDoc(groupId).collection('join_requests').doc(userId).update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[Groups] Richiesta rifiutata: $userId in $groupId');
      return true;
    } catch (e) {
      debugPrint('[Groups] Errore rifiuto: $e');
      return false;
    }
  }

  /// Conteggio richieste pendenti (per badge admin)
  Future<int> getPendingRequestsCount(String groupId) async {
    try {
      final snapshot = await _groupDoc(groupId)
          .collection('join_requests')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }
  // ─────────────────────────────────────────────────────────────────────
  // UTILITY
  // ─────────────────────────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    final months = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];
    return '${date.day} ${months[date.month - 1]} ${date.year} alle ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUSINESS GROUPS (L1)
  // ─────────────────────────────────────────────────────────────────────

  /// Marca o smarca un gruppo come Business. Solo super admin.
  ///
  /// Quando isBusinessGroup=true, l'admin del gruppo sblocca il
  /// caricamento del logo personalizzato e il badge "verificato".
  /// In futuro saranno disponibili anche cover image e brand color.
  ///
  /// Per ora il flag viene settato manualmente da [AdminPanelPage].
  /// Quando lanceremo il piano Business sara' autoset al pagamento
  /// del primo IAP `trailshare_business_*`.
  Future<bool> setBusinessFlag(String groupId, bool value) async {
    try {
      await _groupDoc(groupId).update({
        'isBusinessGroup': value,
        // Pulisce avatarUrl se rimuoviamo lo status business: niente
        // logo se non sei piu' premium.
        if (!value) 'avatarUrl': FieldValue.delete(),
      });
      debugPrint('[GroupsRepo] setBusinessFlag $groupId = $value');
      return true;
    } catch (e) {
      debugPrint('[GroupsRepo] Errore setBusinessFlag: $e');
      return false;
    }
  }

  /// Carica un logo per il gruppo Business. Restituisce l'URL pubblico
  /// dell'immagine in Firebase Storage o null su errore.
  ///
  /// Path storage: `groups/{groupId}/logo.jpg`. Sostituisce qualsiasi
  /// logo precedente (overwrite). Il chiamante deve essere admin del
  /// gruppo E il gruppo deve avere isBusinessGroup=true (controllo lato
  /// UI prima di mostrare il pulsante upload).
  Future<String?> uploadGroupLogo(String groupId, File file) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('groups')
          .child(groupId)
          .child('logo.jpg');
      final task = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await task.ref.getDownloadURL();
      // Salva l'URL su Firestore cosi' la UI lo legge dal modello Group
      await _groupDoc(groupId).update({'avatarUrl': url});
      debugPrint('[GroupsRepo] Logo caricato per $groupId: $url');
      return url;
    } catch (e) {
      debugPrint('[GroupsRepo] Errore uploadGroupLogo: $e');
      return null;
    }
  }

  /// Imposta il colore brand custom del gruppo. Salvato come int ARGB
  /// (0xFFRRGGBB). Solo gruppi Business — controllo lato UI.
  Future<bool> setBrandColor(String groupId, int colorValue) async {
    try {
      await _groupDoc(groupId).update({'brandColor': colorValue});
      debugPrint('[GroupsRepo] BrandColor $groupId = ${colorValue.toRadixString(16)}');
      return true;
    } catch (e) {
      debugPrint('[GroupsRepo] Errore setBrandColor: $e');
      return false;
    }
  }

  /// Resetta il colore brand al default (rimuove il campo Firestore).
  Future<bool> clearBrandColor(String groupId) async {
    try {
      await _groupDoc(groupId).update({'brandColor': FieldValue.delete()});
      debugPrint('[GroupsRepo] BrandColor $groupId resettato');
      return true;
    } catch (e) {
      debugPrint('[GroupsRepo] Errore clearBrandColor: $e');
      return false;
    }
  }

  /// Carica una cover image 16:9 per il gruppo Business. Restituisce
  /// l'URL pubblico o null su errore.
  ///
  /// Path storage: `groups/{groupId}/cover.jpg`. Sostituisce qualsiasi
  /// cover precedente (overwrite). Stesso pattern di [uploadGroupLogo].
  Future<String?> uploadGroupCover(String groupId, File file) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('groups')
          .child(groupId)
          .child('cover.jpg');
      final task = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await task.ref.getDownloadURL();
      await _groupDoc(groupId).update({'coverUrl': url});
      debugPrint('[GroupsRepo] Cover caricata per $groupId: $url');
      return url;
    } catch (e) {
      debugPrint('[GroupsRepo] Errore uploadGroupCover: $e');
      return null;
    }
  }

  /// Rimuove la cover image del gruppo (sia Storage che il puntatore
  /// su Firestore). Idempotente.
  Future<bool> removeGroupCover(String groupId) async {
    try {
      await _groupDoc(groupId).update({
        'coverUrl': FieldValue.delete(),
      });
      try {
        await FirebaseStorage.instance
            .ref()
            .child('groups')
            .child(groupId)
            .child('cover.jpg')
            .delete();
      } catch (_) {
        // Ignora "object not found"
      }
      debugPrint('[GroupsRepo] Cover rimossa per $groupId');
      return true;
    } catch (e) {
      debugPrint('[GroupsRepo] Errore removeGroupCover: $e');
      return false;
    }
  }

  /// Rimuove il logo personalizzato del gruppo (sia Storage che il
  /// puntatore su Firestore). Idempotente.
  Future<bool> removeGroupLogo(String groupId) async {
    try {
      // Prima togli il puntatore Firestore (cosi' la UI non punta a
      // un'immagine in via di cancellazione)
      await _groupDoc(groupId).update({
        'avatarUrl': FieldValue.delete(),
      });
      // Poi cancella il file Storage (best-effort, se gia' assente OK)
      try {
        await FirebaseStorage.instance
            .ref()
            .child('groups')
            .child(groupId)
            .child('logo.jpg')
            .delete();
      } catch (_) {
        // Ignora "object not found"
      }
      debugPrint('[GroupsRepo] Logo rimosso per $groupId');
      return true;
    } catch (e) {
      debugPrint('[GroupsRepo] Errore removeGroupLogo: $e');
      return false;
    }
  }
}