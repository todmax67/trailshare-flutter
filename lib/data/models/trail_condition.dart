import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Stato di percorribilità di un sentiero, segnalato dalla community.
enum TrailConditionStatus {
  good('good', 'Buono', '🟢', Color(0xFF2E7D32)),
  warning('warning', 'Attenzione', '🟡', Color(0xFFF9A825)),
  mud('mud', 'Fango', '💧', Color(0xFF795548)),
  snow('snow', 'Neve', '❄️', Color(0xFF42A5F5)),
  ice('ice', 'Ghiaccio', '🧊', Color(0xFF1565C0)),
  rockfall('rockfall', 'Frana / Sassi', '🪨', Color(0xFFEF6C00)),
  closed('closed', 'Chiuso', '🚫', Color(0xFFC62828));

  final String code;
  final String label;
  final String emoji;
  final Color color;
  const TrailConditionStatus(this.code, this.label, this.emoji, this.color);

  static TrailConditionStatus fromCode(String? code) {
    for (final s in TrailConditionStatus.values) {
      if (s.code == code) return s;
    }
    return TrailConditionStatus.good;
  }

  /// True se indica un problema (badge rosso/arancione).
  bool get isCritical =>
      this == TrailConditionStatus.closed ||
      this == TrailConditionStatus.rockfall ||
      this == TrailConditionStatus.ice;
}

/// Segnalazione di condizione sentiero da parte di un utente.
class TrailCondition {
  final String id;
  final String userId;
  final String username;
  final String? avatarUrl;
  final TrailConditionStatus status;
  final String note;
  final DateTime reportedAt;

  const TrailCondition({
    required this.id,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.status,
    this.note = '',
    required this.reportedAt,
  });

  factory TrailCondition.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return TrailCondition(
      id: doc.id,
      userId: data['userId'] ?? '',
      username: data['username'] ?? 'Utente',
      avatarUrl: data['avatarUrl'],
      status: TrailConditionStatus.fromCode(data['status'] as String?),
      note: data['note'] ?? '',
      reportedAt: (data['reportedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'userId': userId,
        'username': username,
        'avatarUrl': avatarUrl,
        'status': status.code,
        'note': note,
        'reportedAt': FieldValue.serverTimestamp(),
      };
}
