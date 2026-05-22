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

  /// Epic 3.6 — mappa `username → uid` per le menzioni `@username` presenti
  /// in [text]. Risolto dal repository al salvataggio e usato dalla UI
  /// per rendere tappabili gli span (apre PublicProfilePage) e dalla
  /// Cloud Function `onCommentCreated` per inviare FCM ai menzionati.
  /// Vuota se nessuna menzione o se nessuno username è stato risolto.
  final Map<String, String> mentions;

  const TrackComment({
    required this.id,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.text,
    required this.createdAt,
    this.mentions = const {},
  });

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'username': username,
      if (avatarUrl != null && avatarUrl!.isNotEmpty) 'avatarUrl': avatarUrl,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      if (mentions.isNotEmpty) 'mentions': mentions,
    };
  }

  factory TrackComment.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    final rawMentions = data['mentions'];
    final Map<String, String> mentions = rawMentions is Map
        ? rawMentions.map((k, v) => MapEntry(k.toString(), v.toString()))
        : const {};

    return TrackComment(
      id: id,
      userId: data['userId']?.toString() ?? '',
      username: data['username']?.toString() ?? 'Utente',
      avatarUrl: data['avatarUrl']?.toString(),
      text: data['text']?.toString() ?? '',
      createdAt: parseTs(data['createdAt']),
      mentions: mentions,
    );
  }
}
