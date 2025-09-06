import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;

class ItineraryPage extends StatefulWidget {
  final String destination;
  final List<String> foods;
  final List<String> places;
  final GoogleSignInAccount? user;

  const ItineraryPage({
    super.key,
    required this.destination,
    required this.foods,
    required this.places,
    this.user,
  });

  @override
  State<ItineraryPage> createState() => _ItineraryPageState();
}

class _ItineraryPageState extends State<ItineraryPage> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  LatLng _centerLocation = const LatLng(33.4734, -111.9010); // Default Scottsdale
  
  bool _isLoadingItinerary = true;
  String _loadingMessage = 'Initializing your perfect trip...';
  double _loadingProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeItinerary();
  }

  Future<void> _initializeItinerary() async {
    setState(() {
      _isLoadingItinerary = true;
      _loadingMessage = 'Analyzing your preferences...';
      _loadingProgress = 0.1;
    });
    
    await _getDestinationCoordinates();
    
    setState(() {
      _loadingMessage = 'Getting AI recommendations for ${widget.destination}...';
      _loadingProgress = 0.3;
    });
    
    await _addPlaceMarkers();
    
    setState(() {
      _loadingMessage = 'Mapping out your perfect locations...';
      _loadingProgress = 0.8;
    });
    
    // Small delay to show the mapping message
    await Future.delayed(const Duration(milliseconds: 800));
    
    setState(() {
      _isLoadingItinerary = false;
      _loadingProgress = 1.0;
    });
    
    // Adjust camera after loading is complete
    Future.delayed(const Duration(milliseconds: 300), () {
      _adjustCameraToBounds();
    });
  }

  Future<void> _getDestinationCoordinates() async {
    try {
      // Comprehensive city coordinates mapping
      Map<String, LatLng> destinationCoords = {
        'paris': const LatLng(48.8566, 2.3522),
        'tokyo': const LatLng(35.6762, 139.6503),
        'new york': const LatLng(40.7128, -74.0060),
        'london': const LatLng(51.5074, -0.1278),
        'rome': const LatLng(41.9028, 12.4964),
        'barcelona': const LatLng(41.3851, 2.1734),
        'amsterdam': const LatLng(52.3676, 4.9041),
        'dubai': const LatLng(25.2048, 55.2708),
        'singapore': const LatLng(1.3521, 103.8198),
        'sydney': const LatLng(-33.8688, 151.2093),
        'bangkok': const LatLng(13.7563, 100.5018),
        'istanbul': const LatLng(41.0082, 28.9784),
        'berlin': const LatLng(52.5200, 13.4050),
        'vienna': const LatLng(48.2082, 16.3738),
        'prague': const LatLng(50.0755, 14.4378),
        'venice': const LatLng(45.4408, 12.3155),
        'santorini': const LatLng(36.3932, 25.4615),
        'bali': const LatLng(-8.3405, 115.0920),
        'scottsdale': const LatLng(33.4734, -111.9010),
        'mumbai': const LatLng(19.0760, 72.8777),
        'delhi': const LatLng(28.7041, 77.1025),
        'bangalore': const LatLng(12.9716, 77.5946),
        'kolkata': const LatLng(22.5726, 88.3639),
        'chennai': const LatLng(13.0827, 80.2707),
        'jaipur': const LatLng(26.9124, 75.7873),
        'goa': const LatLng(15.2993, 74.1240),
        'kerala': const LatLng(10.8505, 76.2711),
        'agra': const LatLng(27.1767, 78.0081),
        'varanasi': const LatLng(25.3176, 82.9739),
      };
      
      String searchKey = widget.destination.toLowerCase();
      LatLng coords = destinationCoords[searchKey] ?? const LatLng(33.4734, -111.9010);
      
      setState(() {
        _centerLocation = coords;
      });
    } catch (e) {
      // Use default location if anything fails
      setState(() {
        _centerLocation = const LatLng(33.4734, -111.9010);
      });
    }
  }




  Future<void> _addPlaceMarkers() async {
    // Use Gemini AI to get specific place recommendations
    setState(() {
      _loadingMessage = 'AI is selecting perfect places for you...';
      _loadingProgress = 0.4;
    });
    
    final recommendations = await _getGeminiRecommendations();
    
    setState(() {
      _loadingMessage = 'Finding exact locations on the map...';
      _loadingProgress = 0.6;
    });
    
    // Get coordinates for AI-recommended landmarks
    final landmarks = recommendations['landmarks'] ?? [];
    for (int i = 0; i < landmarks.length && i < 6; i++) {
      final landmark = landmarks[i];
      
      setState(() {
        _loadingMessage = 'Locating ${landmark}...';
        _loadingProgress = 0.6 + (i * 0.05);
      });
      
      final coords = await _getCoordinatesForPlace(landmark, widget.destination);
      
      if (coords != null) {
        final marker = Marker(
          markerId: MarkerId('landmark_$i'),
          position: coords,
          infoWindow: InfoWindow(
            title: landmark,
            snippet: 'AI-recommended for your interests',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
        );
        
        _markers.add(marker);
      }
    }
    
    setState(() {
      _loadingMessage = 'Finding perfect restaurants...';
      _loadingProgress = 0.75;
    });
    
    // Get coordinates for AI-recommended restaurants
    final restaurants = recommendations['restaurants'] ?? [];
    for (int i = 0; i < restaurants.length && i < 5; i++) {
      final restaurant = restaurants[i];
      
      setState(() {
        _loadingMessage = 'Locating ${restaurant}...';
        _loadingProgress = 0.75 + (i * 0.02);
      });
      
      final coords = await _getCoordinatesForPlace(restaurant, widget.destination);
      
      if (coords != null) {
        final marker = Marker(
          markerId: MarkerId('restaurant_$i'),
          position: coords,
          infoWindow: InfoWindow(
            title: restaurant,
            snippet: 'Perfect for your food preferences',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        );
        
        _markers.add(marker);
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<Map<String, List<String>>> _getGeminiRecommendations() async {
    try {
      final model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.5-flash',
      );

      final prompt = '''
Based on the user's preferences for ${widget.destination}, recommend SPECIFIC landmarks and restaurants that exist in ${widget.destination}.

User's Place Interests: ${widget.places.join(', ')}
User's Food Interests: ${widget.foods.join(', ')}
Destination: ${widget.destination}

Provide EXACT names of real places that exist in ${widget.destination}. Be very specific with actual place names that can be found on Google Maps.

Return ONLY in this exact format:
LANDMARKS: Big Ben, Tower Bridge, Westminster Abbey, British Museum, Hyde Park
RESTAURANTS: Dishoom, Sketch, Rules Restaurant, Gordon Ramsay Hell's Kitchen, The Ivy

Requirements:
- Provide 5-8 specific landmark names that actually exist in ${widget.destination}
- Provide 4-6 specific restaurant names that actually exist in ${widget.destination}  
- Match recommendations to the user's stated interests
- Use real, famous, well-known places only
- Be precise with naming (use official names that appear on Google Maps)
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final content = response.text ?? '';
      
      return _parseGeminiRecommendations(content);
    } catch (e) {
      print('Gemini error: $e');
      // Fallback to default recommendations if AI fails
      return _getFallbackRecommendations();
    }
  }

  Map<String, List<String>> _parseGeminiRecommendations(String response) {
    List<String> landmarks = [];
    List<String> restaurants = [];
    
    final lines = response.split('\n');
    for (final line in lines) {
      if (line.startsWith('LANDMARKS:')) {
        final landmarksText = line.replaceFirst('LANDMARKS:', '').trim();
        landmarks = landmarksText.split(',').map((l) => l.trim()).toList();
      } else if (line.startsWith('RESTAURANTS:')) {
        final restaurantsText = line.replaceFirst('RESTAURANTS:', '').trim();
        restaurants = restaurantsText.split(',').map((r) => r.trim()).toList();
      }
    }
    
    return {
      'landmarks': landmarks,
      'restaurants': restaurants,
    };
  }

  Map<String, List<String>> _getFallbackRecommendations() {
    // Fallback recommendations based on destination
    String city = widget.destination.toLowerCase();
    
    switch (city) {
      case 'london':
        return {
          'landmarks': ['Big Ben', 'Tower Bridge', 'London Eye', 'Buckingham Palace', 'British Museum'],
          'restaurants': ['Dishoom', 'Sketch', 'Rules Restaurant', 'The Ivy', 'Gordon Ramsay Hell\'s Kitchen']
        };
      case 'paris':
        return {
          'landmarks': ['Eiffel Tower', 'Louvre Museum', 'Notre-Dame Cathedral', 'Arc de Triomphe', 'Champs-Élysées'],
          'restaurants': ['L\'As du Fallafel', 'Le Comptoir du Relais', 'Breizh Café', 'L\'Ami Jean', 'Bistrot Paul Bert']
        };
      case 'mumbai':
        return {
          'landmarks': ['Gateway of India', 'Marine Drive', 'Elephanta Caves', 'Chhatrapati Shivaji Terminus', 'Haji Ali Dargah'],
          'restaurants': ['Trishna', 'Britannia & Co.', 'Leopold Cafe', 'Bademiya', 'Khyber Restaurant']
        };
      case 'tokyo':
        return {
          'landmarks': ['Tokyo Tower', 'Senso-ji Temple', 'Shibuya Crossing', 'Meiji Shrine', 'Tokyo Skytree'],
          'restaurants': ['Jiro Sushi', 'Kozasa Sushi', 'Ramen Yashichi', 'Tonkatsu Maisen', 'Nabezo']
        };
      case 'new york':
        return {
          'landmarks': ['Statue of Liberty', 'Times Square', 'Central Park', 'Brooklyn Bridge', 'Empire State Building'],
          'restaurants': ['Katz\'s Delicatessen', 'Joe\'s Pizza', 'Peter Luger', 'Xi\'an Famous Foods', 'Levain Bakery']
        };
      case 'rome':
        return {
          'landmarks': ['Colosseum', 'Vatican City', 'Trevi Fountain', 'Roman Forum', 'Pantheon'],
          'restaurants': ['Da Enzo', 'Trattoria Monti', 'Pizzarium', 'Ginger Sapori', 'Il Sorpasso']
        };
      default:
        return {
          'landmarks': ['City Center', 'Main Square', 'Historic District', 'Central Park', 'Museum District'],
          'restaurants': ['Local Restaurant', 'Traditional Cuisine', 'Popular Eatery', 'Street Food Market', 'Fine Dining']
        };
    }
  }


  Future<LatLng?> _getCoordinatesForPlace(String placeName, String cityName) async {
    try {
      // Use Google Maps Geocoding API to find coordinates for specific places
      final query = '$placeName, $cityName';
      final encodedQuery = Uri.encodeComponent(query);
      
      // Using the same Google Maps API that's already integrated with the app
      // This uses the built-in geocoding functionality
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedQuery&key=AIzaSyCLgimggRuRcKCEUE0mmYm00AC18bg8O58'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        
        if (results.isNotEmpty) {
          final location = results[0]['geometry']['location'];
          return LatLng(location['lat'], location['lng']);
        }
      }
    } catch (e) {
      print('Error geocoding $placeName: $e');
    }
    
    // Fallback: generate coordinates around city center with some variation
    double offsetLat = (placeName.hashCode % 400 - 200) * 0.001;
    double offsetLng = ((placeName.hashCode ~/ 100) % 400 - 200) * 0.001;
    
    return LatLng(
      _centerLocation.latitude + offsetLat,
      _centerLocation.longitude + offsetLng,
    );
  }

  void _adjustCameraToBounds() {
    if (_markers.isEmpty || _mapController == null) return;

    // Calculate bounds that include all markers
    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLng = _markers.first.position.longitude;

    for (Marker marker in _markers) {
      minLat = minLat < marker.position.latitude ? minLat : marker.position.latitude;
      maxLat = maxLat > marker.position.latitude ? maxLat : marker.position.latitude;
      minLng = minLng < marker.position.longitude ? minLng : marker.position.longitude;
      maxLng = maxLng > marker.position.longitude ? maxLng : marker.position.longitude;
    }

    // Add padding to bounds
    double latPadding = (maxLat - minLat) * 0.3;
    double lngPadding = (maxLng - minLng) * 0.3;

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat - latPadding, minLng - lngPadding),
      northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
    );

    // Animate camera to show all markers
    Future.delayed(const Duration(milliseconds: 500), () {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100.0),
      );
    });
  }

  Widget _buildLoadingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Creating Your Itinerary',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        
        // Loading container
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              // AI Animation Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ).animate(
                onPlay: (controller) => controller.repeat(),
              ).shimmer(
                duration: 2000.ms,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
              ),
              
              const SizedBox(height: 24),
              
              // Progress bar
              Container(
                width: double.infinity,
                height: 8,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _loadingProgress,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Loading message
              Text(
                _loadingMessage,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              Text(
                'AI is analyzing your preferences to find the perfect spots',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 24),
              
              // User preferences reminder
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ...widget.places.map((place) => ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.4,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        place,
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )),
                  ...widget.foods.map((food) => ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.4,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        food,
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.2),
      ],
    );
  }

  Widget _buildMapView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your AI-Curated Itinerary',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 400,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                // Adjust bounds after map is created
                Future.delayed(const Duration(seconds: 1), () {
                  _adjustCameraToBounds();
                });
              },
              initialCameraPosition: CameraPosition(
                target: _centerLocation,
                zoom: 13, // Initial zoom, will be adjusted to show all markers
              ),
              markers: _markers,
              zoomControlsEnabled: true,
              mapToolbarEnabled: true,
              myLocationButtonEnabled: false,
              compassEnabled: true,
              onTap: (LatLng position) {
                // Hide any open info windows when tapping the map
              },
            ),
          ),
        ).animate().fadeIn(duration: 1000.ms).scale(begin: const Offset(0.95, 0.95)),
        
        const SizedBox(height: 16),
        
        // Legend showing all places
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI-Recommended Places',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Show AI-recommended landmarks
                  ..._markers.where((marker) => marker.markerId.value.startsWith('landmark_')).map((marker) => ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_balance,
                            size: 16,
                            color: Colors.blue.shade600,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              marker.infoWindow.title ?? 'Landmark',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
                  // Show AI-recommended restaurants
                  ..._markers.where((marker) => marker.markerId.value.startsWith('restaurant_')).map((marker) => ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.restaurant,
                            size: 16,
                            color: Colors.red.shade600,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              marker.infoWindow.title ?? 'Restaurant',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 1200.ms).slideY(begin: 0.1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          widget.destination,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero section with title and image
            Container(
              width: double.infinity,
              height: 300,
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Background image placeholder
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.secondary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  // Overlay gradient
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  // Title
                  Positioned(
                    bottom: 30,
                    left: 30,
                    right: 30,
                    child: Text(
                      '${widget.destination}: Where adventure meets luxury',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.3),

            // Loading state or Map view
            Padding(
              padding: const EdgeInsets.all(20),
              child: _isLoadingItinerary ? _buildLoadingView() : _buildMapView(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}