import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize();
    _googleInitialized = true;
  }

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.addScope('profile');

      if (kIsWeb) {
        // Web: use popup to avoid redirect/session issues
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        return await _auth.signInWithPopup(googleProvider);
      } else {
        // Android/iOS: FORCE native Google account chooser (stay in app).
        await _ensureGoogleInitialized();
        final account = await GoogleSignIn.instance
            .authenticate()
            .timeout(const Duration(seconds: 45));
        final idToken = account.authentication.idToken;
        if (idToken == null || idToken.isEmpty) {
          throw FirebaseAuthException(
            code: 'missing-id-token',
            message: 'Google ID token was not returned',
          );
        }
        final credential = GoogleAuthProvider.credential(idToken: idToken);
        return await _auth
            .signInWithCredential(credential)
            .timeout(const Duration(seconds: 45));
      }
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Google sign-in failed. Please try again.';
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method.';
      case 'invalid-credential':
        return 'The credential is invalid or has expired.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'user-not-found':
        return 'No user found with this credential.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'invalid-verification-code':
        return 'Invalid verification code.';
      case 'invalid-verification-id':
        return 'Invalid verification ID.';
      default:
        return 'An error occurred during authentication. Please try again.';
    }
  }
}
