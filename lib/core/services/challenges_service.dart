import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Servizio per la gestione delle sfide
class ChallengesService {
  static final ChallengesService _instance = ChallengesService._internal();
  factory ChallengesService() => _instance;
  ChallengesService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Tipi di sfida disponibili
  static const String TYPE_DISTANCE = 'DISTANCE_TOTAL';
  static const String TYPE_ELEVATION = 'ELEVATION_TOTAL';
  static const String TYPE_TRACKS = 'TRACKS_COUNT';

  /// Ottiene le sfide attive
  Future<List<Challenge>> getActiveChallenges() async {
    try {
      final now = DateTime.now();
      
      final snapshot = await _firestore
          .collection('challenges')
          .where('endDate', isGreaterThan: Timestamp.fromDate(now))
          .where('isActive', isEqualTo: true)
          .orderBy('endDate')
          .limit(20)
          .get();

      return snapshot.docs.map((doc) {
        return Challenge.fromFirestore(doc);
      }).toList();
    } catch (e) {
      print('[Challenges] Errore caricamento sfide: $e');
      return [];
    }
  }

  /// Ottiene le sfide a cui l'utente partecipa
  Future<List<Challenge>> getMyChallenges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection('challenges')
          .where('participantIds', arrayContains: user.uid)
          .where('isActive', isEqualTo: true)
          .orderBy('endDate')
          .get();

      return snapshot.docs.map((doc) => Challenge.fromFirestore(doc)).toList();
    } catch (e) {
      print('[Challenges] Errore caricamento mie sfide: $e');
      return [];
    }
  }

  /// Verifica se l'utente partecipa a una sfida
  Future<bool> isParticipating(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore
          .collection('challenges')
          .doc(challengeId)
          .collection('participants')
          .doc(user.uid)
          .get();

      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Ottiene il progresso dell'utente in una sfida
  Future<double> getUserProgress(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    try {
      final doc = await _firestore
          .collection('challenges')
          .doc(challengeId)
          .collection('participants')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        return (doc.data()?['progress'] as num?)?.toDouble() ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// Partecipa a una sfida
  Future<bool> joinChallenge(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final batch = _firestore.batch();

      // Aggiungi partecipante
      final participantRef = _firestore
          .collection('challenges')
          .doc(challengeId)
          .collection('participants')
          .doc(user.uid);

      batch.set(participantRef, {
        'joinedAt': FieldValue.serverTimestamp(),
        'progress': 0,
        'userId': user.uid,
        'displayName': user.displayName ?? 'Utente',
      });

      // Aggiorna contatore e array partecipanti
      final challengeRef = _firestore.collection('challenges').doc(challengeId);
      batch.update(challengeRef, {
        'participantCount': FieldValue.increment(1),
        'participantIds': FieldValue.arrayUnion([user.uid]),
      });

      await batch.commit();
      return true;
    } catch (e) {
      print('[Challenges] Errore partecipazione: $e');
      return false;
    }
  }

  /// Abbandona una sfida
  Future<bool> leaveChallenge(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final batch = _firestore.batch();

      // Rimuovi partecipante
      final participantRef = _firestore
          .collection('challenges')
          .doc(challengeId)
          .collection('participants')
          .doc(user.uid);

      batch.delete(participantRef);

      // Aggiorna contatore
      final challengeRef = _firestore.collection('challenges').doc(challengeId);
      batch.update(challengeRef, {
        'participantCount': FieldValue.increment(-1),
        'participantIds': FieldValue.arrayRemove([user.uid]),
      });

      await batch.commit();
      return true;
    } catch (e) {
      print('[Challenges] Errore abbandono: $e');
      return false;
    }
  }

  /// Crea una nuova sfida
  Future<String?> createChallenge({
    required String title,
    required String description,
    required String type,
    required double goal,
    required DateTime endDate,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final docRef = await _firestore.collection('challenges').add({
        'title': title,
        'description': description,
        'type': type,
        'goal': goal,
        'endDate': Timestamp.fromDate(endDate),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'creatorName': user.displayName ?? 'Utente',
        'isActive': true,
        'participantCount': 0,
        'participantIds': [],
      });

      return docRef.id;
    } catch (e) {
      print('[Challenges] Errore creazione: $e');
      return null;
    }
  }

  /// Aggiorna il progresso dell'utente (chiamato dopo ogni traccia)
  Future<void> updateProgress({
    required double distanceMeters,
    required double elevationGain,
    required int tracksCount,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Ottieni sfide attive a cui l'utente partecipa
      final challenges = await getMyChallenges();

      for (final challenge in challenges) {
        double increment = 0;

        switch (challenge.type) {
          case TYPE_DISTANCE:
            increment = distanceMeters;
            break;
          case TYPE_ELEVATION:
            increment = elevationGain;
            break;
          case TYPE_TRACKS:
            increment = tracksCount.toDouble();
            break;
        }

        if (increment > 0) {
          await _firestore
              .collection('challenges')
              .doc(challenge.id)
              .collection('participants')
              .doc(user.uid)
              .update({
            'progress': FieldValue.increment(increment),
            'lastUpdate': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      print('[Challenges] Errore aggiornamento progresso: $e');
    }
  }

  /// Ottiene la classifica di una sfida
  Future<List<ChallengeParticipant>> getLeaderboard(String challengeId, {int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('challenges')
          .doc(challengeId)
          .collection('participants')
          .orderBy('progress', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return ChallengeParticipant(
          userId: doc.id,
          displayName: data['displayName'] ?? 'Utente',
          progress: (data['progress'] as num?)?.toDouble() ?? 0,
          joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
        );
      }).toList();
    } catch (e) {
      print('[Challenges] Errore classifica: $e');
      return [];
    }
  }
}

/// Modello Sfida
class Challenge {
  final String id;
  final String title;
  final String description;
  final String type;
  final double goal;
  final DateTime endDate;
  final DateTime? createdAt;
  final String createdBy;
  final String creatorName;
  final bool isActive;
  final int participantCount;

  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.goal,
    required this.endDate,
    this.createdAt,
    required this.createdBy,
    required this.creatorName,
    required this.isActive,
    required this.participantCount,
  });

  factory Challenge.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Challenge(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      type: data['type'] ?? '',
      goal: (data['goal'] as num?)?.toDouble() ?? 0,
      endDate: (data['endDate'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? '',
      creatorName: data['creatorName'] ?? 'Utente',
      isActive: data['isActive'] ?? true,
      participantCount: (data['participantCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Icona in base al tipo
  String get icon {
    switch (type) {
      case ChallengesService.TYPE_DISTANCE:
        return '🏃';
      case ChallengesService.TYPE_ELEVATION:
        return '⛰️';
      case ChallengesService.TYPE_TRACKS:
        return '📍';
      default:
        return '🏆';
    }
  }

  /// Unità di misura
  String get unit {
    switch (type) {
      case ChallengesService.TYPE_DISTANCE:
        return 'km';
      case ChallengesService.TYPE_ELEVATION:
        return 'm';
      case ChallengesService.TYPE_TRACKS:
        return 'tracce';
      default:
        return '';
    }
  }

  /// Goal formattato
  String get formattedGoal {
    switch (type) {
      case ChallengesService.TYPE_DISTANCE:
        return '${(goal / 1000).toStringAsFixed(0)} km';
      case ChallengesService.TYPE_ELEVATION:
        return '${goal.toStringAsFixed(0)} m';
      case ChallengesService.TYPE_TRACKS:
        return '${goal.toStringAsFixed(0)} tracce';
      default:
        return goal.toString();
    }
  }

  /// Formatta progresso
  String formatProgress(double progress) {
    switch (type) {
      case ChallengesService.TYPE_DISTANCE:
        return '${(progress / 1000).toStringAsFixed(1)} km';
      case ChallengesService.TYPE_ELEVATION:
        return '${progress.toStringAsFixed(0)} m';
      case ChallengesService.TYPE_TRACKS:
        return '${progress.toStringAsFixed(0)} tracce';
      default:
        return progress.toString();
    }
  }

  /// Giorni rimanenti
  int get daysLeft {
    return endDate.difference(DateTime.now()).inDays;
  }

  /// Scaduta
  bool get isExpired => DateTime.now().isAfter(endDate);
}

/// Modello Partecipante
class ChallengeParticipant {
  final String userId;
  final String displayName;
  final double progress;
  final DateTime? joinedAt;

  const ChallengeParticipant({
    required this.userId,
    required this.displayName,
    required this.progress,
    this.joinedAt,
  });
}
