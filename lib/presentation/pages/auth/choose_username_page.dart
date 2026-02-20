import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';

class ChooseUsernamePage extends StatefulWidget {
  final VoidCallback onUsernameChosen;

  const ChooseUsernamePage({super.key, required this.onUsernameChosen});

  @override
  State<ChooseUsernamePage> createState() => _ChooseUsernamePageState();
}

class _ChooseUsernamePageState extends State<ChooseUsernamePage> {
  final _controller = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveUsername() async {
    final username = _controller.text.trim();

    // Validazione
    if (username.isEmpty) {
      setState(() => _errorMessage = 'Inserisci un username');
      return;
    }
    if (username.length < 3) {
      setState(() => _errorMessage = 'Minimo 3 caratteri');
      return;
    }
    if (username.length > 20) {
      setState(() => _errorMessage = 'Massimo 20 caratteri');
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(username)) {
      setState(() => _errorMessage = 'Solo lettere, numeri, punti e underscore');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // Controlla unicità
      final existing = await _firestore
          .collection('user_profiles')
          .where('username', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();

      final user = FirebaseAuth.instance.currentUser;
      // Se esiste ed è di un altro utente
      if (existing.docs.isNotEmpty && existing.docs.first.id != user?.uid) {
        setState(() {
          _errorMessage = 'Username già in uso, scegline un altro';
          _isSaving = false;
        });
        return;
      }

      if (user == null) return;

      // Salva
      await _firestore.collection('user_profiles').doc(user.uid).set({
        'username': username,
        'usernameLower': username.toLowerCase(),
        'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        widget.onUsernameChosen();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Icona
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_add,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 32),

              // Titolo
              const Text(
                'Scegli il tuo username',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Questo nome sarà visibile agli altri utenti di TrailShare',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Input username
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveUsername(),
                maxLength: 20,
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: 'es. mario_rossi',
                  prefixIcon: const Icon(Icons.alternate_email),
                  errorText: _errorMessage,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),
              const SizedBox(height: 8),

              // Regole
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '3-20 caratteri • Lettere, numeri, punti e underscore',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),

              const Spacer(flex: 3),

              // Bottone conferma
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveUsername,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Conferma',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
