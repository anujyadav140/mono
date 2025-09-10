import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mono/services/friend_service.dart';

class FriendRequestListener extends StatefulWidget {
  final VoidCallback onViewRequests;
  const FriendRequestListener({super.key, required this.onViewRequests});

  @override
  State<FriendRequestListener> createState() => _FriendRequestListenerState();
}

class _FriendRequestListenerState extends State<FriendRequestListener> {
  int _lastCount = 0;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return StreamBuilder<List<String>>(
      stream: FriendService.incomingRequestUids(uid),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        if (count > _lastCount && _lastCount != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('You have $count friend request${count == 1 ? '' : 's'}')),
            );
          });
        }
        _lastCount = count;
        if (count == 0) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.mail_outline, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count pending friend request${count == 1 ? '' : 's'}',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurface),
                ),
              ),
              TextButton(
                onPressed: widget.onViewRequests,
                child: const Text('View'),
              ),
            ],
          ),
        );
      },
    );
  }
}

