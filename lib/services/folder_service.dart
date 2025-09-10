import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class GroupFolder {
  final String id;
  final String name;
  final String ownerUid;
  final List<String> memberUids;
  final DateTime? createdAt;

  const GroupFolder({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.memberUids,
    this.createdAt,
  });

  factory GroupFolder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['createdAt'];
    return GroupFolder(
      id: doc.id,
      name: (data['name'] ?? '') as String,
      ownerUid: (data['ownerUid'] ?? '') as String,
      memberUids: (data['memberUids'] as List? ?? const <String>[]).cast<String>(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'ownerUid': ownerUid,
        'memberUids': memberUids,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

class FolderService {
  static final _db = FirebaseFirestore.instance;
  static const _col = 'group_folders';
  static bool get isSupported => kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static String? get uid => FirebaseAuth.instance.currentUser?.uid;

  static Stream<List<GroupFolder>> streamMyFolders() {
    if (!isSupported || uid == null) return const Stream<List<GroupFolder>>.empty();
    // Show any folder the user participates in (owner included), so friends see shared folders
    return _db
        .collection(_col)
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GroupFolder.fromDoc(d)).toList());
  }

  /// Creates a folder for the current user, enforcing a max of 5.
  static Future<void> createFolder({required String name, required List<String> memberUids}) async {
    if (!isSupported) return;
    final me = uid;
    if (me == null) throw Exception('Not signed in');
    final q = await _db.collection(_col).where('ownerUid', isEqualTo: me).get();
    if (q.size >= 5) {
      throw Exception('Folder limit reached (5)');
    }
    // Ensure owner included once
    final unique = {...memberUids, me}.toList();
    final folder = GroupFolder(id: '', name: name.trim(), ownerUid: me, memberUids: unique);
    await _db.collection(_col).add(folder.toMap());
  }

  /// Deletes an existing folder. Only the owner can delete.
  static Future<void> deleteFolder(String folderId) async {
    if (!isSupported) return;
    final me = uid;
    if (me == null) throw Exception('Not signed in');
    final ref = _db.collection(_col).doc(folderId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Folder not found');
    final data = snap.data() as Map<String, dynamic>;
    if ((data['ownerUid'] as String?) != me) {
      throw Exception('Only the owner can delete this folder');
    }
    await ref.delete();
  }

  /// Adds members to an existing folder (arrayUnion). Only the owner can update.
  static Future<void> addMembers({required String folderId, required List<String> memberUids}) async {
    if (!isSupported) return;
    if (memberUids.isEmpty) return;
    final me = uid;
    if (me == null) throw Exception('Not signed in');
    final ref = _db.collection(_col).doc(folderId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Folder not found');
    final data = snap.data() as Map<String, dynamic>;
    if ((data['ownerUid'] as String?) != me) {
      throw Exception('Only the owner can modify members');
    }
    // Ensure the owner stays present and members are unique
    final toAdd = {...memberUids, me}.toList();
    await ref.update({'memberUids': FieldValue.arrayUnion(toAdd)});
  }
}
