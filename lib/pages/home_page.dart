import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import '../firebase_options.dart';
import 'login_page.dart';
import 'itinerary_page.dart';
import 'itinerary_choice_page.dart';

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
        return 'Working on something special for your 4-day $destination adventure...';
    }
  }

  Stream<String> _generateStream(String destination) async* {
    final phases = ['start', 'data', 'thinking', 'results'];
    
    for (int i = 0; i < phases.length; i++) {
      await Future.delayed(Duration(milliseconds: 800 + (i * 200)));
      _delightMomentNotifier.value = _generateDelightMoment(destination, phases[i]);
      yield phases[i];
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  void dispose() {
    _destinationCtrl.dispose();
    _summaryStream.close();
    _delightMomentNotifier.dispose();
    super.dispose();
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
        _delightMomentNotifier.value = 'Finalizing your personalized recommendations...';
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

      // Use Gemini to extract FOODS / PLACES
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

      // Parse and update state
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
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => ItineraryChoicePage(user: widget.user)),
                        ),
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
                              Icons.travel_explore,
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
                                  'Plan your perfect 4-day adventure with hyper-personalized itinerary',
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
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const SizedBox(height: 5),
                            // Destination Search
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  scheme.surfaceContainer.withValues(alpha: 0.5),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: scheme.outline.withValues(alpha: 0.1),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Where to?',
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                    fontSize: (text.titleMedium?.fontSize ?? 16) * 0.85 * fontScale,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Autocomplete<String>(
                                        initialValue: TextEditingValue(text: _destinationCtrl.text),
                                        optionsBuilder: (TextEditingValue textEditingValue) {
                                          if (textEditingValue.text.isEmpty) {
                                            return const Iterable<String>.empty();
                                          }
                                          return _suggestions.where((String option) {
                                            return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                                          });
                                        },
                                        onSelected: (String selection) {
                                          _destinationCtrl.text = selection;
                                        },
                                        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                                          textEditingController.text = _destinationCtrl.text;
                                          textEditingController.selection = TextSelection.fromPosition(
                                            TextPosition(offset: textEditingController.text.length),
                                          );
                                          
                                          return TextField(
                                            controller: textEditingController,
                                            focusNode: focusNode,
                                            onChanged: (value) => _destinationCtrl.text = value,
                                            onSubmitted: (_) => _submitDestination(),
                                            decoration: InputDecoration(
                                              hintText: 'e.g., Paris, Tokyo, New York',
                                              hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                                              filled: true,
                                              fillColor: scheme.surfaceContainer.withValues(alpha: 0.3),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide.none,
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            ),
                                          );
                                        },
                                      ).animate().fadeIn(delay: 350.ms, duration: 200.ms).slideY(begin: 0.2),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            scheme.primary,
                                            scheme.primary.withValues(alpha: 0.8),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: scheme.primary.withValues(alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(24),
                                          onTap: _loading ? null : _submitDestination,
                                          child: Center(
                                            child: _loading
                                                ? SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                    ),
                                                  )
                                                : Icon(
                                                    Icons.send,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ).animate().fadeIn(delay: 400.ms, duration: 200.ms).scale(begin: const Offset(0.8, 0.8)),
                                  ],
                                ),
                              ],
                            ),
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // Error display
                            if (_error != null)
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
                          
                          // Delight Moments Display - Only show during loading
                          if (_loading && (_foods.isEmpty && _places.isEmpty))
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    scheme.primaryContainer.withValues(alpha: 0.3),
                                    scheme.secondaryContainer.withValues(alpha: 0.2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: 0.2),
                                ),
                              ),
                              child: ValueListenableBuilder<String>(
                                valueListenable: _delightMomentNotifier,
                                builder: (context, delightMoment, child) {
                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  scheme.primary,
                                                  scheme.primary.withValues(alpha: 0.7),
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
                                              delightMoment.isNotEmpty ? delightMoment : 'Preparing your adventure...',
                                              style: text.bodyMedium?.copyWith(
                                                color: scheme.onSurface,
                                                fontWeight: FontWeight.w500,
                                                fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.85 * fontScale,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.2),
                          
                          // Results Section
                          if (_places.isNotEmpty || _foods.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                            'Recommended Places',
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
                                            'Local Cuisines to Try',
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
                                            backgroundColor: scheme.primary,
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
                                                'Create Full Itinerary',
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
                            ),
                          ],
                        ],
                        ),
                      ),
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
