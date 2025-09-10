import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';

import 'login_page.dart';
import 'itinerary_page.dart';
import '../firebase_options.dart';
import 'search_user.dart';
import 'friend_requests_page.dart';
import 'select_friends_page.dart';
import 'group_folder_detail_page.dart';
import 'package:mono/widgets/friend_request_listener.dart';
import 'package:mono/models/app_user.dart';
import 'package:mono/services/friend_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mono/services/folder_service.dart';

class GroupItineraryPage extends StatefulWidget {
  final GoogleSignInAccount? user;

  const GroupItineraryPage({super.key, this.user});

  @override
  State<GroupItineraryPage> createState() => _GroupItineraryPageState();
}

class _GroupItineraryPageState extends State<GroupItineraryPage> {
  final List<AppUser> _members = [];
  // Legacy fields retained for existing components; will be moved into folder detail pages.
  final TextEditingController _destinationCtrl = TextEditingController();
  final StreamController<String> _summaryStream = StreamController<String>.broadcast();
  final ValueNotifier<String> _delightMomentNotifier = ValueNotifier<String>('');
  final List<String> _suggestions = const [
    'Paris', 'Tokyo', 'New York', 'London', 'Rome', 'Barcelona',
    'Amsterdam', 'Dubai', 'Singapore', 'Sydney', 'Bangkok', 'Istanbul',
    'Berlin', 'Vienna', 'Prague', 'Venice', 'Santorini', 'Bali'
  ];
  bool _loading = false;
  String? _error;
  bool _hasSearchedOnce = false;
  bool _showProceedButton = false;
  List<String> _foods = [];
  List<String> _places = [];
  final TextEditingController _friendSearchCtrl = TextEditingController();
  final TextEditingController _folderNameCtrl = TextEditingController();
  bool _showCreateFolderField = false;
  String? _deletingFolderId;
  
  @override
  void initState() {
    super.initState();
    // Pre-fill current user as a group member if available
    final u = widget.user;
    if (u != null) {
      _members.add(AppUser(id: u.id, email: u.email, displayName: u.displayName, photoUrl: u.photoUrl));
    }
  }

  Future<List<AppUser>> _fetchFriendUsers(List<String> uids) async {
    final users = await Future.wait(uids.map((id) => FriendService.fetchUser(id)));
    return users.whereType<AppUser>().toList();
  }

  void _toggleMember(AppUser user) {
    final exists = _members.any((m) => m.id == user.id);
    setState(() {
      if (exists) {
        _members.removeWhere((m) => m.id == user.id);
      } else {
        _members.add(user);
      }
    });
  }

  Future<void> _openFriendSearchWithQuery() async {
    final q = _friendSearchCtrl.text.trim();
    final selected = await Navigator.of(context).push<List<AppUser>>(
      MaterialPageRoute(
        builder: (_) => SearchUserPage(initialSelected: _members, initialQuery: q),
      ),
    );
    if (selected != null) {
      final map = {for (final m in _members) m.id: m};
      for (final s in selected) { map[s.id] = s; }
      setState(() { _members..clear()..addAll(map.values); });
    }
  }

  Future<void> _openAddMembers() async {
    final selected = await Navigator.of(context).push<List<AppUser>>(
      MaterialPageRoute(
        builder: (_) => SelectFriendsPage(initial: _members),
      ),
    );
    if (selected != null) {
      // Merge unique by id
      final map = {for (final m in _members) m.id: m};
      for (final s in selected) {
        map[s.id] = s;
      }
      setState(() {
        _members
          ..clear()
          ..addAll(map.values);
      });
    }
  }

  void _openRequests() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FriendRequestsPage()),
    );
  }

  void _toggleCreateFolder() {
    setState(() {
      _showCreateFolderField = !_showCreateFolderField;
      if (_showCreateFolderField) {
        _folderNameCtrl.clear();
      }
    });
  }

  Future<void> _createFolder() async {
    final folderName = _folderNameCtrl.text.trim();
    if (folderName.isEmpty) return;
    
    setState(() {
      _showCreateFolderField = false;
    });
    
    try {
      final memberIds = _members.map((m) => m.id).toList();
      await FolderService.createFolder(name: folderName, memberUids: memberIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Folder "$folderName" created successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating folder: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
    
    _folderNameCtrl.clear();
  }

  void _showDeleteConfirmation(GroupFolder folder) {
    setState(() {
      _deletingFolderId = folder.id;
    });
  }

  void _cancelDelete() {
    setState(() {
      _deletingFolderId = null;
    });
  }

  Future<void> _confirmDeleteFolder(GroupFolder folder) async {
    final scheme = Theme.of(context).colorScheme;
    setState(() {
      _deletingFolderId = null;
    });
    
    try {
      await FolderService.deleteFolder(folder.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${folder.name}"'), backgroundColor: scheme.primary),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _addFriendsToFolder(GroupFolder folder) async {
    final selected = await Navigator.of(context).push<List<AppUser>>(
      MaterialPageRoute(builder: (_) => SelectFriendsPage(excludeIds: folder.memberUids.toSet())),
    );
    if (selected == null || selected.isEmpty) return;
    final ids = selected.map((u) => u.id).where((id) => !folder.memberUids.contains(id)).toSet().toList();
    if (ids.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new friends selected')),
      );
      return;
    }
    try {
      await FolderService.addMembers(folderId: folder.id, memberUids: ids);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${ids.length} friend(s) to "${folder.name}"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add friends: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  void _showFriendsBottomSheet(List<AppUser> friends, {String? title}) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final screenSize = MediaQuery.of(context).size;
    final fontScale = screenSize.width / 400;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.8,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ).animate().fadeIn(duration: 100.ms).slideY(begin: -0.5),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      title ?? 'Friends',
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        fontSize: (text.titleLarge?.fontSize ?? 22) * 0.8 * fontScale,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${friends.length}',
                        style: text.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: (text.labelMedium?.fontSize ?? 12) * 0.9 * fontScale,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 50.ms, duration: 200.ms).slideX(begin: -0.2),
              const Divider(height: 1),
              // Friends list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: scheme.primaryContainer,
                          backgroundImage: friend.photoUrl != null
                              ? NetworkImage(friend.photoUrl!)
                              : null,
                          child: friend.photoUrl == null
                              ? Icon(
                                  Icons.person,
                                  color: scheme.onPrimaryContainer,
                                  size: 20,
                                )
                              : null,
                        ),
                        title: Text(
                          friend.displayName ?? friend.email,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                            fontSize: (text.bodyLarge?.fontSize ?? 16) * 0.9 * fontScale,
                          ),
                        ),
                        subtitle: friend.displayName != null
                            ? Text(
                                friend.email,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: (text.bodySmall?.fontSize ?? 12) * 0.9 * fontScale,
                                ),
                              )
                            : null,
                      ),
                    ).animate().fadeIn(delay: (100 + index * 50).ms, duration: 200.ms)
                      .slideX(begin: 0.3).scale(begin: const Offset(0.95, 0.95));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _summaryStream.close();
    _destinationCtrl.dispose();
    _delightMomentNotifier.dispose();
    _friendSearchCtrl.dispose();
    _folderNameCtrl.dispose();
    super.dispose();
  }

  String _generateDelightMoment(String destination, String phase) {
    return '';
  }

  Stream<String> _generateStream(String destination) async* {
    final phases = ['start', 'data', 'thinking', 'results'];
    
    for (int i = 0; i < phases.length; i++) {
      await Future.delayed(Duration(milliseconds: 800 + (i * 200)));
      _delightMomentNotifier.value = _generateDelightMoment(destination, phases[i]);
      yield phases[i];
    }
  }

  Future<void> _submitDestination() async {
    if (_destinationCtrl.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter a destination';
      });
      return;
    }
    
    setState(() {
      _loading = true;
      _error = null;
      _places.clear();
      _foods.clear();
      _showProceedButton = false;
      _hasSearchedOnce = true;
    });

    try {
      final destination = _destinationCtrl.text.trim();
      
      // Start the delight moment stream
      _generateStream(destination).listen((_) {}, onDone: () {
        _delightMomentNotifier.value = 'Finalizing group recommendations...';
      });

      // Call HTTP Function directly to avoid App Check on callable
      final region = 'us-central1';
      final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
      final url = Uri.parse('https://$region-$projectId.cloudfunctions.net/exaSummary');
      final httpResp = await http.get(url).timeout(const Duration(seconds: 60));
      if (httpResp.statusCode != 200) {
        throw Exception('Functions HTTP error ${httpResp.statusCode}');
      }
      final Map<String, dynamic> data = json.decode(httpResp.body) as Map<String, dynamic>;
      final String exaSummary = (data['summary'] ?? '').toString();

      if (exaSummary.isEmpty) {
        throw Exception('No summary available');
      }

      // Use Gemini to extract FOODS / PLACES tailored for group
      final model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.5-flash',
      );
      final prompt = '''
For a group trip to $destination, and based on the user's historical preferences below, extract foods and places that will work well for groups. Be concise.

User Preferences:
$exaSummary

Return ONLY in this exact format:
FOODS: Italian Pizza, Family-style Tapas, Sushi, Street Tacos, Gelato
PLACES: Art Museums, Historic Districts, Parks, Rooftop Bars, Local Markets
''';
      final response = await model.generateContent([Content.text(prompt)]);
      final geminiSummary = response.text ?? '';

      _parseGeminiResponse(geminiSummary);
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to get recommendations. Please try again.';
      });
    }
  }
  
  void _parseGeminiResponse(String response) {
    try {
      List<String> foods = [];
      List<String> places = [];
      final lines = response.split('\n');
      for (final line in lines) {
        if (line.startsWith('FOODS:')) {
          final foodsText = line.replaceFirst('FOODS:', '').trim();
          foods = foodsText.split(',').map((f) => f.trim()).toList();
        } else if (line.startsWith('PLACES:')) {
          final placesText = line.replaceFirst('PLACES:', '').trim();
          places = placesText.split(',').map((p) => p.trim()).toList();
        }
      }

      if (foods.isEmpty && places.isEmpty) {
        throw Exception('Unable to parse recommendations');
      }

      setState(() {
        _foods = foods;
        _places = places;
        _showProceedButton = true;
      });
    } catch (_) {
      setState(() {
        _error = 'Error processing recommendations. Please try again.';
      });
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    String name = 'Explorer';
    
    // Get user name from passed Google Sign In user
    if (widget.user?.displayName != null) {
      name = widget.user!.displayName!;
    } else if (widget.user?.email != null) {
      final email = widget.user!.email;
      final emailName = email.split('@')[0];
      // Capitalize first letter
      if (emailName.isNotEmpty) {
        name = emailName[0].toUpperCase() + emailName.substring(1);
      }
    }
    
    final greeting = _getGreeting();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final screenSize = MediaQuery.of(context).size;
    final fontScale = screenSize.width / 400; // Base width for scaling

    return Scaffold(
      backgroundColor: scheme.surface,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.8),
              scheme.secondary.withValues(alpha: 0.6),
              scheme.tertiary.withValues(alpha: 0.4),
            ],
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                scheme.surface.withValues(alpha: 0.1),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header with back and logout buttons
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ).animate().fadeIn(delay: 100.ms, duration: 200.ms).scale(begin: const Offset(0.8, 0.8)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Sign out',
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.logout,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        onPressed: () async {
                          try {
                            await GoogleSignIn.instance.disconnect();
                            await GoogleSignIn.instance.signOut();
                            if (!context.mounted) return;
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const LoginPage()),
                              (route) => false,
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          }
                        },
                      ).animate().fadeIn(delay: 150.ms, duration: 200.ms).scale(begin: const Offset(0.8, 0.8)),
                    ],
                  ),
                ),
                // Header content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.group,
                              color: Colors.white,
                              size: 20,
                            ),
                          ).animate().scale(delay: 200.ms, duration: 200.ms),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$greeting, $name',
                                  style: text.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    fontSize: (text.headlineMedium?.fontSize ?? 28) * 0.65 * fontScale,
                                  ),
                                ).animate().fadeIn(delay: 250.ms, duration: 200.ms).slideX(begin: -0.2),
                                Text(
                                  'Plan perfect group adventures with AI-powered itineraries',
                                  style: text.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.85 * fontScale,
                                  ),
                                ).animate().fadeIn(delay: 300.ms, duration: 200.ms).slideX(begin: -0.2),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
                // Main content section
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 20),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    children: [
            FriendRequestListener(onViewRequests: _openRequests),
            const SizedBox(height: 5),
            // Your Friends section with profile icons
            Builder(builder: (context) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return const SizedBox();
              return StreamBuilder<List<String>>(
                stream: FriendService.friendsOf(uid),
                builder: (context, snap) {
                  final ids = snap.data ?? const <String>[];
                  return FutureBuilder<List<AppUser>>(
                    future: _fetchFriendUsers(ids),
                    builder: (context, fs) {
                      final friends = fs.data ?? const <AppUser>[];
                      if (friends.isEmpty) return const SizedBox();
                      final show = friends.take(3).toList();
                      final overflow = friends.length - show.length;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // "Your Friends" text on the left
                            GestureDetector(
                              onTap: _openAddMembers,
                              child: Text(
                                'Your Friends',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.9 * fontScale,
                                  decoration: TextDecoration.underline,
                                  decorationColor: scheme.primary.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            // Profile icons on the right
                            GestureDetector(
                              onTap: () => _showFriendsBottomSheet(friends, title: 'Your Friends'),
                              child: Builder(builder: (_) {
                                const double radius = 14;
                                const double step = 20; // overlap amount
                                final int count = show.length + (overflow > 0 ? 1 : 0);
                                final double width = radius * 2 + step * (count > 0 ? count - 1 : 0);
                                return SizedBox(
                                  height: radius * 2,
                                  width: width,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      for (int i = 0; i < show.length; i++)
                                        Positioned(
                                          left: i * step,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(color: scheme.surface, width: 2),
                                            ),
                                            child: CircleAvatar(
                                              radius: radius,
                                              backgroundColor: scheme.surfaceContainerHighest,
                                              backgroundImage: show[i].photoUrl != null
                                                  ? NetworkImage(show[i].photoUrl!)
                                                  : null,
                                              child: show[i].photoUrl == null
                                                  ? Icon(Icons.person, size: 14, color: scheme.onSurfaceVariant)
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      if (overflow > 0)
                                        Positioned(
                                          left: show.length * step,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(color: scheme.surface, width: 2),
                                            ),
                                            child: CircleAvatar(
                                              radius: radius,
                                              backgroundColor: scheme.surfaceContainerHighest,
                                              child: Text(
                                                '+$overflow',
                                                style: text.labelSmall?.copyWith(
                                                  color: scheme.onSurfaceVariant,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            }),
            // Friend search opens on button press only (no inline search bar)
            // Premium action buttons  
            Container(
              margin: const EdgeInsets.only(top: 16, bottom: 22),
              child: Row(
              children: [
                // Add Friends button
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openFriendSearchWithQuery,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_add,
                                size: 22,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Add Friends',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.9 * fontScale,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Add Itinerary Folders button
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _showCreateFolderField ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _showCreateFolderField ? scheme.primary.withValues(alpha: 0.5) : scheme.outline.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _toggleCreateFolder,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add,
                                size: 22,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Add Folder',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.9 * fontScale,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              ),
            ),
            // Friend requests notification (if any)
            Builder(builder: (context) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return const SizedBox();
              return StreamBuilder<List<String>>(
                stream: FriendService.incomingRequestUids(uid),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  if (count == 0) return const SizedBox();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openRequests,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.mail,
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'You have $count friend request${count > 1 ? 's' : ''}',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.9 * fontScale,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: scheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
            // Modern folder creation field
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: _showCreateFolderField
                  ? Container(
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE1E3E1),
                                  width: 1,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x08000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _folderNameCtrl,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: 'Folder name',
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF9AA0A6),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0,
                                  ),
                                  border: InputBorder.none,
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: scheme.primary.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  enabledBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF202124),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0,
                                ),
                                onSubmitted: (_) => _createFolder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            height: 48,
                            width: 48,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.primary.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              onPressed: _createFolder,
                              icon: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Create folder',
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 150.ms).slideY(begin: -0.2)
                  : const SizedBox(),
            ),
            const SizedBox(height: 16),
            // Folders section header
            Text(
              'Itinerary Folders',
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
                fontSize: (text.titleMedium?.fontSize ?? 16) * 0.9 * fontScale,
              ),
            ),
            const SizedBox(height: 8),
                // Stream folders from Firestore
                StreamBuilder<List<GroupFolder>>(
                  stream: FolderService.streamMyFolders(),
                  builder: (context, snapshot) {
                    final folders = snapshot.data ?? const <GroupFolder>[];
                    if (folders.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 56,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No folders yet',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Create your first folder to get started',
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: folders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final f = folders[index];
                        final created = f.createdAt?.toLocal().toString() ?? '';
                        // Shadow _members for subtitle count without affecting class field
                        final _members = f.memberUids;
                        final isDeleting = _deletingFolderId == f.id;
                        
                        return Column(
                          children: [
                            Container(
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: scheme.outline.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Icon(
                              Icons.folder,
                              color: scheme.primary.withValues(alpha: 0.7),
                              size: 28,
                            ),
                            title: Text(
                              f.name,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                                fontSize: (text.titleSmall?.fontSize ?? 14) * 0.9 * fontScale,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Created ${created.split(' ')[0]} • ${_members.length} members',
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: (text.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                ),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FutureBuilder<List<AppUser>>(
                                  future: _fetchFriendUsers(f.memberUids),
                                  builder: (context, snap) {
                                    final all = (snap.data ?? const <AppUser>[]);
                                    if (all.isEmpty) return const SizedBox();
                                    final show = all.take(3).toList();
                                    final overflow = all.length - show.length;
                                    return GestureDetector(
                                      onTap: () => _showFriendsBottomSheet(all, title: '${f.name} Members'),
                                      child: Row(
                                      children: [
                                        for (int i = 0; i < show.length; i++) ...[
                                          if (i > 0) const SizedBox(width: 4),
                                          CircleAvatar(
                                            radius: 12,
                                            backgroundImage: show[i].photoUrl != null ? NetworkImage(show[i].photoUrl!) : null,
                                            child: show[i].photoUrl == null ? const Icon(Icons.person, size: 16) : null,
                                          ),
                                        ],
                                        if (overflow > 0) ...[
                                          const SizedBox(width: 4),
                                          CircleAvatar(
                                            radius: 12,
                                            backgroundColor: scheme.primaryContainer,
                                            child: Text(
                                              '$overflow',
                                              style: text.labelSmall?.copyWith(
                                                color: scheme.onPrimaryContainer,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 8),
                                      ],
                                    ),
                                    );
                                  },
                                ),
                                StreamBuilder<List<String>>(
                                  stream: () {
                                    final uid = FirebaseAuth.instance.currentUser?.uid;
                                    if (uid == null) {
                                      return const Stream<List<String>>.empty();
                                    }
                                    return FriendService.friendsOf(uid);
                                  }(),
                                  builder: (context, snap) {
                                    final friendIds = snap.data ?? const <String>[];
                                    final hasEligible = friendIds.any((id) => !f.memberUids.contains(id));
                                    if (!hasEligible) return const SizedBox.shrink();
                                    return IconButton(
                                      tooltip: 'Add friends',
                                      icon: const Icon(Icons.person_add_alt_1),
                                      color: scheme.primary,
                                      iconSize: 26,
                                      padding: const EdgeInsets.all(8),
                                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                      onPressed: () => _addFriendsToFolder(f),
                                    );
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GroupFolderDetailPage(
                                    name: f.name,
                                    members: this._members,
                                    user: widget.user,
                                  ),
                                ),
                              );
                            },
                            onLongPress: () => _showDeleteConfirmation(f),
                          ),
                        ),
                        // Inline delete confirmation
                        AnimatedSize(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          child: isDeleting
                              ? Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.red.shade200,
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.warning_amber,
                                            color: Colors.red.shade600,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Delete "${f.name}"?',
                                              style: text.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: Colors.red.shade700,
                                                fontSize: (text.titleSmall?.fontSize ?? 14) * 0.9 * fontScale,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'This action cannot be undone.',
                                        style: text.bodySmall?.copyWith(
                                          color: Colors.red.shade600,
                                          fontSize: (text.bodySmall?.fontSize ?? 12) * 0.9 * fontScale,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: _cancelDelete,
                                            style: TextButton.styleFrom(
                                              foregroundColor: scheme.onSurfaceVariant,
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            ),
                                            child: Text(
                                              'Cancel',
                                              style: TextStyle(
                                                fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.9 * fontScale,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () => _confirmDeleteFolder(f),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red.shade600,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            child: Text(
                                              'Delete',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.9 * fontScale,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ).animate().fadeIn(duration: 150.ms).slideY(begin: -0.3)
                              : const SizedBox(),
                        ),
                      ],
                    );
                      },
                    );
                  },
                ),
                            const SizedBox(height: 20),
                            
                            // moved to top: see row above folders
                            const SizedBox.shrink(),

                            // Removed "Your Friends" container (requested)
                            const SizedBox.shrink(),
                            // Removed "Where is your group going?" container
                            const SizedBox.shrink(),
                            
                            const SizedBox(height: 20),
                            
                            // Error display
                            if (_error != null) ...[ 
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: text.bodyMedium?.copyWith(
                                          color: Colors.red.shade600,
                                          fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.85 * fontScale,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ).animate().fadeIn(duration: 200.ms).shake(),
                            ],
                            
                            // Delight Moments Display - Only show during loading
                            if (_loading && (_foods.isEmpty && _places.isEmpty)) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.purple.shade100.withValues(alpha: 0.5),
                                      Colors.pink.shade100.withValues(alpha: 0.3),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.purple.shade200,
                                  ),
                                ),
                                child: ValueListenableBuilder<String>(
                                  valueListenable: _delightMomentNotifier,
                                  builder: (context, delightMoment, child) {
                                    return Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.purple.shade400,
                                                Colors.pink.shade400,
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons.auto_awesome,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            delightMoment.isNotEmpty ? delightMoment : 'Planning group adventure...',
                                            style: text.bodyMedium?.copyWith(
                                              color: Colors.purple.shade700,
                                              fontWeight: FontWeight.w500,
                                              fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.85 * fontScale,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.2),
                            ],
                            
                            // Results Section
                            if (_places.isNotEmpty || _foods.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              // Places Section
                              if (_places.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.blue.shade400,
                                            Colors.purple.shade400,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.place, color: Colors.white, size: 16),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Group-Friendly Places',
                                      style: text.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface,
                                        fontSize: (text.titleMedium?.fontSize ?? 16) * 0.85 * fontScale,
                                      ),
                                    ),
                                  ],
                                ).animate().fadeIn(delay: 200.ms, duration: 300.ms).slideX(begin: -0.3),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _places.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final place = entry.value;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.blue.shade50,
                                            Colors.purple.shade50,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.blue.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        place,
                                        style: text.bodySmall?.copyWith(
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.w500,
                                          fontSize: (text.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                        ),
                                      ),
                                    ).animate().fadeIn(delay: (300 + index * 100).ms, duration: 300.ms).scale(begin: const Offset(0.8, 0.8));
                                  }).toList(),
                                ),
                                const SizedBox(height: 24),
                              ],
                              
                              // Foods Section
                              if (_foods.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.orange.shade400,
                                            Colors.red.shade400,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.restaurant, color: Colors.white, size: 16),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Group Dining Options',
                                      style: text.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface,
                                        fontSize: (text.titleMedium?.fontSize ?? 16) * 0.85 * fontScale,
                                      ),
                                    ),
                                  ],
                                ).animate().fadeIn(delay: 600.ms, duration: 300.ms).slideX(begin: -0.3),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _foods.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final food = entry.value;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.orange.shade50,
                                            Colors.red.shade50,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.orange.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        food,
                                        style: text.bodySmall?.copyWith(
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.w500,
                                          fontSize: (text.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                        ),
                                      ),
                                    ).animate().fadeIn(delay: (700 + index * 100).ms, duration: 300.ms).scale(begin: const Offset(0.8, 0.8));
                                  }).toList(),
                                ),
                                const SizedBox(height: 32),
                              ],
                              
                              // Proceed Button
                              if (_showProceedButton)
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => ItineraryPage(
                                            destination: _destinationCtrl.text.trim(),
                                            foods: _foods,
                                            places: _places,
                                            user: widget.user,
                                          ),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.purple.shade400,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 4,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Create Group Itinerary',
                                          style: text.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontSize: (text.titleMedium?.fontSize ?? 16) * 0.85 * fontScale,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                                      ],
                                    ),
                                  ),
                                ).animate().fadeIn(delay: 1000.ms, duration: 400.ms).slideY(begin: 0.3),
                            ],
                    ],
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupFolder {
  final String name;
  final DateTime createdAt;
  _GroupFolder({required this.name, required this.createdAt});
}

class _RequestsBadgeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RequestsBadgeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<List<String>>(
      stream: FriendService.incomingRequestUids(uid),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            TextButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.mail_outline),
              label: const Text('Requests'),
            ),
            if (count > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                  child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
          ],
        );
      },
    );
  }
}
