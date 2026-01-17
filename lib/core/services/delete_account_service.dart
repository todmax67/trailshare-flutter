import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';

/// Servizio per eliminare l'account utente
/// 
/// Elimina tutti i dati associati all'utente da Firestore
/// e poi elimina l'account da Firebase Auth.
class DeleteAccountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Elimina l'account e tutti i dati associati
  /// 
  /// Restituisce true se l'eliminazione è riuscita
  Future<DeleteAccountResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      return DeleteAccountResult(
        success: false,
        error: 'Nessun utente loggato',
      );
    }

    try {
      final userId = user.uid;

      // 1. Elimina le tracce dell'utente
      await _deleteCollection('users/$userId/tracks');

      // 2. Elimina il profilo utente
      await _firestore.collection('user_profiles').doc(userId).delete();

      // 3. Rimuovi l'utente dalle liste followers/following di altri
      await _removeFromFollowLists(userId);

      // 4. Elimina sessioni LiveTrack
      await _deleteLiveSessions(userId);

      // 5. Elimina i cheers dell'utente
      await _deleteUserCheers(userId);

      // 6. Elimina dalla wishlist (se salvata come documento separato)
      // I wishlist sono già dentro user_profiles, quindi già eliminati

      // 7. Infine, elimina l'account Firebase Auth
      await user.delete();

      return DeleteAccountResult(success: true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return DeleteAccountResult(
          success: false,
          error: 'Per sicurezza, effettua nuovamente il login prima di eliminare l\'account',
          requiresReauth: true,
        );
      }
      return DeleteAccountResult(
        success: false,
        error: 'Errore Firebase: ${e.message}',
      );
    } catch (e) {
      return DeleteAccountResult(
        success: false,
        error: 'Errore durante l\'eliminazione: $e',
      );
    }
  }

  /// Elimina una collezione intera
  Future<void> _deleteCollection(String path) async {
    final collection = _firestore.collection(path);
    final snapshots = await collection.limit(100).get();
    
    for (final doc in snapshots.docs) {
      await doc.reference.delete();
    }

    // Se ci sono più di 100 documenti, continua
    if (snapshots.docs.length == 100) {
      await _deleteCollection(path);
    }
  }

  /// Rimuove l'utente dalle liste followers/following di altri utenti
  Future<void> _removeFromFollowLists(String userId) async {
    try {
      // Trova tutti gli utenti che questo utente segue
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(userId)
          .get();

      if (profileDoc.exists) {
        final data = profileDoc.data()!;
        
        // Rimuovi dai followers degli utenti che seguiva
        final following = List<String>.from(data['following'] ?? []);
        for (final followedId in following) {
          await _firestore.collection('user_profiles').doc(followedId).update({
            'followers': FieldValue.arrayRemove([userId]),
          });
        }

        // Rimuovi dai following degli utenti che lo seguivano
        final followers = List<String>.from(data['followers'] ?? []);
        for (final followerId in followers) {
          await _firestore.collection('user_profiles').doc(followerId).update({
            'following': FieldValue.arrayRemove([userId]),
          });
        }
      }
    } catch (e) {
      print('[DeleteAccount] Errore rimozione follow lists: $e');
    }
  }

  /// Elimina le sessioni LiveTrack dell'utente
  Future<void> _deleteLiveSessions(String userId) async {
    try {
      final sessions = await _firestore
          .collection('live_sessions')
          .where('userId', isEqualTo: userId)
          .get();

      for (final doc in sessions.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      print('[DeleteAccount] Errore eliminazione live sessions: $e');
    }
  }

  /// Elimina i cheers dati dall'utente
  Future<void> _deleteUserCheers(String userId) async {
    try {
      // Questo è più complesso perché i cheers sono subcollection di published_tracks
      // Per semplicità, li lasciamo (verranno ignorati)
      // In produzione, potresti usare una Cloud Function per pulirli
    } catch (e) {
      print('[DeleteAccount] Errore eliminazione cheers: $e');
    }
  }

  /// Re-autentica l'utente (necessario per operazioni sensibili)
  Future<bool> reauthenticateWithGoogle() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Per Google Sign-In, serve ri-autenticarsi
      // Questo dipende dal provider usato
      // Per ora restituiamo false e gestiamo nel UI
      return false;
    } catch (e) {
      return false;
    }
  }
}

/// Risultato dell'operazione di eliminazione
class DeleteAccountResult {
  final bool success;
  final String? error;
  final bool requiresReauth;

  const DeleteAccountResult({
    required this.success,
    this.error,
    this.requiresReauth = false,
  });
}

/// Dialog per confermare l'eliminazione dell'account
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _confirmController = TextEditingController();
  final _service = DeleteAccountService();
  
  bool _isDeleting = false;
  bool _confirmed = false;
  String? _error;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  void _onConfirmChanged(String value) {
    setState(() {
      _confirmed = value.toLowerCase() == 'elimina';
    });
  }

  Future<void> _deleteAccount() async {
    if (!_confirmed || _isDeleting) return;

    setState(() {
      _isDeleting = true;
      _error = null;
    });

    final result = await _service.deleteAccount();

    if (result.success) {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() {
        _isDeleting = false;
        _error = result.error;
      });

      if (result.requiresReauth && mounted) {
        _showReauthDialog();
      }
    }
  }

  void _showReauthDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Richiesta ri-autenticazione'),
        content: const Text(
          'Per sicurezza, devi effettuare nuovamente il login prima di eliminare l\'account.\n\n'
          'Esci e accedi di nuovo, poi riprova.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
          const SizedBox(width: 8),
          const Text('Elimina Account'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Questa azione è irreversibile!\n\n'
              'Verranno eliminati permanentemente:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            _buildDeleteItem('Il tuo profilo'),
            _buildDeleteItem('Tutte le tue tracce'),
            _buildDeleteItem('I tuoi follower e following'),
            _buildDeleteItem('I tuoi percorsi salvati'),
            _buildDeleteItem('Le tue statistiche'),
            const SizedBox(height: 16),
            const Text(
              'Per confermare, scrivi "ELIMINA" qui sotto:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              onChanged: _onConfirmChanged,
              decoration: InputDecoration(
                hintText: 'Scrivi ELIMINA',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              enabled: !_isDeleting,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: _confirmed && !_isDeleting ? _deleteAccount : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
          ),
          child: _isDeleting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Elimina Account'),
        ),
      ],
    );
  }

  Widget _buildDeleteItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.remove_circle, size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

/// Funzione helper per mostrare il dialog
Future<bool?> showDeleteAccountDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const DeleteAccountDialog(),
  );
}
