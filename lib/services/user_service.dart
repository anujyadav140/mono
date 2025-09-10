import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:firebase_auth/firebase_auth.dart' as fa;

import '../models/app_user.dart';

class UserService {
  static const String _collection = 'users';

  /// Whether Cloud Firestore is available on this platform/runtime.
  /// Official support: Android, iOS, web, macOS.
  static bool get isSupported => kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Upserts a user document for the given Google account, with a search index.
  static Future<void> upsertFromGoogle(GoogleSignInAccount account) async {
    if (!isSupported) return;
    try {
      final doc = FirebaseFirestore.instance.collection(_collection).doc(account.id);
      final email = account.email;
      final displayName = account.displayName;
      final photoUrl = account.photoUrl;

      final handle = _emailHandle(email);
      final prefixes = _buildSearchPrefixes(<String?>[
        email,
        displayName,
        handle,
      ]);

      await doc.set({
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'handle': handle,
        'searchPrefixes': prefixes,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // If Firestore database is not created yet, avoid breaking sign-in.
      debugPrint('UserService.upsertFromGoogle skipped: $e');
    }
  }

  /// Returns at most [limit] users matching the search query using prefix matching
  /// on email, displayName and handle.
  static Future<List<AppUser>> searchUsers(String query, {int limit = 20}) async {
    if (!isSupported) return [];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_collection)
          .where('searchPrefixes', arrayContains: q)
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => AppUser.fromMap(d.id, d.data()))
          .toList(growable: false);
    } catch (e) {
      // If database doesn't exist yet, just return empty so UI stays functional.
      debugPrint('UserService.searchUsers skipped: $e');
      return [];
    }
  }

  static String _emailHandle(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email.toLowerCase();
    return email.substring(0, at).toLowerCase();
  }

  static List<String> _buildSearchPrefixes(List<String?> values) {
    final Set<String> out = {};
    for (final v in values) {
      if (v == null) continue;
      final s = v.trim().toLowerCase();
      if (s.isEmpty) continue;
      for (int i = 1; i <= s.length; i++) {
        out.add(s.substring(0, i));
      }
    }
    return out.take(200).toList();
  }

  /// Upserts a user document from a FirebaseAuth user. Use this when
  /// the app signs in to Firebase directly (e.g., signInWithProvider).
  static Future<void> upsertFromFirebaseUser(fa.User user) async {
    if (!isSupported) return;
    try {
      final doc = FirebaseFirestore.instance.collection(_collection).doc(user.uid);

      final email = user.email ?? '';
      final displayName = user.displayName;
      final photoUrl = user.photoURL;

      final handle = _emailHandle(email);
      final prefixes = _buildSearchPrefixes(<String?>[
        email,
        displayName,
        handle,
      ]);

      await doc.set({
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'handle': handle,
        'searchPrefixes': prefixes,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('UserService.upsertFromFirebaseUser skipped: $e');
    }
  }
}
