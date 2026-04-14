import 'package:cloud_firestore/cloud_firestore.dart';

/// Recensione di un sentiero pubblico (PublicTrail).
/// Ogni utente può lasciare una sola recensione per sentiero.
class TrailReview {
  final String userId;
  final String username;
  final String? avatarUrl;
  final int rating; // 1..5
  final String text;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const TrailReview({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.rating,
    required this.text,
    required this.createdAt,
    this.updatedAt,
  });

  factory TrailReview.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return TrailReview(
      userId: data['userId'] ?? doc.id,
      username: data['username'] ?? 'Utente',
      avatarUrl: data['avatarUrl'],
      rating: (data['rating'] as num?)?.toInt() ?? 0,
      text: data['text'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'userId': userId,
        'username': username,
        'avatarUrl': avatarUrl,
        'rating': rating,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toFirestoreUpdate() => {
        'username': username,
        'avatarUrl': avatarUrl,
        'rating': rating,
        'text': text,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// Risultato di un'operazione di scrittura review.
class ReviewResult {
  final bool success;
  final String? error;
  final TrailReview? review;

  const ReviewResult({
    required this.success,
    this.error,
    this.review,
  });

  factory ReviewResult.ok([TrailReview? review]) =>
      ReviewResult(success: true, review: review);

  factory ReviewResult.fail(String error) =>
      ReviewResult(success: false, error: error);
}
