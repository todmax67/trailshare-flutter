import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/emergency_contact.dart';

/// Repository per i contatti di emergenza dell'utente corrente.
///
/// Struttura Firestore:
///   user_profiles/{uid}/emergency_contacts/{contactId}
///
/// Regola operativa: **massimo 3 contatti per utente** (regola applicata
/// sia lato client — UI non permette di aggiungere il 4° — sia lato
/// Firestore rules per sicurezza).
class EmergencyContactsRepository {
  static const int maxContacts = 3;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  EmergencyContactsRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _col(String uid) => _firestore
      .collection('user_profiles')
      .doc(uid)
      .collection('emergency_contacts');

  /// Lista contatti dell'utente corrente, ordinati per `order` crescente.
  Future<List<EmergencyContact>> getContacts() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _col(uid).orderBy('order').get();
    return snap.docs.map(EmergencyContact.fromFirestore).toList();
  }

  /// Stream reattivo dei contatti (per la settings page).
  Stream<List<EmergencyContact>> watchContacts() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _col(uid).orderBy('order').snapshots().map(
          (s) => s.docs.map(EmergencyContact.fromFirestore).toList(),
        );
  }

  /// Aggiunge un nuovo contatto. Lancia [StateError] se si supera [maxContacts].
  /// Ritorna l'ID assegnato dal backend.
  Future<String> addContact(EmergencyContact contact) async {
    final uid = _uid;
    if (uid == null) throw StateError('Utente non autenticato');

    final existing = await _col(uid).count().get();
    if ((existing.count ?? 0) >= maxContacts) {
      throw StateError('Raggiunto limite di $maxContacts contatti di emergenza');
    }

    final doc = _col(uid).doc();
    await doc.set(contact.toFirestore());
    return doc.id;
  }

  /// Aggiorna un contatto esistente.
  Future<void> updateContact(EmergencyContact contact) async {
    final uid = _uid;
    if (uid == null) throw StateError('Utente non autenticato');
    await _col(uid).doc(contact.id).update(contact.toFirestore());
  }

  /// Elimina un contatto.
  Future<void> deleteContact(String contactId) async {
    final uid = _uid;
    if (uid == null) throw StateError('Utente non autenticato');
    await _col(uid).doc(contactId).delete();
  }

  /// Aggiorna l'ordine (priorità) di più contatti in un batch.
  Future<void> reorderContacts(List<EmergencyContact> ordered) async {
    final uid = _uid;
    if (uid == null) throw StateError('Utente non autenticato');
    final batch = _firestore.batch();
    for (var i = 0; i < ordered.length; i++) {
      final c = ordered[i];
      batch.update(_col(uid).doc(c.id), {'order': i});
    }
    await batch.commit();
  }

  /// Vero se l'utente corrente ha almeno 1 contatto configurato
  /// (utile per decidere se abilitare il toggle Lifeline).
  Future<bool> hasAnyContact() async {
    final uid = _uid;
    if (uid == null) return false;
    final snap = await _col(uid).limit(1).get();
    return snap.docs.isNotEmpty;
  }

  // ── Template messaggio Lifeline ──────────────────────────────────────
  //
  // Il template è salvato come campo `lifelineMessageTemplate` direttamente
  // sul documento `user_profiles/{uid}`. Se vuoto / null si usa il default.
  //
  // Placeholder supportati (case-sensitive):
  //   {nome}         → nome del contatto destinatario
  //   {attività}     → nome attività (es. "Trekking", "Mountain Bike")
  //   {nomeTraccia}  → " lungo {nome}" solo se in modalità guidata, vuoto altrimenti
  //   {link}         → link live con token del contatto

  /// Testo di default del messaggio iniziale ai contatti.
  static const String defaultMessageTemplate =
      '🛡️ Lifeline TrailShare — Ciao {nome}! Sto per iniziare {attività}{nomeTraccia}.\n'
      'Se vuoi seguire la mia posizione live apri: {link}\n'
      'In caso di emergenza contattami o chiama le autorità.';

  /// Legge il template salvato (o null se non personalizzato).
  Future<String?> getMessageTemplate() async {
    final uid = _uid;
    if (uid == null) return null;
    final doc = await _firestore.collection('user_profiles').doc(uid).get();
    final data = doc.data();
    final raw = data?['lifelineMessageTemplate'];
    if (raw is String && raw.trim().isNotEmpty) return raw;
    return null;
  }

  /// Sostituisce il template salvato. Passare null / stringa vuota per
  /// ripristinare il default.
  Future<void> setMessageTemplate(String? template) async {
    final uid = _uid;
    if (uid == null) throw StateError('Utente non autenticato');
    final trimmed = template?.trim();
    await _firestore.collection('user_profiles').doc(uid).set(
      {
        'lifelineMessageTemplate':
            (trimmed == null || trimmed.isEmpty) ? FieldValue.delete() : trimmed,
      },
      SetOptions(merge: true),
    );
  }

  /// Rende il template sostituendo i placeholder.
  /// Usato dal [LifelineService] al momento dell'invio.
  static String renderTemplate({
    required String template,
    required String contactName,
    required String activityName,
    String? referenceName,
    required String link,
  }) {
    final traccia = (referenceName == null || referenceName.trim().isEmpty)
        ? ''
        : ' lungo "$referenceName"';
    return template
        .replaceAll('{nome}', contactName)
        .replaceAll('{attività}', activityName)
        .replaceAll('{attivita}', activityName) // tolleranza senza accento
        .replaceAll('{nomeTraccia}', traccia)
        .replaceAll('{link}', link);
  }
}
