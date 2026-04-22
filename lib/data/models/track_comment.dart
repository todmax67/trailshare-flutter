import 'package:cloud_firestore/cloud_firestore.dart';

/// Commento di un utente su una [CommunityTrack].
///
/// Storage: sub-collezione `published_tracks/{trackId}/comments/{commentId}`.
/// I campi `userId`, `username`, `avatarUrl` sono denormalizzati per
/// evitare un join di lettura su `user_profiles` per ogni commento.
class TrackComment {
  final String id;
  final String userId;
  final String username;
  final String? avatarUrl;
  final String text;
  final DateTime createdAt;

  const TrackComment({
    required this.id,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'username': username,
      if (avatarUrl != null && avatarUrl!.isNotEmpty) 'avatarUrl': avatarUrl,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory TrackComment.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return TrackComment(
      id: id,
      userId: data['userId']?.toString() ?? '',
      username: data['username']?.toString() ?? 'Utente',
      avatarUrl: data['avatarUrl']?.toString(),
      text: data['text']?.toString() ?? '',
      createdAt: parseTs(data['createdAt']),
    );
  }
}
