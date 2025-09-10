import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mono/models/app_user.dart';
import 'package:mono/services/user_service.dart';
import 'package:mono/services/friend_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SearchUserPage extends StatefulWidget {
  final List<AppUser> initialSelected;
  final GoogleSignInAccount? currentUser;
  final String? initialQuery;

  const SearchUserPage({super.key, this.initialSelected = const [], this.currentUser, this.initialQuery});

  @override
  State<SearchUserPage> createState() => _SearchUserPageState();
}

class _SearchUserPageState extends State<SearchUserPage> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  List<AppUser> _results = [];
  final List<AppUser> _selected = [];
  bool _loading = false;
  final Map<String, FriendStatus> _status = {};

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _ctrl.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch(widget.initialQuery!));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await UserService.searchUsers(query, limit: 25);
      // Filter out current user and already selected
      final currentId = FirebaseAuth.instance.currentUser?.uid;
      final selectedIds = _selected.map((e) => e.id).toSet();
      setState(() {
        _results = res.where((u) => u.id != currentId && !selectedIds.contains(u.id)).toList();
        _loading = false;
      });
      await _loadStatuses();
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadStatuses() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    final Map<String, FriendStatus> map = {};
    for (final u in _results) {
      map[u.id] = await FriendService.getStatus(me, u.id);
    }
    if (!mounted) return;
    setState(() { _status
      ..clear()
      ..addAll(map);
    });
  }

  Future<void> _onAction(AppUser user) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    final status = _status[user.id] ?? FriendStatus.none;
    try {
      if (status == FriendStatus.friends) {
        final exists = _selected.any((u) => u.id == user.id);
        setState(() {
          if (exists) {
            _selected.removeWhere((u) => u.id == user.id);
          } else {
            _selected.add(user);
          }
        });
        return;
      }
      if (status == FriendStatus.pendingIncoming) {
        final ok = await FriendService.accept(me, user.id);
        if (ok) {
          setState(() { _status[user.id] = FriendStatus.friends; });
          // Auto-select now that you're friends
          setState(() { _selected.add(user); });
        }
        return;
      }
      // none or pendingOutgoing -> send request
      final newStatus = await FriendService.sendRequest(me, user.id);
      setState(() { _status[user.id] = newStatus; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request sent')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to process: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Group Members'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop<List<AppUser>>(_selected);
            },
            child: Text('Done (${_selected.length})'),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _ctrl,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search by email or handle (e.g. anujyadav140)',
                filled: true,
                fillColor: scheme.surface,
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                children: _selected
                    .map((u) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text(u.displayName ?? u.email),
                            onDeleted: () => setState(() { _selected.removeWhere((e) => e.id == u.id); }),
                          ),
                        ))
                    .toList(),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _ctrl.text.trim().isEmpty
                              ? 'Type to search your friends'
                              : 'No users found',
                          style: text.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final user = _results[index];
                          final selected = _selected.any((u) => u.id == user.id);
                          final st = _status[user.id] ?? FriendStatus.none;
                          return ListTile(
                            leading: CircleAvatar(backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null, child: user.photoUrl == null ? const Icon(Icons.person) : null),
                            title: Text(user.displayName ?? user.email),
                            subtitle: Text(user.email),
                            trailing: _buildTrailingForStatus(context, st, selected, scheme, () => _onAction(user)),
                            onTap: () => _onAction(user),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailingForStatus(BuildContext context, FriendStatus st, bool selected, ColorScheme scheme, VoidCallback onPressed) {
    switch (st) {
      case FriendStatus.friends:
        return Icon(selected ? Icons.check_circle : Icons.add_circle_outline, color: selected ? scheme.primary : scheme.onSurfaceVariant);
      case FriendStatus.pendingOutgoing:
        return const Text('Requested');
      case FriendStatus.pendingIncoming:
        return TextButton(onPressed: onPressed, child: const Text('Accept'));
      case FriendStatus.none:
      default:
        return TextButton(onPressed: onPressed, child: const Text('Request'));
    }
  }
}
