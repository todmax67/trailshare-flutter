import 'package:cloud_firestore/cloud_firestore.dart';

/// Foto community caricata su un sentiero pubblico (PublicTrail).
/// Ogni utente può caricare più foto per lo stesso sentiero.
class TrailPhoto {
  final String photoId;
  final String trailId;
  final String userId;
  final String username;
  final String? avatarUrl;
  final String photoUrl;
  final String storagePath;
  final String caption;
  final DateTime createdAt;

  const TrailPhoto({
    required this.photoId,
    required this.trailId,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.photoUrl,
    required this.storagePath,
    this.caption = '',
    required this.createdAt,
  });

  factory TrailPhoto.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return TrailPhoto(
      photoId: doc.id,
      trailId: data['trailId'] ?? '',
      userId: data['userId'] ?? '',
      username: data['username'] ?? 'Utente',
      avatarUrl: data['avatarUrl'],
      photoUrl: data['photoUrl'] ?? '',
      storagePath: data['storagePath'] ?? '',
      caption: data['caption'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'trailId': trailId,
        'userId': userId,
        'username': username,
        'avatarUrl': avatarUrl,
        'photoUrl': photoUrl,
        'storagePath': storagePath,
        'caption': caption,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// Risultato di un'operazione di upload/delete foto.
class PhotoUploadResult {
  final bool success;
  final String? error;
  final TrailPhoto? photo;

  const PhotoUploadResult({
    required this.success,
    this.error,
    this.photo,
  });

  factory PhotoUploadResult.ok([TrailPhoto? photo]) =>
      PhotoUploadResult(success: true, photo: photo);

  factory PhotoUploadResult.fail(String error) =>
      PhotoUploadResult(success: false, error: error);
}
