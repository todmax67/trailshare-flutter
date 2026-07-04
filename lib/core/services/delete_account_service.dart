import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/constants/app_colors.dart';

/// Servizio per eliminare l'account utente.
///
/// La cancellazione vera e propria gira lato server nella Cloud Function
/// `deleteMyAccount` (privilegi Admin SDK): geometria tracce (GPS+HR), copie
/// pubbliche (published_tracks/community_tracks) coi cheers/comments
/// annidati, cheers dati su tracce altrui, token OAuth Strava/Polar
/// (revocati), pairing Garmin, foto su Storage, l'intero doc users/{uid}
/// (ricorsivo) e infine l'account Firebase Auth. Il client si limita a
/// invocarla e, a successo, a chiudere la sessione locale — niente più
/// richiesta di re-login (l'eliminazione Auth la fa l'Admin SDK server-side,
/// non serve una login recente lato client).
class DeleteAccountService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  /// Elimina l'account e tutti i dati associati.
  Future<DeleteAccountResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      return DeleteAccountResult(
        success: false,
        error: 'Nessun utente loggato',
      );
    }

    try {
      await _functions.httpsCallable('deleteMyAccount').call();
      await _auth.signOut();
      return DeleteAccountResult(success: true);
    } on FirebaseFunctionsException catch (e) {
      return DeleteAccountResult(
        success: false,
        error: e.message ?? 'Errore durante l\'eliminazione (${e.code})',
      );
    } catch (e) {
      return DeleteAccountResult(
        success: false,
        error: 'Errore durante l\'eliminazione: $e',
      );
    }
  }
}

/// Risultato dell'operazione di eliminazione
class DeleteAccountResult {
  final bool success;
  final String? error;

  const DeleteAccountResult({
    required this.success,
    this.error,
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
    }
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
