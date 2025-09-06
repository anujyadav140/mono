import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_page.dart';
import 'itinerary_page.dart';

class HomePage extends StatefulWidget {
  final GoogleSignInAccount? user;
  
  const HomePage({super.key, this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _destinationCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  final StreamController<String> _summaryStream = StreamController<String>.broadcast();
  
  List<String> _places = [];
  List<String> _foods = [];
  bool _showProceedButton = false;
  final ValueNotifier<String> _delightMomentNotifier = ValueNotifier<String>('');
  bool _hasSearchedOnce = false;
  
  final List<String> _suggestions = [
    'Paris', 'Tokyo', 'New York', 'London', 'Rome', 'Barcelona', 
    'Amsterdam', 'Dubai', 'Singapore', 'Sydney', 'Bangkok', 'Istanbul',
    'Berlin', 'Vienna', 'Prague', 'Venice', 'Santorini', 'Bali'
  ];
  
  String _generateDelightMoment(String destination, String phase) {
    switch (phase) {
      case 'start':
        return 'Analyzing your travel preferences for $destination...';
      case 'data':
        return 'Processing data from travel blogs and reviews...';
      case 'thinking':
        return 'Cross-referencing local favorites with your taste profile...';
      case 'results':
        return 'Curating personalized recommendations just for you...';
      default:
        return 'Working on something special for your $destination trip...';
    }
  }

  @override
  void dispose() {
    _summaryStream.close();
    _destinationCtrl.dispose();
    _delightMomentNotifier.dispose();
    super.dispose();
  }
  
  void _showDelightMoment(String destination, String phase) {
    _delightMomentNotifier.value = _generateDelightMoment(destination, phase);
    
    // Clear after 2.5 seconds
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _delightMomentNotifier.value = '';
      }
    });
  }

  Future<void> _runCombinedSummary() async {
    final destination = _destinationCtrl.text.trim();
    
    // Check if search is empty and show toast
    if (destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a destination to search'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    FocusScope.of(context).unfocus(); // Hide keyboard
    setState(() {
      _loading = true;
      _error = null;
      _foods.clear();
      _places.clear();
      _showProceedButton = false;
      _hasSearchedOnce = true;
    });
    _summaryStream.add('');
    try {
      // Show initial delight moment
      _showDelightMoment(destination, 'start');
      
      // 1. Get raw data from Exa API
      final callable = FirebaseFunctions.instance.httpsCallable('exaSummaryCallable');
      final resp = await callable.call(<String, dynamic>{'destination': destination});
      final Map data = resp.data as Map;
      final String exaSummary = (data['summary'] ?? '').toString();
      
      if (exaSummary.isEmpty) {
        _summaryStream.add('No summary available.');
        return;
      }
      
      // Show another delight moment after getting data
      await Future.delayed(const Duration(milliseconds: 1500));
      _showDelightMoment(destination, 'data');
      
      // 2. Use Gemini to create personalized travel recommendations
      final model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.5-flash',
      );
      
      final prompt = '''
Based on the user's preferences below, extract foods and places (be as accurate as possible, but try to infer things too) that the user would like in $destination. Be very concise.

User Preferences:
$exaSummary

Return ONLY in this exact format:
FOODS: Italian Pizza, French Pastries, Sushi, Street Tacos, Gelato
PLACES: Art Museums, Historic Districts, Parks, Rooftop Bars, Local Markets
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final geminiSummary = response.text ?? '';
      
      // Show final delight moment before presenting results
      await Future.delayed(const Duration(milliseconds: 800));
      _showDelightMoment(destination, 'results');
      
      // Parse the response to extract foods and places
      _parseGeminiResponse(geminiSummary);
    } catch (e) {
      _summaryStream.add('');
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _parseGeminiResponse(String response) {
    try {
      final lines = response.split('\n');
      for (final line in lines) {
        if (line.startsWith('FOODS:')) {
          final foodsText = line.replaceFirst('FOODS:', '').trim();
          _foods = foodsText.split(',').map((f) => f.trim()).toList();
        } else if (line.startsWith('PLACES:')) {
          final placesText = line.replaceFirst('PLACES:', '').trim();
          _places = placesText.split(',').map((p) => p.trim()).toList();
        }
      }
      
      if (_foods.isNotEmpty || _places.isNotEmpty) {
        _showProceedButton = false; // Will be shown after animations
        _startAnimations();
      } else {
        _summaryStream.add('Unable to parse recommendations. Please try again.');
      }
    } catch (e) {
      _summaryStream.add('Error processing recommendations. Please try again.');
    }
  }

  void _startAnimations() {
    _summaryStream.add(''); // Clear any existing content
    
    // Show delight moment when animations start
    Future.delayed(const Duration(milliseconds: 500), () {
      _showDelightMoment(_destinationCtrl.text.trim(), 'thinking');
    });
    
    // Show proceed button after a delay
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _showProceedButton = true;
        });
      }
    });
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

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: false, // Prevent overflow when keyboard appears
      appBar: AppBar(
        title: Text(
          'Mono Moments',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Sign out',
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.logout, size: 20),
              ),
              onPressed: () async {
                try {
                  // Disconnect and sign out from Google Sign In completely
                  await GoogleSignIn.instance.disconnect();
                  await GoogleSignIn.instance.signOut();
                  
                  if (!context.mounted) return;
                  // Navigate back to login page
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Sign out failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting Section
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.travel_explore_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ).animate().scale(delay: 150.ms, duration: 400.ms),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting $name!',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideX(begin: -0.2),
                          Text(
                            'Plan your perfect trip with hyper-personalized itinerary',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideX(begin: -0.2),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2),
              const SizedBox(height: 24),
              // Destination Search
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text == '') {
                    return const Iterable<String>.empty();
                  }
                  return _suggestions.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  _destinationCtrl.text = selection;
                },
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  _destinationCtrl.addListener(() {
                    controller.text = _destinationCtrl.text;
                  });
                  controller.addListener(() {
                    _destinationCtrl.text = controller.text;
                  });
                  
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Where would you like to explore?',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: Container(
                        margin: const EdgeInsets.all(4),
                        child: ElevatedButton(
                          onPressed: _loading ? null : _runCombinedSummary,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            minimumSize: const Size(0, 40),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text('Search'),
                        ),
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _loading ? null : _runCombinedSummary(),
                    onEditingComplete: onEditingComplete,
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              title: Text(option),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ).animate().fadeIn(delay: 150.ms, duration: 400.ms).slideY(begin: 0.2),
              const SizedBox(height: 20),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms).shake(),
              // Delight Moments Display - Only show during loading, hide when results are shown
              if (_loading && (_foods.isEmpty && _places.isEmpty))
                SizedBox(
                  height: 88, // Fixed height to reserve space for full card with padding and margins
                  child: ValueListenableBuilder<String>(
                    valueListenable: _delightMomentNotifier,
                    builder: (context, delightMoment, child) {
                      if (delightMoment.isEmpty) return const SizedBox.shrink();
                      
                      return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            delightMoment,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.2);
                    },
                  ),
                ),
              
              // AI Recommendations Section
              Expanded(
                child: !_hasSearchedOnce
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60.0),
                          child: Column(
                            children: [
                              Icon(
                                Icons.travel_explore_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Search for a destination above',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Get AI-powered travel recommendations',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _loading
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 60.0),
                              child: Column(
                                children: [
                                  CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Finding perfect recommendations...',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Foods Section
                            if (_foods.isNotEmpty) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.restaurant_rounded,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Foods You\'ll Love',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideX(begin: -0.3),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _foods.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final food = entry.value;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.restaurant,
                                          size: 16,
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          food,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ).animate().fadeIn(delay: (300 + index * 100).ms, duration: 500.ms).scale(begin: const Offset(0.8, 0.8));
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                            ],
                            // Places Section
                            if (_places.isNotEmpty) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.place_rounded,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Places You\'ll Enjoy',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ).animate().fadeIn(delay: 800.ms, duration: 500.ms).slideX(begin: -0.3),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _places.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final place = entry.value;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          size: 16,
                                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          place,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ).animate().fadeIn(delay: (900 + index * 100).ms, duration: 500.ms).scale(begin: const Offset(0.8, 0.8));
                                }).toList(),
                              ),
                              const SizedBox(height: 32),
                            ],
                            // Proceed Button
                            if (_showProceedButton)
                              Center(
                                child: ElevatedButton(
                                  onPressed: () {
                                    // Navigate to itinerary page
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
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                  ),
                                  child: const Text(
                                    'Proceed',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ).animate().fadeIn(delay: 1500.ms, duration: 600.ms).slideY(begin: 0.3),
                          ],
                        ),
                      ),
              ).animate().fadeIn(delay: 250.ms, duration: 400.ms).slideY(begin: 0.3),
            ],
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
