import 'package:cloud_firestore/cloud_firestore.dart';

/// Contatto di emergenza associato a un utente.
///
/// Massimo 3 per utente (regola applicata lato client + rules Firestore).
/// Salvato in `user_profiles/{uid}/emergency_contacts/{contactId}`.
///
/// Se il contatto è a sua volta utente TrailShare (`trailShareUserId` != null)
/// può ricevere push notifications dirette invece di SMS, altrimenti gli
/// viene proposto l'invio via url_launcher (SMS / WhatsApp / email).
class EmergencyContact {
  /// ID documento Firestore (equivale a slug o uuid).
  final String id;

  /// Nome visualizzato (es. "Marco fratello", "Moglie", "118").
  final String name;

  /// Numero di telefono in formato E.164 (es. `+393331234567`).
  /// Opzionale: se null, si usa solo l'email.
  final String? phone;

  /// Email alternativa al telefono. Opzionale.
  final String? email;

  /// Se il contatto è a sua volta utente TrailShare, UID Firebase.
  /// Quando impostato, le notifiche Lifeline preferiscono il canale push
  /// in-app invece di SMS/WhatsApp.
  final String? trailShareUserId;

  /// Ordine di priorità 0-based. In caso SOS i contatti vengono
  /// notificati in ordine (il primo è il più "vicino/affidabile").
  final int order;

  /// Timestamp di creazione (serverTimestamp al primo save).
  final DateTime? createdAt;

  const EmergencyContact({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.trailShareUserId,
    this.order = 0,
    this.createdAt,
  });

  /// Vero se il contatto ha almeno un canale di comunicazione valido.
  bool get isReachable => (phone?.isNotEmpty ?? false) || (email?.isNotEmpty ?? false) || (trailShareUserId?.isNotEmpty ?? false);

  /// Vero se è un utente TrailShare che può ricevere push notifications.
  bool get isTrailShareUser => trailShareUserId != null && trailShareUserId!.isNotEmpty;

  EmergencyContact copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? trailShareUserId,
    int? order,
    DateTime? createdAt,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      trailShareUserId: trailShareUserId ?? this.trailShareUserId,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        if (email != null && email!.isNotEmpty) 'email': email,
        if (trailShareUserId != null && trailShareUserId!.isNotEmpty)
          'trailShareUserId': trailShareUserId,
        'order': order,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
      };

  factory EmergencyContact.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return EmergencyContact(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      phone: data['phone'] as String?,
      email: data['email'] as String?,
      trailShareUserId: data['trailShareUserId'] as String?,
      order: (data['order'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
