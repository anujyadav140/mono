import 'dart:math';

class LocationService {
  static LocationService? _instance;
  LocationService._internal();
  
  static LocationService get instance {
    _instance ??= LocationService._internal();
    return _instance!;
  }

  // Milan city bounds
  static const double _milanCenterLat = 45.4642;
  static const double _milanCenterLng = 9.1900;
  static const double _milanRadius = 0.15; // ~15km radius

  // Notable Milan locations for randomized selection
  final List<MilanLocation> _milanLocations = [
    MilanLocation(
      name: 'Duomo di Milano',
      lat: 45.4641943,
      lng: 9.1896346,
      category: 'Cathedral',
      description: 'Iconic Gothic cathedral in the heart of Milan',
    ),
    MilanLocation(
      name: 'Galleria Vittorio Emanuele II',
      lat: 45.4656,
      lng: 9.1897,
      category: 'Shopping',
      description: 'Historic shopping gallery with luxury boutiques',
    ),
    MilanLocation(
      name: 'Teatro alla Scala',
      lat: 45.4677,
      lng: 9.1898,
      category: 'Theatre',
      description: 'World-famous opera house',
    ),
    MilanLocation(
      name: 'Sforza Castle',
      lat: 45.4704,
      lng: 9.1794,
      category: 'Castle',
      description: 'Medieval fortress housing several museums',
    ),
    MilanLocation(
      name: 'Brera District',
      lat: 45.4719,
      lng: 9.1881,
      category: 'Neighborhood',
      description: 'Artistic quarter with galleries and cafes',
    ),
    MilanLocation(
      name: 'Navigli District',
      lat: 45.4484,
      lng: 9.1696,
      category: 'Nightlife',
      description: 'Canal district famous for nightlife and dining',
    ),
    MilanLocation(
      name: 'Quadrilatero della Moda',
      lat: 45.4681,
      lng: 9.1953,
      category: 'Shopping',
      description: 'Fashion quadrilateral with luxury stores',
    ),
    MilanLocation(
      name: 'Parco Sempione',
      lat: 45.4728,
      lng: 9.1712,
      category: 'Park',
      description: 'Large park behind Sforza Castle',
    ),
    MilanLocation(
      name: 'Porta Nuova',
      lat: 45.4853,
      lng: 9.1877,
      category: 'Business',
      description: 'Modern business district with skyscrapers',
    ),
    MilanLocation(
      name: 'Isola District',
      lat: 45.4875,
      lng: 9.1889,
      category: 'Trendy Area',
      description: 'Hip neighborhood with contemporary architecture',
    ),
    MilanLocation(
      name: 'Corso Buenos Aires',
      lat: 45.4781,
      lng: 9.2094,
      category: 'Shopping',
      description: 'One of Europe\'s longest shopping streets',
    ),
    MilanLocation(
      name: 'Santa Maria delle Grazie',
      lat: 45.4658,
      lng: 9.1701,
      category: 'Church',
      description: 'Church housing Leonardo da Vinci\'s Last Supper',
    ),
    MilanLocation(
      name: 'Cimitero Monumentale',
      lat: 45.4865,
      lng: 9.1816,
      category: 'Cemetery',
      description: 'Monumental cemetery with artistic tombs',
    ),
    MilanLocation(
      name: 'Porta Ticinese',
      lat: 45.4503,
      lng: 9.1789,
      category: 'Historic',
      description: 'Historic gate and vibrant neighborhood',
    ),
    MilanLocation(
      name: 'Via Torino',
      lat: 45.4587,
      lng: 9.1856,
      category: 'Shopping',
      description: 'Popular shopping street near the center',
    ),
  ];

  final Random _random = Random();
  MilanLocation? _currentLocation;
  List<MilanLocation> _nearbyLocations = [];

  /// Simulates user being in Milan with randomized location
  UserLocation simulateUserInMilan() {
    // Select a random Milan location as base
    final baseLocation = _milanLocations[_random.nextInt(_milanLocations.length)];
    _currentLocation = baseLocation;
    
    // Add slight randomization to coordinates (simulate GPS variance)
    final latVariance = (_random.nextDouble() - 0.5) * 0.002; // ~200m variance
    final lngVariance = (_random.nextDouble() - 0.5) * 0.002;
    
    final userLat = baseLocation.lat + latVariance;
    final userLng = baseLocation.lng + lngVariance;
    
    // Generate nearby locations
    _generateNearbyLocations(userLat, userLng);
    
    return UserLocation(
      latitude: userLat,
      longitude: userLng,
      city: 'Milan',
      country: 'Italy',
      address: _generateRandomAddress(),
      nearbyLocation: baseLocation,
      accuracy: 5.0 + _random.nextDouble() * 10.0, // 5-15m accuracy
      timestamp: DateTime.now(),
    );
  }

  /// Generate random realistic Milan address
  String _generateRandomAddress() {
    final streets = [
      'Via Montenapoleone',
      'Corso di Porta Ticinese',
      'Via Brera',
      'Corso Buenos Aires',
      'Via della Spiga',
      'Via Manzoni',
      'Corso Venezia',
      'Via Torino',
      'Via Dante',
      'Corso Magenta',
    ];
    
    final street = streets[_random.nextInt(streets.length)];
    final number = 1 + _random.nextInt(200);
    
    return '$street, $number, Milan, Italy';
  }

  /// Generate nearby locations based on current position
  void _generateNearbyLocations(double userLat, double userLng) {
    _nearbyLocations.clear();
    
    // Calculate distances and select nearby locations
    for (final location in _milanLocations) {
      final distance = _calculateDistance(userLat, userLng, location.lat, location.lng);
      if (distance <= 2.0) { // Within 2km
        _nearbyLocations.add(location);
      }
    }
    
    // Sort by distance
    _nearbyLocations.sort((a, b) {
      final distA = _calculateDistance(userLat, userLng, a.lat, a.lng);
      final distB = _calculateDistance(userLat, userLng, b.lat, b.lng);
      return distA.compareTo(distB);
    });
    
    // Keep only top 8 nearest
    if (_nearbyLocations.length > 8) {
      _nearbyLocations = _nearbyLocations.sublist(0, 8);
    }
  }

  /// Calculate distance between two coordinates in kilometers
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // Earth's radius in km
    
    final double dLat = _toRadians(lat2 - lat1);
    final double dLng = _toRadians(lng2 - lng1);
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * 
        sin(dLng / 2) * sin(dLng / 2);
    
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  /// Get current Milan location
  MilanLocation? get currentLocation => _currentLocation;
  
  /// Get nearby locations
  List<MilanLocation> get nearbyLocations => List.unmodifiable(_nearbyLocations);
  
  /// Generate random activity location within Milan
  MilanLocation getRandomActivityLocation() {
    return _milanLocations[_random.nextInt(_milanLocations.length)];
  }
}

class UserLocation {
  final double latitude;
  final double longitude;
  final String city;
  final String country;
  final String address;
  final MilanLocation nearbyLocation;
  final double accuracy;
  final DateTime timestamp;

  UserLocation({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.country,
    required this.address,
    required this.nearbyLocation,
    required this.accuracy,
    required this.timestamp,
  });

  String get coordinates => '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

class MilanLocation {
  final String name;
  final double lat;
  final double lng;
  final String category;
  final String description;

  MilanLocation({
    required this.name,
    required this.lat,
    required this.lng,
    required this.category,
    required this.description,
  });
  
  String get coordinates => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
}