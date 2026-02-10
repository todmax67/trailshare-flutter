import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Risultato autenticazione
class AuthResult {
  final bool success;
  final String? errorMessage;
  final User? user;

  AuthResult({required this.success, this.errorMessage, this.user});
}

/// Servizio di autenticazione
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Utente corrente
  User? get currentUser => _auth.currentUser;

  /// Stream stato autenticazione
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ═══════════════════════════════════════════════════════════════════════════
  // EMAIL & PASSWORD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Login con email e password
  Future<AuthResult> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return AuthResult(success: true, user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, errorMessage: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Errore di connessione');
    }
  }

  /// Registrazione con email e password
  Future<AuthResult> registerWithEmail(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return AuthResult(success: true, user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, errorMessage: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Errore di connessione');
    }
  }

  /// Reset password
  Future<AuthResult> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, errorMessage: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Errore di connessione');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GOOGLE SIGN-IN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Login con Google
  Future<AuthResult> signInWithGoogle() async {
    try {
      // Avvia il flusso di autenticazione Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // L'utente ha annullato
        return AuthResult(success: false, errorMessage: 'Accesso annullato');
      }

      // Ottieni i dettagli di autenticazione
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Crea le credenziali Firebase
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Accedi a Firebase
      final userCredential = await _auth.signInWithCredential(credential);
      
      return AuthResult(success: true, user: userCredential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, errorMessage: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Errore Google Sign-In: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APPLE SIGN-IN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Login con Apple — Metodo nativo Firebase (bypassa OAuth server-side)
  Future<AuthResult> signInWithApple() async {
    try {
      debugPrint('[AppleSignIn] Starting native Firebase Apple Sign-In...');

      final appleProvider = AppleAuthProvider();
      appleProvider.addScope('email');
      appleProvider.addScope('name');

      // Usa signInWithProvider — gestisce tutto Firebase/iOS nativamente
      // Non passa per la configurazione OAuth server-side
      final userCredential = await _auth.signInWithProvider(appleProvider);

      debugPrint('[AppleSignIn] SUCCESS! uid: ${userCredential.user?.uid}');
      debugPrint('[AppleSignIn] email: ${userCredential.user?.email}');
      debugPrint('[AppleSignIn] displayName: ${userCredential.user?.displayName}');

      return AuthResult(success: true, user: userCredential.user);
    } on FirebaseAuthException catch (e) {
      debugPrint('[AppleSignIn] Firebase Auth Exception: code=${e.code}, message=${e.message}');
      if (e.code == 'canceled' || e.message?.contains('canceled') == true) {
        return AuthResult(success: false, errorMessage: 'Accesso annullato');
      }
      return AuthResult(success: false, errorMessage: 'Firebase [${e.code}]: ${e.message}');
    } catch (e) {
      debugPrint('[AppleSignIn] Generic Exception: ${e.runtimeType}: $e');
      return AuthResult(success: false, errorMessage: 'Errore: ${e.runtimeType}: $e');
    }
  }

  /// Verifica se Apple Sign-In è disponibile
  Future<bool> isAppleSignInAvailable() async {
    return await SignInWithApple.isAvailable();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOGOUT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Logout
  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Genera nonce casuale per Apple Sign-In
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  /// SHA256 di una stringa
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Messaggi di errore localizzati
  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Nessun account trovato con questa email';
      case 'wrong-password':
        return 'Password non corretta';
      case 'invalid-email':
        return 'Email non valida';
      case 'user-disabled':
        return 'Account disabilitato';
      case 'too-many-requests':
        return 'Troppi tentativi. Riprova più tardi';
      case 'email-already-in-use':
        return 'Email già registrata';
      case 'weak-password':
        return 'Password troppo debole (minimo 6 caratteri)';
      case 'operation-not-allowed':
        return 'Operazione non consentita';
      case 'account-exists-with-different-credential':
        return 'Esiste già un account con questa email';
      case 'invalid-credential':
        return 'Credenziali non valide';
      case 'network-request-failed':
        return 'Errore di connessione';
      default:
        return 'Errore di autenticazione';
    }
  }
}
