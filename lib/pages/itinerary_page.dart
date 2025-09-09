import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
  
  Uint8List? _destinationImageBytes;
  List<String> _tripTypes = [];
  String _tripDescription = '';
  bool _isStreamingDescription = false;
  String _tripTitle = '';
  bool _isStreamingTitle = false;
  List<Map<String, dynamic>> _timelineItems = [];
  Map<String, List<Map<String, dynamic>>> _timelineByDay = {};

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
    
    // Fetch destination image and coordinates in parallel
    await Future.wait([
      _getDestinationCoordinates(),
      _fetchDestinationImage(),
    ]);
    
    setState(() {
      _loadingMessage = 'Getting AI recommendations for ${widget.destination}...';
      _loadingProgress = 0.3;
    });
    
    // Generate title and chips while places are being mapped
    await Future.wait([
      _addPlaceMarkers(),
      _generateTripTypes(),
      _streamTripTitle(),
    ]);
    
    // Generate timeline with Google Maps data
    await _generateTimeline();
    
    setState(() {
      _loadingMessage = 'Finalizing your perfect itinerary...';
      _loadingProgress = 0.9;
    });
    
    // Small delay to show the finalizing message
    await Future.delayed(const Duration(milliseconds: 300));
    
    setState(() {
      _isLoadingItinerary = false;
      _loadingProgress = 1.0;
    });
    
    // Start streaming trip description after page loads
    Future.delayed(const Duration(milliseconds: 500), () {
      _streamTripDescription();
    });
    
    // Adjust camera after loading is complete
    Future.delayed(const Duration(milliseconds: 300), () {
      _adjustCameraToBounds();
    });
  }

  Future<void> _shareItinerary() async {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Generating PDF...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Create PDF document
      final pdf = pw.Document();
      
      // Helper function to download images for PDF
      Future<pw.MemoryImage?> downloadImageForPdf(String? imageUrl) async {
        if (imageUrl == null) return null;
        try {
          final response = await http.get(Uri.parse(imageUrl));
          if (response.statusCode == 200) {
            return pw.MemoryImage(response.bodyBytes);
          }
        } catch (e) {
          print('Error downloading image for PDF: $e');
        }
        return null;
      }

      // Pre-download all images for timeline items
      Map<String, pw.MemoryImage?> downloadedImages = {};
      for (final dayEntry in _timelineByDay.entries) {
        for (final item in dayEntry.value) {
          if (item['image'] != null) {
            final image = await downloadImageForPdf(item['image']);
            if (image != null) {
              downloadedImages[item['image']] = image;
            }
          }
        }
      }

      // Calculate dynamic page height based on content
      double estimatedHeight = 1000 + (_timelineByDay.length * 300) + (_timelineByDay.values.fold(0, (sum, items) => sum + items.length) * 400);
      
      // Create custom long page format
      final customPageFormat = PdfPageFormat(
        PdfPageFormat.a4.width,
        estimatedHeight,
        marginAll: 20,
      );

      // Build single long PDF page
      pdf.addPage(
        pw.Page(
          pageFormat: customPageFormat,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header with Mono Moments branding
              pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Text(
                  'Mono Moments',
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
            // Header
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    widget.destination.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 28,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  if (_tripTitle.isNotEmpty) ...[
                    pw.Text(
                      _tripTitle,
                      style: pw.TextStyle(
                        fontSize: 18,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Trip Types
            if (_tripTypes.isNotEmpty) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Trip Themes',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      _tripTypes.join(' • '),
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],

            // Trip Description
            if (_tripDescription.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Overview',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      _tripDescription,
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                        lineSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
            ],

            // Daily Itinerary
            pw.Text(
              'Daily Itinerary',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
            pw.SizedBox(height: 16),

            // Timeline items
            for (final dayEntry in _timelineByDay.entries) ...[
              pw.Container(
                width: double.infinity,
                margin: const pw.EdgeInsets.only(bottom: 20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Day header
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.blue700,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        'Day ${dayEntry.key}',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 12),

                    // Day items
                    for (final item in dayEntry.value) ...[
                      pw.Container(
                        margin: const pw.EdgeInsets.only(bottom: 16),
                        padding: const pw.EdgeInsets.all(16),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300),
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            // Time and Title
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Expanded(
                                  flex: 3,
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      if (item['time'] != null) ...[
                                        pw.Text(
                                          item['time'],
                                          style: pw.TextStyle(
                                            fontSize: 12,
                                            color: PdfColors.blue600,
                                            fontWeight: pw.FontWeight.bold,
                                          ),
                                        ),
                                        pw.SizedBox(height: 4),
                                      ],
                                      pw.Text(
                                        item['title'] ?? 'Place',
                                        style: pw.TextStyle(
                                          fontSize: 16,
                                          fontWeight: pw.FontWeight.bold,
                                          color: PdfColors.grey800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item['image'] != null && downloadedImages[item['image']] != null) ...[
                                  pw.SizedBox(width: 12),
                                  pw.Container(
                                    width: 80,
                                    height: 60,
                                    decoration: pw.BoxDecoration(
                                      borderRadius: pw.BorderRadius.circular(8),
                                    ),
                                    child: pw.ClipRRect(
                                      child: pw.Image(
                                        downloadedImages[item['image']]!,
                                        fit: pw.BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            pw.SizedBox(height: 8),

                            // Rating and location
                            if (item['rating'] != null && item['rating'].toString().isNotEmpty) ...[
                              pw.Row(
                                children: [
                                  pw.Text('Rating: ', style: pw.TextStyle(color: PdfColors.orange, fontWeight: pw.FontWeight.bold)),
                                  pw.Text(
                                    '${item['rating']}/5',
                                    style: pw.TextStyle(
                                      fontSize: 12,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                  if (item['review_count'] != null) ...[
                                    pw.SizedBox(width: 8),
                                    pw.Text(
                                      '(${item['review_count']} reviews)',
                                      style: const pw.TextStyle(
                                        fontSize: 11,
                                        color: PdfColors.grey600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              pw.SizedBox(height: 4),
                            ],

                            if (item['location'] != null) ...[
                              pw.Text(
                                'Location: ${item['location']}',
                                style: const pw.TextStyle(
                                  fontSize: 11,
                                  color: PdfColors.grey600,
                                ),
                              ),
                              pw.SizedBox(height: 8),
                            ],

                            // Description
                            if (item['description'] != null && item['description'].toString().isNotEmpty) ...[
                              pw.Text(
                                item['description'],
                                style: const pw.TextStyle(
                                  fontSize: 11,
                                  color: PdfColors.grey700,
                                  lineSpacing: 1.3,
                                ),
                              ),
                            ],

                            // Price
                            if (item['price'] != null && item['price'].toString().isNotEmpty) ...[
                              pw.SizedBox(height: 8),
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.green100,
                                  borderRadius: pw.BorderRadius.circular(4),
                                ),
                                child: pw.Text(
                                  '${item['price']}',
                                  style: pw.TextStyle(
                                    fontSize: 11,
                                    color: PdfColors.green800,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Footer
            pw.SizedBox(height: 20),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 12),
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    'Generated by Mono Moments',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue700,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Your AI Travel Companion',
                    style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      );

      // Save PDF
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${widget.destination}_Itinerary.pdf');
      await file.writeAsBytes(await pdf.save());

      // Share PDF
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out my ${widget.destination} itinerary!',
        subject: '${widget.destination} Travel Itinerary',
      );

    } catch (e) {
      print('Error sharing itinerary PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
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
Based on the user's preferences for ${widget.destination}, recommend SPECIFIC landmarks and restaurants for a complete 4-DAY TRIP itinerary.

User's Place Interests: ${widget.places.join(', ')}
User's Food Interests: ${widget.foods.join(', ')}
Destination: ${widget.destination}

Provide EXACT names of real places that exist in ${widget.destination}. Be very specific with actual place names that can be found on Google Maps.

Return ONLY in this exact format:
LANDMARKS: Big Ben, Tower Bridge, Westminster Abbey, British Museum, Hyde Park, Buckingham Palace, Covent Garden, Camden Market, Greenwich, Notting Hill, St. Paul's Cathedral, Tate Modern
RESTAURANTS: Dishoom, Sketch, Rules Restaurant, Gordon Ramsay Hell's Kitchen, The Ivy, Padella, Duck & Waffle, Hawksmoor, Clos Maggiore, Barrafina

Requirements:
- Provide 12-16 specific landmark names for 4 days of exploration (3-4 per day)
- Provide 8-12 specific restaurant names for 4 days of dining (2-3 per day)
- Include mix of major attractions, cultural sites, and hidden gems
- Match recommendations to the user's stated interests
- Use real, famous, well-known places only
- Consider geographic distribution for logical daily groupings
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


  Future<void> _fetchDestinationImage() async {
    try {
      setState(() {
        _loadingMessage = 'AI is creating the perfect image for ${widget.destination}...';
        _loadingProgress = 0.15;
      });
      
      // Use Gemini Vertex AI to generate destination image
      final model = FirebaseAI.vertexAI(location: 'global').generativeModel(
        model: 'gemini-2.5-flash-image-preview',
        generationConfig: GenerationConfig(
          responseModalities: [ResponseModalities.text, ResponseModalities.image],
        ),
      );

      final prompt = '''
Generate a beautiful, high-quality travel photograph of ${widget.destination}.

Style requirements:
- Professional travel photography
- Golden hour or beautiful lighting
- Iconic landmarks and architecture of ${widget.destination}
- Vibrant colors and crisp details
- Travel magazine quality
- Scenic composition showing the essence of ${widget.destination}

Show the most recognizable and beautiful aspects of ${widget.destination} that would inspire travelers to visit.
''';

      final response = await model.generateContent([Content.text(prompt)]);
      
      if (response.inlineDataParts.isNotEmpty) {
        setState(() {
          _destinationImageBytes = response.inlineDataParts.first.bytes;
        });
      }
    } catch (e) {
      print('Error generating destination image with AI: $e');
      // Keep both image bytes and URL as null for fallback gradient
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

  Future<void> _generateTripTypes() async {
    try {
      final model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.5-flash',
      );

      final prompt = '''
Based on the user's preferences for their trip to ${widget.destination}, generate 3 trip type labels.

User's Place Interests: ${widget.places.join(', ')}
User's Food Interests: ${widget.foods.join(', ')}
Destination: ${widget.destination}

Requirements:
- Generate exactly 3 trip type labels
- Each label should be 1-2 words maximum
- Labels should reflect the user's interests and destination
- Make them catchy and descriptive
- Examples: Cultural, Adventure, Culinary, Shopping, Relaxation, Nightlife, Historic, Scenic, Luxury, Local

Return ONLY the 3 labels separated by commas, nothing else.
Example: Cultural, Culinary, Adventure
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final content = response.text?.trim() ?? '';
      
      // Parse the response
      List<String> types = content.split(',').map((type) => type.trim()).toList();
      
      // Ensure we have exactly 3 types
      if (types.length > 3) {
        types = types.take(3).toList();
      } else if (types.length < 3) {
        // Add fallback types if needed
        final fallbackTypes = ['Cultural', 'Adventure', 'Scenic'];
        while (types.length < 3 && fallbackTypes.isNotEmpty) {
          final fallback = fallbackTypes.removeAt(0);
          if (!types.contains(fallback)) {
            types.add(fallback);
          }
        }
      }
      
      setState(() {
        _tripTypes = types;
      });
    } catch (e) {
      print('Error generating trip types: $e');
      // Fallback to default trip types
      setState(() {
        _tripTypes = ['Cultural', 'Adventure', 'Culinary'];
      });
    }
  }

  Future<void> _streamTripTitle() async {
    setState(() {
      _isStreamingTitle = true;
      _tripTitle = '';
    });
    
    try {
      final model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.5-flash',
      );

      final prompt = '''
Create a catchy, exciting one-liner title for a trip to ${widget.destination}.

User's interests: ${widget.places.join(', ')}
Food preferences: ${widget.foods.join(', ')}

Requirements:
- Must be catchy and exciting
- Should capture the essence of ${widget.destination}
- Maximum 6-8 words
- Should feel personal and adventurous
- Examples: "Magical Nights in Paris Await", "Tokyo Dreams Come Alive", "Bangkok Adventures Unleashed"

Return ONLY the title, nothing else.
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final content = response.text?.trim() ?? '';
      
      // Simulate streaming effect by adding text gradually
      final words = content.split(' ');
      for (int i = 0; i < words.length; i++) {
        if (mounted) {
          setState(() {
            _tripTitle = words.take(i + 1).join(' ');
          });
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }
    } catch (e) {
      print('Error streaming title: $e');
      setState(() {
        _tripTitle = 'Amazing Adventures in ${widget.destination}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStreamingTitle = false;
        });
      }
    }
  }

  Future<void> _streamTripDescription() async {
    setState(() {
      _isStreamingDescription = true;
      _tripDescription = '';
    });
    
    try {
      final model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.5-flash',
      );

      final landmarkNames = _markers
          .where((m) => m.markerId.value.startsWith('landmark_'))
          .map((m) => m.infoWindow.title ?? '')
          .where((title) => title.isNotEmpty)
          .toList();
      
      final restaurantNames = _markers
          .where((m) => m.markerId.value.startsWith('restaurant_'))
          .map((m) => m.infoWindow.title ?? '')
          .where((title) => title.isNotEmpty)
          .toList();

      final prompt = '''
Write a single inspiring paragraph for ${widget.destination} based on these AI-curated recommendations.

Landmarks to visit: ${landmarkNames.join(', ')}
Restaurants to try: ${restaurantNames.join(', ')}
User's interests: ${widget.places.join(', ')} (places), ${widget.foods.join(', ')} (food)

Write ONLY 1 paragraph (1-3 sentences) that:
1. Captures the essence and adventure of visiting ${widget.destination}
2. Mentions specific landmarks and restaurants from the lists
3. Connects the recommendations to the user's interests
4. Uses an inspiring, travel-magazine style tone
5. Makes it feel personal and exciting

Requirements:
- EXACTLY 1 paragraph only
- Maximum 3 sentences
- Keep it concise and impactful
- No line breaks or multiple paragraphs
- Be specific about ${widget.destination} and the recommended places
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final content = response.text ?? '';
      
      // Simulate streaming effect by adding text gradually
      final words = content.split(' ');
      for (int i = 0; i < words.length; i++) {
        if (mounted) {
          setState(() {
            _tripDescription = words.take(i + 1).join(' ');
          });
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    } catch (e) {
      print('Error streaming description: $e');
      setState(() {
        _tripDescription = 'Discover the magic of ${widget.destination} with our AI-curated selection of must-visit landmarks and incredible dining experiences. From iconic attractions to hidden gems, this journey promises unforgettable memories tailored to your unique interests and preferences.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStreamingDescription = false;
        });
      }
    }
  }

  Future<void> _generateTimeline() async {
    try {
      print('Timeline: Starting timeline generation...');
      print('Timeline: Current markers count: ${_markers.length}');
      
      // Get all the places that are actually mapped on the map
      final landmarkMarkers = _markers.where((marker) => marker.markerId.value.startsWith('landmark_')).toList();
      final restaurantMarkers = _markers.where((marker) => marker.markerId.value.startsWith('restaurant_')).toList();
      
      List<String> mappedLandmarks = landmarkMarkers.map((marker) => marker.infoWindow.title ?? '').where((title) => title.isNotEmpty).toList();
      List<String> mappedRestaurants = restaurantMarkers.map((marker) => marker.infoWindow.title ?? '').where((title) => title.isNotEmpty).toList();
      
      print('Timeline: Found ${mappedLandmarks.length} landmarks and ${mappedRestaurants.length} restaurants');
      print('Timeline: Landmarks: $mappedLandmarks');
      print('Timeline: Restaurants: $mappedRestaurants');
      
      if (mappedLandmarks.isEmpty && mappedRestaurants.isEmpty) {
        print('Timeline: No mapped places available, creating fallback timeline');
        // Create a fallback timeline with sample data for 4 days
        final fallbackTimelineByDay = _createFallbackTimelineByDay();
        setState(() {
          _timelineByDay = fallbackTimelineByDay;
          // For backward compatibility, keep the combined list
          _timelineItems = [];
          fallbackTimelineByDay.values.forEach((dayItems) => _timelineItems.addAll(dayItems));
        });
        return;
      }
      
      // Use Gemini AI to structure these exact places into a proper daily itinerary
      final structuredItinerary = await _structureItineraryWithGemini(mappedLandmarks, mappedRestaurants);
      
      Map<String, List<Map<String, dynamic>>> timelineByDay = {};
      
      // Create timeline items organized by day
      for (final scheduleItem in structuredItinerary) {
        final dayNumber = scheduleItem['day'] ?? '1';
        final placeName = scheduleItem['place'];
        final placeType = scheduleItem['type']; // 'attraction' or 'restaurant'
        final timeSlot = scheduleItem['time'];
        
        // Initialize day list if not exists
        timelineByDay[dayNumber] ??= [];
        
        // Get detailed information for this exact place
        if (placeName != null && placeType != null && timeSlot != null) {
          final placeDetails = await _getPlaceDetails(placeName, widget.destination);
          if (placeDetails != null) {
            timelineByDay[dayNumber]!.add({
              'type': placeType,
              'time': timeSlot,
              'title': placeDetails['name'] ?? placeName,
              'description': placeDetails['description'] ?? _generateContextualDescription(placeName, placeType, timeSlot),
              'image': placeDetails['image'],
              'rating': placeDetails['rating'],
              'review_count': placeDetails['review_count'],
              'reviews': placeDetails['reviews'] ?? [],
              'location': placeDetails['location'] ?? widget.destination,
              'price': placeDetails['price'],
              'opening_hours': placeDetails['opening_hours'],
              'phone_number': placeDetails['phone_number'],
              'website': placeDetails['website'],
              'business_status': placeDetails['business_status'],
              'google_maps_url': placeDetails['google_maps_url'],
              'icon': placeType == 'restaurant' ? Icons.restaurant : Icons.camera_alt,
            });
          } else {
            // If detailed place API failed, try to get basic info from text search
            final basicInfo = await _getBasicPlaceInfo(placeName, widget.destination);
            timelineByDay[dayNumber]!.add({
              'type': placeType,
              'time': timeSlot,
              'title': placeName,
              'description': basicInfo['description'] ?? 'Discover this amazing place in ${widget.destination}.',
              'image': basicInfo['image'],
              'rating': basicInfo['rating'],
              'review_count': basicInfo['review_count'],
              'reviews': [],
              'location': basicInfo['address'] ?? '$placeName, ${widget.destination}',
              'price': null,
              'opening_hours': null,
              'phone_number': null,
              'website': null,
              'business_status': 'OPERATIONAL',
              'google_maps_url': null,
              'icon': placeType == 'restaurant' ? Icons.restaurant : Icons.camera_alt,
            });
          }
        }
      }
      
      print('Timeline: Generated timeline for ${timelineByDay.keys.length} days');
      
      // Count total items across all days
      int totalItems = timelineByDay.values.fold(0, (sum, dayItems) => sum + dayItems.length);
      
      // If we didn't get sufficient timeline data, use fallback
      if (timelineByDay.isEmpty || totalItems < 4) { // Require at least 1 item per day
        print('Timeline: Generated timeline has insufficient data ($totalItems items), using fallback');
        final fallbackTimelineByDay = _createFallbackTimelineByDay();
        setState(() {
          _timelineByDay = fallbackTimelineByDay;
          _timelineItems = [];
          fallbackTimelineByDay.values.forEach((dayItems) => _timelineItems.addAll(dayItems));
        });
      } else {
        setState(() {
          _timelineByDay = timelineByDay;
          // For backward compatibility, keep the combined list
          _timelineItems = [];
          timelineByDay.values.forEach((dayItems) => _timelineItems.addAll(dayItems));
        });
      }
    } catch (e) {
      print('Error generating timeline: $e');
      // Fallback to default timeline on any error
      final fallbackTimelineByDay = _createFallbackTimelineByDay();
      setState(() {
        _timelineByDay = fallbackTimelineByDay;
        _timelineItems = [];
        fallbackTimelineByDay.values.forEach((dayItems) => _timelineItems.addAll(dayItems));
      });
    }
  }

  Future<List<Map<String, String>>> _structureItineraryWithGemini(List<String> landmarks, List<String> restaurants) async {
    try {
      final model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.5-flash',
      );

      final prompt = '''
You are a travel itinerary planner. Structure these EXACT places (that are already mapped on Google Maps) into a perfect 4-DAY itinerary for ${widget.destination}.

MAPPED ATTRACTIONS: ${landmarks.join(', ')}
MAPPED RESTAURANTS: ${restaurants.join(', ')}

IMPORTANT: Use ONLY the places listed above. Do not add any new places.

Structure them into a logical 4-day itinerary with geographic clustering and appropriate time slots. Consider:
- Distribute places evenly across 4 days (3-4 attractions + 2-3 restaurants per day)
- Group places that are geographically close together on the same day
- Start each day with morning activities
- Include lunch/meal breaks at mapped restaurants
- End each day with evening activities
- Ensure logical flow and reasonable travel times

Return ONLY in this exact format (one line per place):
DAY: 1 | PLACE: [exact place name] | TYPE: attraction | TIME: Morning exploration
DAY: 1 | PLACE: [exact place name] | TYPE: restaurant | TIME: Lunch break
DAY: 2 | PLACE: [exact place name] | TYPE: attraction | TIME: Morning adventure
DAY: 2 | PLACE: [exact place name] | TYPE: restaurant | TIME: Dinner experience

Use these exact time labels:
- Morning exploration, Morning adventure, Morning discovery
- Lunch break, Afternoon snack, Light meal
- Afternoon adventure, Afternoon exploration, Afternoon discovery  
- Dinner experience, Evening dining, Evening meal

Arrange ALL the mapped places (${landmarks.length + restaurants.length} total places) logically across 4 days.
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final content = response.text ?? '';
      
      return _parseItineraryStructure(content);
    } catch (e) {
      print('Error structuring itinerary: $e');
      // Fallback: create simple structure with mapped places
      return _createFallbackStructure(landmarks, restaurants);
    }
  }

  List<Map<String, String>> _parseItineraryStructure(String response) {
    List<Map<String, String>> schedule = [];
    final lines = response.split('\n');
    
    for (final line in lines) {
      if (line.contains('DAY:') && line.contains('PLACE:') && line.contains('TYPE:') && line.contains('TIME:')) {
        final parts = line.split('|');
        if (parts.length >= 4) {
          final day = parts[0].replaceFirst('DAY:', '').trim();
          final place = parts[1].replaceFirst('PLACE:', '').trim();
          final type = parts[2].replaceFirst('TYPE:', '').trim();
          final time = parts[3].replaceFirst('TIME:', '').trim();
          
          // Only add if all values are non-empty
          if (day.isNotEmpty && place.isNotEmpty && type.isNotEmpty && time.isNotEmpty) {
            schedule.add({
              'day': day,
              'place': place,
              'type': type,
              'time': time,
            });
          }
        }
      }
    }
    
    return schedule;
  }

  List<Map<String, String>> _createFallbackStructure(List<String> landmarks, List<String> restaurants) {
    List<Map<String, String>> schedule = [];
    
    // Distribute places across 4 days
    final landmarkGroups = <List<String>>[];
    final restaurantGroups = <List<String>>[];
    
    // Divide landmarks into 4 groups
    for (int day = 0; day < 4; day++) {
      landmarkGroups.add([]);
      restaurantGroups.add([]);
    }
    
    // Distribute landmarks evenly across 4 days
    for (int i = 0; i < landmarks.length; i++) {
      landmarkGroups[i % 4].add(landmarks[i]);
    }
    
    // Distribute restaurants evenly across 4 days
    for (int i = 0; i < restaurants.length; i++) {
      restaurantGroups[i % 4].add(restaurants[i]);
    }
    
    // Create schedule for each day
    for (int day = 0; day < 4; day++) {
      final dayNumber = (day + 1).toString();
      final dayLandmarks = landmarkGroups[day];
      final dayRestaurants = restaurantGroups[day];
      
      // Morning attractions
      for (int i = 0; i < dayLandmarks.length && i < 2; i++) {
        schedule.add({
          'day': dayNumber,
          'place': dayLandmarks[i],
          'type': 'attraction',
          'time': i == 0 ? 'Morning exploration' : 'Morning adventure',
        });
      }
      
      // Lunch
      if (dayRestaurants.isNotEmpty) {
        schedule.add({
          'day': dayNumber,
          'place': dayRestaurants[0],
          'type': 'restaurant',
          'time': 'Lunch break',
        });
      }
      
      // Afternoon attractions
      for (int i = 2; i < dayLandmarks.length; i++) {
        schedule.add({
          'day': dayNumber,
          'place': dayLandmarks[i],
          'type': 'attraction',
          'time': 'Afternoon adventure',
        });
      }
      
      // Dinner
      if (dayRestaurants.length > 1) {
        schedule.add({
          'day': dayNumber,
          'place': dayRestaurants[1],
          'type': 'restaurant',
          'time': 'Evening dining',
        });
      }
    }
    
    return schedule;
  }

  Map<String, List<Map<String, dynamic>>> _createFallbackTimelineByDay() {
    return {
      '1': [
        {
          'type': 'attraction',
          'time': 'Morning exploration',
          'title': 'Historic City Center',
          'description': 'Start your ${widget.destination} adventure by exploring the historic heart of the city. Discover architectural marvels and immerse yourself in local culture.',
          'image': null,
          'rating': null,
          'review_count': null,
          'reviews': [],
          'location': widget.destination,
          'price': 'Free',
          'opening_hours': null,
          'phone_number': null,
          'website': null,
          'business_status': 'OPERATIONAL',
          'google_maps_url': null,
          'icon': Icons.camera_alt,
        },
        {
          'type': 'restaurant',
          'time': 'Lunch break',
          'title': 'Local Cuisine Restaurant',
          'description': 'Enjoy authentic local flavors at this recommended dining spot, perfect for experiencing the culinary traditions of ${widget.destination}.',
          'image': null,
          'rating': null,
          'review_count': null,
          'reviews': [],
          'location': widget.destination,
          'price': '\$\$',
          'opening_hours': null,
          'phone_number': null,
          'website': null,
          'business_status': 'OPERATIONAL',
          'google_maps_url': null,
          'icon': Icons.restaurant,
        },
        {
          'type': 'attraction',
          'time': 'Afternoon adventure',
          'title': 'Cultural Landmark',
          'description': 'Continue your journey with a visit to this significant cultural site that showcases the rich heritage of ${widget.destination}.',
          'image': null,
          'rating': null,
          'review_count': null,
          'reviews': [],
          'location': widget.destination,
          'price': '\$',
          'icon': Icons.camera_alt,
        },
      ],
      '2': [
        {
          'type': 'attraction',
          'time': 'Morning adventure',
          'title': 'Art District',
          'description': 'Explore the vibrant art scene and galleries that define the creative spirit of ${widget.destination}.',
          'image': null,
          'rating': null,
          'review_count': null,
          'reviews': [],
          'location': widget.destination,
          'price': '\$',
          'icon': Icons.camera_alt,
        },
        {
          'type': 'restaurant',
          'time': 'Evening dining',
          'title': 'Rooftop Restaurant',
          'description': 'Experience fine dining with panoramic views of ${widget.destination} skyline.',
          'image': null,
          'rating': null,
          'review_count': null,
          'reviews': [],
          'location': widget.destination,
          'price': '\$\$\$',
          'opening_hours': null,
          'phone_number': null,
          'website': null,
          'business_status': 'OPERATIONAL',
          'google_maps_url': null,
          'icon': Icons.restaurant,
        },
      ],
      '3': [
        {
          'type': 'attraction',
          'time': 'Morning discovery',
          'title': 'Natural Wonder',
          'description': 'Connect with nature at this beautiful natural attraction that showcases the scenic beauty of ${widget.destination}.',
          'image': null,
          'rating': null,
          'review_count': null,
          'reviews': [],
          'location': widget.destination,
          'price': 'Free',
          'opening_hours': null,
          'phone_number': null,
          'website': null,
          'business_status': 'OPERATIONAL',
          'google_maps_url': null,
          'icon': Icons.camera_alt,
        },
        {
          'type': 'restaurant',
          'time': 'Lunch break',
          'title': 'Street Food Market',
          'description': 'Dive into authentic street food culture and taste the flavors that locals love.',
          'image': null,
          'rating': null,
          'review_count': null,
          'reviews': [],
          'location': widget.destination,
          'price': '\$',
          'opening_hours': null,
          'phone_number': null,
          'website': null,
          'business_status': 'OPERATIONAL',
          'google_maps_url': null,
          'icon': Icons.restaurant,
        },
      ],
      '4': [
        {
          'type': 'attraction',
          'time': 'Morning exploration',
          'title': 'Waterfront Promenade',
          'description': 'Take a leisurely stroll along the waterfront and soak in the maritime atmosphere of ${widget.destination}.',
          'image': null,
          'rating': null,
          'review_count': null,
          'reviews': [],
          'location': widget.destination,
          'price': 'Free',
          'opening_hours': null,
          'phone_number': null,
          'website': null,
          'business_status': 'OPERATIONAL',
          'google_maps_url': null,
          'icon': Icons.camera_alt,
        },
        {
          'type': 'restaurant',
          'time': 'Dinner experience',
          'title': 'Farewell Feast',
          'description': 'End your 4-day ${widget.destination} adventure with a memorable farewell dinner featuring signature local dishes.',
          'image': null,
          'rating': null,
          'review_count': null,
          'reviews': [],
          'location': widget.destination,
          'price': '\$\$\$',
          'opening_hours': null,
          'phone_number': null,
          'website': null,
          'business_status': 'OPERATIONAL',
          'google_maps_url': null,
          'icon': Icons.restaurant,
        },
      ],
    };
  }

  String _generateContextualDescription(String placeName, String type, String timeSlot) {
    if (type == 'restaurant') {
      if (timeSlot.toLowerCase().contains('lunch') || timeSlot.toLowerCase().contains('afternoon')) {
        return 'Perfect spot for a delicious meal break during your ${widget.destination} adventure. Enjoy authentic local flavors and recharge for the rest of your day.';
      } else {
        return 'End your day with an exceptional dining experience. This carefully selected restaurant offers the perfect atmosphere to savor the culinary delights of ${widget.destination}.';
      }
    } else {
      if (timeSlot.toLowerCase().contains('morning')) {
        return 'Start your ${widget.destination} adventure at this captivating destination. Perfect for morning exploration when the crowds are lighter and the light is ideal for photography.';
      } else if (timeSlot.toLowerCase().contains('afternoon')) {
        return 'Continue your journey with this remarkable attraction. Ideal for afternoon exploration, offering rich history and stunning views that define the essence of ${widget.destination}.';
      } else {
        return 'Conclude your day at this magnificent location. The perfect evening setting to reflect on your ${widget.destination} experience and capture those golden hour moments.';
      }
    }
  }

  Future<Map<String, dynamic>> _getBasicPlaceInfo(String placeName, String cityName) async {
    try {
      // Use Google Places text search for basic info
      final query = '$placeName, $cityName';
      final encodedQuery = Uri.encodeComponent(query);
      
      final searchUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=$encodedQuery&key=AIzaSyCLgimggRuRcKCEUE0mmYm00AC18bg8O58'
      );
      
      final response = await http.get(searchUrl);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        
        if (results.isNotEmpty) {
          final place = results[0];
          final placeId = place['place_id'];
          
          // Get detailed info including editorial summary in parallel
          final detailsFuture = _getPlaceEditorialSummary(placeId);
          
          // Get basic photo if available
          String? photoUrl;
          if (place['photos'] != null && (place['photos'] as List).isNotEmpty) {
            final photos = place['photos'] as List;
            if (photos.isNotEmpty && photos[0]['photo_reference'] != null) {
              final photoReference = photos[0]['photo_reference'];
              photoUrl = 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&maxheight=600&photo_reference=$photoReference&key=AIzaSyCLgimggRuRcKCEUE0mmYm00AC18bg8O58';
            }
          }
          
          // Wait for editorial summary
          final editorialSummary = await detailsFuture;
          
          return {
            'address': place['formatted_address'] ?? '$placeName, $cityName',
            'image': photoUrl,
            'rating': place['rating'] != null ? double.tryParse(place['rating'].toString())?.toStringAsFixed(1) : null,
            'review_count': place['user_ratings_total']?.toString(),
            'description': editorialSummary ?? 'Experience this unique destination in $cityName.',
          };
        }
      }
    } catch (e) {
      print('Error getting basic place info for $placeName: $e');
    }
    
    // Return basic fallback info
    return {
      'address': '$placeName, $cityName',
      'image': null,
      'rating': null,
      'review_count': null,
      'description': 'Discover this amazing place in $cityName.',
    };
  }

  Future<String?> _getPlaceEditorialSummary(String placeId) async {
    try {
      final detailsUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=editorial_summary&key=AIzaSyCLgimggRuRcKCEUE0mmYm00AC18bg8O58'
      );
      
      final response = await http.get(detailsUrl);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['result'];
        
        if (result != null && result['editorial_summary'] != null && result['editorial_summary']['overview'] != null) {
          return result['editorial_summary']['overview'];
        }
      }
    } catch (e) {
      print('Error getting editorial summary for place: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getPlaceDetails(String placeName, String cityName) async {
    try {
      // Use Google Places API for detailed information
      final query = '$placeName, $cityName';
      final encodedQuery = Uri.encodeComponent(query);
      
      // First, get place details from Places API
      final searchUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=$encodedQuery&key=AIzaSyCLgimggRuRcKCEUE0mmYm00AC18bg8O58'
      );
      
      final response = await http.get(searchUrl);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        
        if (results.isNotEmpty) {
          final place = results[0];
          final placeId = place['place_id'];
          
          // Get detailed information including photos, reviews, editorial summary, and additional data
          final detailsUrl = Uri.parse(
            'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=name,rating,user_ratings_total,formatted_address,photos,types,price_level,editorial_summary,reviews,opening_hours,phone_number,website,business_status,url&key=AIzaSyCLgimggRuRcKCEUE0mmYm00AC18bg8O58'
          );
          
          final detailsResponse = await http.get(detailsUrl);
          
          if (detailsResponse.statusCode == 200) {
            final detailsData = json.decode(detailsResponse.body);
            final result = detailsData['result'];
            
            // Get photo if available from Google Places API
            String? photoUrl;
            if (result['photos'] != null && (result['photos'] as List).isNotEmpty) {
              final photos = result['photos'] as List;
              if (photos.isNotEmpty && photos[0]['photo_reference'] != null) {
                final photoReference = photos[0]['photo_reference'];
                photoUrl = 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&maxheight=600&photo_reference=$photoReference&key=AIzaSyCLgimggRuRcKCEUE0mmYm00AC18bg8O58';
              }
            }
            
            // Get description from Google's editorial summary (About section)
            String description = 'Discover this amazing destination and experience its unique charm.';
            if (result['editorial_summary'] != null && result['editorial_summary']['overview'] != null) {
              description = result['editorial_summary']['overview'];
            } else {
              // If no editorial summary, fetch more details to get About section
              print('No editorial summary for ${result['name']}, fetching additional details...');
            }
            
            // Process reviews data
            List<Map<String, dynamic>> reviewsList = [];
            if (result['reviews'] != null) {
              final reviews = result['reviews'] as List;
              reviewsList = reviews.take(5).map((review) => {
                'author_name': review['author_name'] ?? 'Anonymous',
                'rating': review['rating'] ?? 5,
                'text': review['text'] ?? '',
                'time': review['time'] ?? 0,
                'profile_photo_url': review['profile_photo_url'],
              }).cast<Map<String, dynamic>>().toList();
            }

            // Process opening hours
            Map<String, dynamic>? openingHours;
            if (result['opening_hours'] != null) {
              openingHours = {
                'open_now': result['opening_hours']['open_now'] ?? false,
                'weekday_text': result['opening_hours']['weekday_text'] ?? [],
              };
            }

            return {
              'name': result['name'],
              'rating': result['rating'] != null ? double.tryParse(result['rating'].toString())?.toStringAsFixed(1) : null,
              'review_count': result['user_ratings_total']?.toString() ?? '0',
              'location': result['formatted_address'],
              'image': photoUrl,
              'price': _getPriceLevel(result['price_level']),
              'description': description,
              'reviews': reviewsList,
              'opening_hours': openingHours,
              'phone_number': result['phone_number'],
              'website': result['website'],
              'business_status': result['business_status'] ?? 'OPERATIONAL',
              'google_maps_url': result['url'],
            };
          }
        }
      }
      return null;
    } catch (e) {
      print('Error getting place details for $placeName: $e');
      // Return null so the timeline generation can handle the failure properly
      return null;
    }
  }

  String _getPriceLevel(int? priceLevel) {
    switch (priceLevel) {
      case 0: return 'Free';
      case 1: return '\$';
      case 2: return '\$\$';
      case 3: return '\$\$\$';
      case 4: return '\$\$\$\$';
      default: return '';
    }
  }


  String _generateSpecificPlaceDescription(String? name, List<dynamic>? types, String? address) {
    final placeName = name ?? 'this destination';
    final location = address?.split(',').first ?? widget.destination;
    
    if (types != null && types.isNotEmpty) {
      if (types.contains('tourist_attraction') || types.contains('museum')) {
        return 'Discover the rich history and cultural significance of $placeName. This iconic landmark offers fascinating insights into the heritage of $location, perfect for photography and immersive exploration.';
      } else if (types.contains('restaurant') || types.contains('food') || types.contains('meal_takeaway')) {
        return 'Experience authentic local cuisine at $placeName, a highly regarded dining establishment in $location. Known for exceptional flavors and quality ingredients that showcase the best of the local culinary scene.';
      } else if (types.contains('natural_feature') || types.contains('park')) {
        return 'Immerse yourself in the natural beauty of $placeName. This scenic location in $location offers a peaceful retreat with opportunities for outdoor activities and stunning views.';
      } else if (types.contains('church') || types.contains('place_of_worship')) {
        return 'Visit the magnificent $placeName, a sacred and architecturally significant site in $location. Experience the spiritual atmosphere and admire the stunning religious art and architecture.';
      } else if (types.contains('shopping_mall') || types.contains('store')) {
        return 'Explore $placeName for an excellent shopping experience in $location. Discover local products, souvenirs, and unique items that capture the essence of your destination.';
      } else if (types.contains('night_club') || types.contains('bar')) {
        return 'Experience the vibrant nightlife at $placeName in $location. Enjoy expertly crafted drinks and immerse yourself in the local entertainment scene.';
      }
    }
    return 'Experience the unique charm and distinctive character of $placeName in $location, a special destination carefully selected to match your travel interests and preferences.';
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
    final screenSize = MediaQuery.of(context).size;
    final fontScale = screenSize.width / 400; // Base width for scaling
    
    return Container(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        children: [
          const Spacer(flex: 2),
          
          // Center content
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Large AI Animation Icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 50,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ).animate(
                  onPlay: (controller) => controller.repeat(),
                ).shimmer(
                  duration: 2000.ms,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                ).scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1.1, 1.1),
                  duration: 2000.ms,
                ),
                
                const SizedBox(height: 40),
                
                // Enhanced progress bar
                Container(
                  width: MediaQuery.of(context).size.width * 0.6,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _loadingProgress,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Loading message with better typography
                Text(
                  _loadingMessage,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: (Theme.of(context).textTheme.titleLarge?.fontSize ?? 22) * 0.85 * fontScale,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          // User preferences without card container
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                if (widget.places.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Your Interests',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: (Theme.of(context).textTheme.titleSmall?.fontSize ?? 14) * 0.85 * fontScale,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: widget.places.take(4).map((place) => ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.35,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200, width: 0.5),
                        ),
                        child: Text(
                          place,
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )).toList(),
                  ),
                  if (widget.foods.isNotEmpty) const SizedBox(height: 16),
                ],
                if (widget.foods.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.restaurant,
                        size: 16,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Food Preferences',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: (Theme.of(context).textTheme.titleSmall?.fontSize ?? 14) * 0.85 * fontScale,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: widget.foods.take(4).map((food) => ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.35,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200, width: 0.5),
                        ),
                        child: Text(
                          food,
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ).animate().fadeIn(duration: 1000.ms).slideY(begin: 0.3),
          
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    final screenSize = MediaQuery.of(context).size;
    final fontScale = screenSize.width / 400; // Base width for scaling
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your AI-Curated Itinerary',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: (Theme.of(context).textTheme.titleLarge?.fontSize ?? 22) * 0.85 * fontScale,
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
                      fontSize: (Theme.of(context).textTheme.titleMedium?.fontSize ?? 16) * 0.85 * fontScale,
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

  Widget _buildTimeline() {
    final screenSize = MediaQuery.of(context).size;
    final fontScale = screenSize.width / 400; // Base width for scaling
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Display all 4 days
          if (_timelineByDay.isEmpty) ...[
            // Loading skeleton for timeline
            for (int day = 1; day <= 4; day++) ...[
              // Day header
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ).animate().scale(delay: (100 + day * 150).ms, duration: 400.ms),
                  const SizedBox(width: 8),
                  Text(
                    'Day $day',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: (Theme.of(context).textTheme.titleLarge?.fontSize ?? 22) * 0.85 * fontScale,
                    ),
                  ).animate().fadeIn(delay: (150 + day * 150).ms, duration: 400.ms).slideX(begin: -0.2),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                day == 1 ? "You've landed in ${widget.destination}" : "Exploring more of ${widget.destination}",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: (Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24) * 0.85 * fontScale,
                ),
              ).animate().fadeIn(delay: (200 + day * 150).ms, duration: 400.ms).slideX(begin: -0.2),
              const SizedBox(height: 24),
              
              // Loading skeleton items
              for (int i = 0; i < 3; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timeline line
                    Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                        ).animate(onPlay: (controller) => controller.repeat())
                            .shimmer(duration: 1500.ms, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                        if (i < 2 || day < 4)
                          Container(
                            width: 2,
                            height: 40,
                            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    
                    // Content skeleton
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 100,
                            height: 20,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ).animate(onPlay: (controller) => controller.repeat())
                              .shimmer(duration: 1500.ms, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                          
                          Container(
                            height: 200,
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ).animate(onPlay: (controller) => controller.repeat())
                              .shimmer(duration: 1500.ms, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                        ],
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: (300 + i * 200).ms, duration: 600.ms)
                 .slideX(begin: 0.3, duration: 500.ms)
                 .scale(begin: const Offset(0.9, 0.9), duration: 400.ms),
              ],
              
              if (day < 4) const SizedBox(height: 32),
            ],
          ] else ...[
            // Actual timeline items organized by day
            ...(_timelineByDay.keys.toList()..sort()).asMap().entries.map((dayEntry) {
              final dayIndex = dayEntry.key;
              final dayNumber = dayEntry.value;
              final dayItems = _timelineByDay[dayNumber] ?? [];
              final isLastDay = dayIndex == _timelineByDay.keys.length - 1;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Day header
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ).animate().scale(delay: (100 + dayIndex * 200).ms, duration: 400.ms),
                      const SizedBox(width: 8),
                      Text(
                        'Day $dayNumber',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ).animate().fadeIn(delay: (150 + dayIndex * 200).ms, duration: 400.ms).slideX(begin: -0.2),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dayNumber == '1' ? "You've landed in ${widget.destination}" : "Exploring more of ${widget.destination}",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: (Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24) * 0.85 * fontScale,
                    ),
                  ).animate().fadeIn(delay: (200 + dayIndex * 200).ms, duration: 400.ms).slideX(begin: -0.2),
                  const SizedBox(height: 24),
                  
                  // Timeline items for this day
                  ...dayItems.asMap().entries.map((itemEntry) {
                    final localItemIndex = itemEntry.key;
                    final item = itemEntry.value;
                    final isLastItem = localItemIndex == dayItems.length - 1;
                    final isLastItemOverall = isLastDay && isLastItem;
                    // Calculate global item index across all days
                    final globalItemIndex = dayIndex * 3 + localItemIndex;
                    
                    return _buildTimelineItem(item, isLastItemOverall, globalItemIndex);
                  }).toList(),
                  
                  // Add spacing between days (except after the last day)
                  if (!isLastDay) const SizedBox(height: 32),
                ],
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> item, bool isLast, int itemIndex) {
    final screenSize = MediaQuery.of(context).size;
    final fontScale = screenSize.width / 400; // Base width for scaling
    
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item['type'] == 'restaurant' 
                      ? Colors.orange.shade100 
                      : Colors.blue.shade100,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: item['type'] == 'restaurant' 
                        ? Colors.orange.shade300 
                        : Colors.blue.shade300,
                    width: 2,
                  ),
                ),
                child: Icon(
                  item['icon'] ?? Icons.place,
                  size: 20,
                  color: item['type'] == 'restaurant' 
                      ? Colors.orange.shade600 
                      : Colors.blue.shade600,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
        const SizedBox(width: 16),
        
        // Timeline content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: item['type'] == 'restaurant' 
                      ? Colors.orange.shade50 
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item['time'] ?? 'Activity',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: item['type'] == 'restaurant' 
                        ? Colors.orange.shade700 
                        : Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: (Theme.of(context).textTheme.labelMedium?.fontSize ?? 12) * 0.85 * fontScale,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Content card
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image
                    if (item['image'] != null)
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: Image.network(
                          item['image'],
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 200,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                    Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
                                  ],
                                ),
                              ),
                              child: Icon(
                                item['icon'],
                                size: 60,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            );
                          },
                        ),
                      ),
                    
                    // Content
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Description from Google Maps Platform
                          Text(
                            item['description'] ?? 'Discover this amazing destination.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              height: 1.4,
                              fontSize: (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) * 0.85 * fontScale,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Place info card
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['title'] ?? 'Destination',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontSize: (Theme.of(context).textTheme.titleMedium?.fontSize ?? 16) * 0.85 * fontScale,
                                        ),
                                      ),
                                      if (item['rating'] != null && item['rating'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.star,
                                                  size: 14,
                                                  color: Colors.orange.shade600,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '${item['rating']}/5',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: (Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '(${item['review_count'] ?? '0'} reviews)',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (item['location'] != null) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              size: 14,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                item['location'],
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  fontSize: (Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      // Opening hours status
                                      if (item['opening_hours'] != null) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.access_time,
                                              size: 14,
                                              color: (item['opening_hours']['open_now'] ?? false) 
                                                  ? Colors.green.shade600 
                                                  : Colors.red.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              (item['opening_hours']['open_now'] ?? false) ? 'Open now' : 'Closed',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: (item['opening_hours']['open_now'] ?? false) 
                                                    ? Colors.green.shade600 
                                                    : Colors.red.shade600,
                                                fontWeight: FontWeight.w600,
                                                fontSize: (Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (item['price'] != null && item['price'].isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    item['price'],
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                      fontSize: (Theme.of(context).textTheme.titleLarge?.fontSize ?? 22) * 0.85 * fontScale,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          // Reviews section
                          if (item['reviews'] != null && (item['reviews'] as List).isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
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
                                        Icons.rate_review,
                                        size: 16,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Recent Reviews',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.primary,
                                          fontSize: (Theme.of(context).textTheme.titleSmall?.fontSize ?? 14) * 0.85 * fontScale,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Display up to 3 reviews
                                  ...((item['reviews'] as List).take(3).map((review) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 12,
                                              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                              backgroundImage: review['profile_photo_url'] != null 
                                                  ? NetworkImage(review['profile_photo_url']) 
                                                  : null,
                                              child: review['profile_photo_url'] == null
                                                  ? Icon(
                                                      Icons.person,
                                                      size: 14,
                                                      color: Theme.of(context).colorScheme.primary,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    review['author_name'] ?? 'Anonymous',
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  Row(
                                                    children: List.generate(5, (index) => Icon(
                                                      index < (review['rating'] ?? 5) 
                                                          ? Icons.star 
                                                          : Icons.star_border,
                                                      size: 12,
                                                      color: Colors.orange.shade600,
                                                    )),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (review['text'] != null && review['text'].toString().trim().isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            review['text'].toString().length > 120 
                                                ? '${review['text'].toString().substring(0, 120)}...'
                                                : review['text'].toString(),
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              height: 1.3,
                                              fontSize: (Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  )).toList()),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          
                          // Action buttons
                          Row(
                            children: [
                              // Google Maps button
                              if (item['google_maps_url'] != null) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      // Handle Google Maps action
                                    },
                                    icon: Icon(
                                      Icons.map,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    label: Text(
                                      'Maps',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                    ),
                                  ),
                                ),
                                if (item['website'] != null) const SizedBox(width: 8),
                              ],
                              // Website button
                              if (item['website'] != null) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      // Handle website action
                                    },
                                    icon: Icon(
                                      Icons.language,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    label: Text(
                                      'Website',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                    ),
                                  ),
                                ),
                              ],
                              // If no external links, show details button
                              if (item['google_maps_url'] == null && item['website'] == null) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      // Handle see details action
                                    },
                                    icon: Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    label: Text(
                                      'Details',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    ).animate().fadeIn(delay: (200 + itemIndex * 150).ms, duration: 600.ms)
     .slideX(begin: 0.3, duration: 500.ms)
     .scale(begin: const Offset(0.9, 0.9), duration: 400.ms);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final fontScale = screenSize.width / 400; // Base width for scaling
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.destination,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: (Theme.of(context).textTheme.titleLarge?.fontSize ?? 22) * 0.85 * fontScale,
          ),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? Colors.transparent 
            : Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareItinerary,
          ),
        ],
      ),
      body: _isLoadingItinerary ? _buildLoadingView() : _buildNewItineraryView(),
    );
  }

  Widget _buildNewItineraryView() {
    final screenSize = MediaQuery.of(context).size;
    final fontScale = screenSize.width / 400; // Base width for scaling
    
    return SingleChildScrollView(
      child: Column(
        children: [
          // Hero Image Section
          Container(
            height: MediaQuery.of(context).size.height * 0.6,
            width: double.infinity,
            child: Stack(
              children: [
                // AI-Generated Destination Image
                Container(
                  height: double.infinity,
                  width: double.infinity,
                  child: _destinationImageBytes != null
                      ? Image.memory(
                          _destinationImageBytes!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.secondary,
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Theme.of(context).colorScheme.primary,
                                Theme.of(context).colorScheme.secondary,
                              ],
                            ),
                          ),
                        ),
                ),
                
                // Dark overlay gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
                
                // Content overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Trip type chips
                        if (_tripTypes.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _tripTypes.map((type) => IntrinsicWidth(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  type,
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Dynamic destination title
                        Row(
                          children: [
                            Expanded(
                              child: _tripTitle.isEmpty
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ).animate(onPlay: (controller) => controller.repeat())
                                            .shimmer(duration: 1500.ms, color: Colors.white.withValues(alpha: 0.8)),
                                        const SizedBox(height: 8),
                                        Container(
                                          width: MediaQuery.of(context).size.width * 0.6,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ).animate(onPlay: (controller) => controller.repeat())
                                            .shimmer(duration: 1500.ms, color: Colors.white.withValues(alpha: 0.8)),
                                      ],
                                    )
                                  : Text(
                                      _tripTitle,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                    ),
                            ),
                            if (_isStreamingTitle) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                            ],
                          ],
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // User info with Google profile picture
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.white.withValues(alpha: 0.9),
                              backgroundImage: widget.user?.photoUrl != null 
                                  ? NetworkImage(widget.user!.photoUrl!) 
                                  : null,
                              child: widget.user?.photoUrl == null
                                  ? Icon(
                                      Icons.person,
                                      color: Colors.black87,
                                      size: 20,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.user?.displayName ?? 'Travel Enthusiast',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Hyper-Personalized Itinerary',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 1000.ms),
          
          // Description section
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Streaming description with skeleton loader
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  child: _tripDescription.isEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Description skeleton lines
                            Container(
                              width: double.infinity,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ).animate(onPlay: (controller) => controller.repeat())
                                .shimmer(duration: 1500.ms, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ).animate(onPlay: (controller) => controller.repeat())
                                .shimmer(duration: 1500.ms, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                            const SizedBox(height: 8),
                            Container(
                              width: MediaQuery.of(context).size.width * 0.8,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ).animate(onPlay: (controller) => controller.repeat())
                                .shimmer(duration: 1500.ms, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ).animate(onPlay: (controller) => controller.repeat())
                                .shimmer(duration: 1500.ms, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                            const SizedBox(height: 8),
                            Container(
                              width: MediaQuery.of(context).size.width * 0.6,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ).animate(onPlay: (controller) => controller.repeat())
                                .shimmer(duration: 1500.ms, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                          ],
                        )
                      : Text(
                          _tripDescription,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                            height: 1.6,
                            fontSize: (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) * 0.85 * fontScale,
                          ),
                        ),
                ),
                
                if (_isStreamingDescription)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AI is crafting your story...',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontStyle: FontStyle.italic,
                            fontSize: (Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ).animate().fadeIn(duration: 1200.ms).slideY(begin: 0.2),
          
          // Map section
          Container(
            margin: const EdgeInsets.all(24),
            height: 400,
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
                  Future.delayed(const Duration(seconds: 1), () {
                    _adjustCameraToBounds();
                  });
                },
                initialCameraPosition: CameraPosition(
                  target: _centerLocation,
                  zoom: 13,
                ),
                markers: _markers,
                zoomControlsEnabled: true,
                mapToolbarEnabled: true,
                myLocationButtonEnabled: false,
                compassEnabled: true,
              ),
            ),
          ).animate().fadeIn(duration: 1400.ms).scale(begin: const Offset(0.95, 0.95)),
          
          // Vertical Timeline section
          _buildTimeline().animate().fadeIn(duration: 1600.ms).slideY(begin: 0.1),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}