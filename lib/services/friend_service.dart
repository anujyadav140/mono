import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;

import '../models/app_user.dart';

enum FriendStatus { none, pendingOutgoing, pendingIncoming, friends }

class FriendService {
  static final _db = FirebaseFirestore.instance;
  static const _col = 'friendships';

  static bool get isSupported => kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static String _pairId(String uid1, String uid2) {
    return (uid1.compareTo(uid2) < 0) ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  static Future<FriendStatus> getStatus(String uidA, String uidB) async {
    if (!isSupported) return FriendStatus.none;
    try {
      final id = _pairId(uidA, uidB);
      final doc = await _db.collection(_col).doc(id).get();
      if (!doc.exists) return FriendStatus.none;
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'none') as String;
      final requester = (data['requester'] ?? '') as String;
      if (status == 'accepted') return FriendStatus.friends;
      if (status == 'pending') {
        return requester == uidA ? FriendStatus.pendingOutgoing : FriendStatus.pendingIncoming;
      }
      return FriendStatus.none;
    } catch (e) {
      debugPrint('FriendService.getStatus error: $e');
      return FriendStatus.none;
    }
  }

  /// Sends a friend request. If there is an incoming pending request,
  /// it will be accepted and return FriendStatus.friends.
  static Future<FriendStatus> sendRequest(String fromUid, String toUid) async {
    if (!isSupported) return FriendStatus.none;
    final id = _pairId(fromUid, toUid);
    final ref = _db.collection(_col).doc(id);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        final a = id.split('_')[0];
        final b = id.split('_')[1];
        tx.set(ref, {
          'a': a,
          'b': b,
          // Ensure canonical ordering to match rules and prevent glitches
          'users': [a, b],
          'requester': fromUid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return FriendStatus.pendingOutgoing;
      }
      final data = snap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'pending') as String;
      final requester = (data['requester'] ?? '') as String;
      if (status == 'accepted') return FriendStatus.friends;
      if (status == 'pending') {
        if (requester == fromUid) return FriendStatus.pendingOutgoing;
        // Opposite pending -> accept
        tx.update(ref, {
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
          'acceptedAt': FieldValue.serverTimestamp(),
        });
        return FriendStatus.friends;
      }
      return FriendStatus.none;
    });
  }

  static Future<bool> accept(String uidA, String uidB) async {
    if (!isSupported) return false;
    try {
      final id = _pairId(uidA, uidB);
      final ref = _db.collection(_col).doc(id);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw StateError('No request found');
        }
        final data = snap.data() as Map<String, dynamic>;
        if ((data['status'] as String?) != 'pending') return;
        // Prevent requester from accepting their own request in case of UI glitches
        if ((data['requester'] as String?) == uidA) return;
        tx.update(ref, {
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });
      return true;
    } catch (e) {
      debugPrint('FriendService.accept error: $e');
      return false;
    }
  }

  static Future<bool> deny(String uidA, String uidB) async {
    if (!isSupported) return false;
    try {
      final id = _pairId(uidA, uidB);
      await _db.collection(_col).doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('FriendService.deny error: $e');
      return false;
    }
  }

  static Stream<List<String>> incomingRequestUids(String uid) {
    if (!isSupported) return const Stream.empty();
    // Avoid composite index requirement by filtering status client-side.
    return _db
        .collection(_col)
        .where('users', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final out = <String>[];
      for (final d in snap.docs) {
        final data = d.data();
        if ((data['status'] as String?) != 'pending') continue;
        final requester = (data['requester'] ?? '') as String;
        final users = (data['users'] as List).cast<String>();
        final other = users.firstWhere((u) => u != uid, orElse: () => requester);
        if (requester != uid) {
          out.add(other);
        }
      }
      return out;
    });
  }

  static Stream<List<String>> friendsOf(String uid) {
    if (!isSupported) return const Stream.empty();
    return _db
        .collection(_col)
        .where('users', arrayContains: uid)
        .snapshots()
        .asyncMap((snap) async {
      final out = <String>[];
      for (final d in snap.docs) {
        final data = d.data();
        if ((data['status'] as String?) != 'accepted') continue;
        final users = (data['users'] as List).cast<String>();
        final other = users.firstWhere((u) => u != uid, orElse: () => '');
        if (other.isNotEmpty) out.add(other);
      }
      return out;
    });
  }

  static Future<AppUser?> fetchUser(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return AppUser.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    } catch (e) {
      debugPrint('FriendService.fetchUser error: $e');
      return null;
    }
  }
}
