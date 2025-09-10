import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mono/services/friend_service.dart';

class FriendRequestsPage extends StatelessWidget {
  const FriendRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in required')),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Friend Requests')),
      body: StreamBuilder<List<String>>(
        stream: FriendService.incomingRequestUids(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final ids = snapshot.data ?? const [];
          if (ids.isEmpty) {
            return Center(
              child: Text('No pending requests', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            );
          }
          return ListView.separated(
            itemCount: ids.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final otherId = ids[index];
              return FutureBuilder(
                future: FriendService.fetchUser(otherId),
                builder: (context, snap) {
                  final user = snap.data;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: (user?.photoUrl != null) ? NetworkImage(user!.photoUrl!) : null,
                      child: (user?.photoUrl == null) ? const Icon(Icons.person) : null,
                    ),
                    title: Text(user?.displayName ?? user?.email ?? 'Unknown'),
                    subtitle: Text(user?.email ?? ''),
                    trailing: Wrap(spacing: 8, children: [
                      TextButton(
                        onPressed: () async {
                          await FriendService.accept(uid, otherId);
                        },
                        child: const Text('Accept'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await FriendService.deny(uid, otherId);
                        },
                        child: const Text('Deny'),
                      ),
                    ]),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
