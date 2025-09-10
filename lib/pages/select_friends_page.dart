import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mono/models/app_user.dart';
import 'package:mono/services/friend_service.dart';

class SelectFriendsPage extends StatefulWidget {
  final List<AppUser> initial;
  final Set<String> excludeIds;
  const SelectFriendsPage({super.key, this.initial = const [], this.excludeIds = const <String>{}});

  @override
  State<SelectFriendsPage> createState() => _SelectFriendsPageState();
}

class _SelectFriendsPageState extends State<SelectFriendsPage> {
  final List<AppUser> _selected = [];

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Sign in required')));
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Friends'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop<List<AppUser>>(_selected),
            child: Text('Done (${_selected.length})'),
          )
        ],
      ),
      body: StreamBuilder<List<String>>(
        stream: FriendService.friendsOf(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final friendIds = snapshot.data ?? const [];
          final filteredIds = friendIds.where((id) => !widget.excludeIds.contains(id)).toList(growable: false);
          if (filteredIds.isEmpty) {
            return Center(
              child: Text('No eligible friends to add.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            );
          }
          return ListView.builder(
            itemCount: filteredIds.length,
            itemBuilder: (context, index) {
              final otherId = filteredIds[index];
              return FutureBuilder<AppUser?>(
                future: FriendService.fetchUser(otherId),
                builder: (context, snap) {
                  final user = snap.data;
                  if (user == null) {
                    return const ListTile(title: Text('Loading...'));
                  }
                  final selected = _selected.any((u) => u.id == user.id);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                      child: user.photoUrl == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text(user.displayName ?? user.email),
                    subtitle: Text(user.email),
                    trailing: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selected.removeWhere((u) => u.id == user.id);
                        } else {
                          _selected.add(user);
                        }
                      });
                    },
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
