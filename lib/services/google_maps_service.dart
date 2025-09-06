import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'location_service.dart';

class GoogleMapsService {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api';
  static const String _placesApiUrl = 'https://places.googleapis.com/v1';
  static const String _apiKey = 'AIzaSyCLgimggRuRcKCEUE0mmYm00AC18bg8O58';
  
  static GoogleMapsService? _instance;
  GoogleMapsService._internal();
  
  static GoogleMapsService get instance {
    _instance ??= GoogleMapsService._internal();
    return _instance!;
  }

  final LocationService _locationService = LocationService.instance;
  final Random _random = Random();

  /// Fetch places near user's current Milan location
  Future<List<Place>> fetchNearbyPlaces(double lat, double lng, {String? type}) async {
    final url = Uri.parse('$_baseUrl/place/nearbysearch/json');
    
    final response = await http.get(url.replace(queryParameters: {
      'location': '$lat,$lng',
      'radius': '1500', // 1.5km radius
      'type': type ?? 'point_of_interest',
      'key': _apiKey,
    }));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['results'] as List)
          .map((json) => Place.fromJson(json))
          .toList();
    } else {
      // Fallback to Milan-based mock data if API fails
      return _getMilanPlacesMock(lat, lng, type);
    }
  }

  /// Get place details including reviews
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    final url = Uri.parse('$_baseUrl/place/details/json');
    
    final response = await http.get(url.replace(queryParameters: {
      'place_id': placeId,
      'fields': 'name,rating,reviews,photos,formatted_address,geometry,types',
      'key': _apiKey,
    }));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return PlaceDetails.fromJson(data['result']);
    } else {
      // Fallback to mock data
      return _getMockPlaceDetails(placeId);
    }
  }

  /// Generate Milan-based dashboard data
  Future<MilanDashboardData> getMilanDashboard(String userEmail) async {
    // Simulate user location in Milan
    final userLocation = _locationService.simulateUserInMilan();
    
    try {
      // Fetch real places near user location
      final [restaurants, attractions, shopping] = await Future.wait([
        fetchNearbyPlaces(userLocation.latitude, userLocation.longitude, type: 'restaurant'),
        fetchNearbyPlaces(userLocation.latitude, userLocation.longitude, type: 'tourist_attraction'),
        fetchNearbyPlaces(userLocation.latitude, userLocation.longitude, type: 'shopping_mall'),
      ]);

      // Generate realistic user activity based on Milan context
      final userStats = _generateMilanUserStats(userLocation);
      final recentActivities = await _generateMilanActivities(userLocation);
      
      return MilanDashboardData(
        userLocation: userLocation,
        userStats: userStats,
        nearbyRestaurants: restaurants.take(5).toList(),
        nearbyAttractions: attractions.take(5).toList(),
        nearbyShopping: shopping.take(5).toList(),
        recentActivities: recentActivities,
        recommendations: _generateMilanRecommendations(userLocation),
      );
    } catch (e) {
      // Fallback to rich mock data on API failure
      return _generateFullMilanMockDashboard(userLocation, userEmail);
    }
  }

  /// Generate realistic Milan-based user stats
  UserMapsStats _generateMilanUserStats(UserLocation userLocation) {
    // Base stats on Milan location and context
    final milanMultiplier = 1.2; // Milan users tend to be more active
    
    return UserMapsStats(
      totalReviews: 28 + _random.nextInt(50),
      totalPhotos: (85 + _random.nextInt(200) * milanMultiplier).round(),
      viewsThisMonth: (1200 + _random.nextInt(3000) * milanMultiplier).round(),
      totalViews: (8500 + _random.nextInt(15000) * milanMultiplier).round(),
      contributorLevel: _getRandomContributorLevel(),
      pointsEarned: 850 + _random.nextInt(2000),
      lastReviewDate: DateTime.now().subtract(Duration(days: _random.nextInt(14))),
      averageRating: 3.8 + (_random.nextDouble() * 1.2),
      currentCity: 'Milan',
      currentLocation: userLocation.nearbyLocation.name,
    );
  }

  String _getRandomContributorLevel() {
    final levels = [
      'Local Guide Level 4',
      'Local Guide Level 5',
      'Local Guide Level 6',
      'Local Guide Level 7',
      'Milan Expert Contributor',
      'Trusted Milan Reviewer',
    ];
    return levels[_random.nextInt(levels.length)];
  }

  /// Generate Milan-specific activities
  Future<List<UserActivity>> _generateMilanActivities(UserLocation userLocation) async {
    final activities = <UserActivity>[];
    
    // Recent reviews in Milan
    final milanPlaces = [
      'Caffè Cova', 'Osteria del Borgo', 'Trattoria Milanese', 'Bar Centrale',
      'Ristorante Cracco', 'Navigli Social Club', 'Brera Design District',
      'Quadrilatero della Moda', 'Mercato di Brera', 'Terrazza Aperol'
    ];
    
    for (int i = 0; i < 5; i++) {
      activities.add(UserActivity(
        type: ActivityType.review,
        placeName: milanPlaces[_random.nextInt(milanPlaces.length)],
        rating: 3 + _random.nextInt(3), // 3-5 stars
        text: _generateMilanReviewText(),
        timestamp: DateTime.now().subtract(Duration(days: i * 2 + _random.nextInt(3))),
        location: _locationService.getRandomActivityLocation(),
      ));
    }
    
    // Recent photos
    for (int i = 0; i < 3; i++) {
      activities.add(UserActivity(
        type: ActivityType.photo,
        placeName: milanPlaces[_random.nextInt(milanPlaces.length)],
        text: _generatePhotoDescription(),
        timestamp: DateTime.now().subtract(Duration(hours: _random.nextInt(72))),
        location: _locationService.getRandomActivityLocation(),
      ));
    }
    
    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return activities;
  }

  String _generateMilanReviewText() {
    final reviews = [
      'Autentico ambiente milanese con ottima cucina lombarda. Highly recommended!',
      'Perfect spot in the heart of Milan. Great for aperitivo with friends.',
      'Traditional Milanese cuisine at its finest. The risotto is exceptional.',
      'Trendy location near Navigli. Good food and vibrant atmosphere.',
      'Classic Milan style with modern touches. Excellent service.',
      'Hidden gem in Brera district. Intimate setting with amazing food.',
    ];
    return reviews[_random.nextInt(reviews.length)];
  }

  String _generatePhotoDescription() {
    final descriptions = [
      'Beautiful architecture in Milan\'s historic center',
      'Aperitivo time in the Navigli district',
      'Street art in Isola neighborhood',
      'Milan skyline from Porta Nuova',
      'Traditional Milanese interior design',
      'Perfect pasta dish at local trattoria',
    ];
    return descriptions[_random.nextInt(descriptions.length)];
  }

  List<Recommendation> _generateMilanRecommendations(UserLocation userLocation) {
    return [
      Recommendation(
        title: 'Try authentic risotto alla milanese',
        subtitle: 'Based on your location near ${userLocation.nearbyLocation.name}',
        type: 'food',
        priority: 'high',
      ),
      Recommendation(
        title: 'Explore Brera Art District',
        subtitle: 'Perfect for photography enthusiasts',
        type: 'culture',
        priority: 'medium',
      ),
      Recommendation(
        title: 'Evening aperitivo at Navigli',
        subtitle: 'Traditional Milanese social hour',
        type: 'social',
        priority: 'high',
      ),
      Recommendation(
        title: 'Visit Quadrilatero della Moda',
        subtitle: 'World-class fashion shopping',
        type: 'shopping',
        priority: 'medium',
      ),
    ];
  }

  /// Milan places mock data for offline functionality
  List<Place> _getMilanPlacesMock(double lat, double lng, String? type) {
    // Return relevant Milan places based on type
    switch (type) {
      case 'restaurant':
        return _getMilanRestaurants();
      case 'tourist_attraction':
        return _getMilanAttractions();
      case 'shopping_mall':
        return _getMilanShopping();
      default:
        return _getMilanMixedPlaces();
    }
  }

  List<Place> _getMilanRestaurants() {
    return [
      Place(id: 'r1', name: 'Trattoria Milanese', rating: 4.3, vicinity: 'Via Santa Marta, 11', 
            types: ['restaurant'], lat: 45.4641, lng: 9.1896),
      Place(id: 'r2', name: 'Osteria del Borgo', rating: 4.5, vicinity: 'Via Borgo Spesso, 12', 
            types: ['restaurant'], lat: 45.4719, lng: 9.1881),
      Place(id: 'r3', name: 'Ristorante Cracco', rating: 4.7, vicinity: 'Via Victor Hugo, 4', 
            types: ['restaurant'], lat: 45.4656, lng: 9.1897),
      Place(id: 'r4', name: 'Caffè Cova', rating: 4.2, vicinity: 'Via Montenapoleone, 8', 
            types: ['restaurant', 'cafe'], lat: 45.4681, lng: 9.1953),
      Place(id: 'r5', name: 'Terrazza Aperol', rating: 4.4, vicinity: 'Piazza del Duomo, 21', 
            types: ['bar', 'restaurant'], lat: 45.4641, lng: 9.1896),
    ];
  }

  List<Place> _getMilanAttractions() {
    return [
      Place(id: 'a1', name: 'Duomo di Milano', rating: 4.6, vicinity: 'Piazza del Duomo', 
            types: ['tourist_attraction'], lat: 45.4641, lng: 9.1896),
      Place(id: 'a2', name: 'Teatro alla Scala', rating: 4.5, vicinity: 'Via Filodrammatici, 2', 
            types: ['tourist_attraction'], lat: 45.4677, lng: 9.1898),
      Place(id: 'a3', name: 'Castello Sforzesco', rating: 4.3, vicinity: 'Piazza Castello', 
            types: ['tourist_attraction'], lat: 45.4704, lng: 9.1794),
      Place(id: 'a4', name: 'Navigli District', rating: 4.4, vicinity: 'Navigli', 
            types: ['tourist_attraction'], lat: 45.4484, lng: 9.1696),
      Place(id: 'a5', name: 'Brera District', rating: 4.5, vicinity: 'Brera', 
            types: ['tourist_attraction'], lat: 45.4719, lng: 9.1881),
    ];
  }

  List<Place> _getMilanShopping() {
    return [
      Place(id: 's1', name: 'Galleria Vittorio Emanuele II', rating: 4.5, vicinity: 'Piazza del Duomo', 
            types: ['shopping_mall'], lat: 45.4656, lng: 9.1897),
      Place(id: 's2', name: 'Quadrilatero della Moda', rating: 4.6, vicinity: 'Via Montenapoleone', 
            types: ['shopping_mall'], lat: 45.4681, lng: 9.1953),
      Place(id: 's3', name: 'Corso Buenos Aires', rating: 4.2, vicinity: 'Corso Buenos Aires', 
            types: ['shopping_mall'], lat: 45.4781, lng: 9.2094),
      Place(id: 's4', name: 'Via Torino Shopping', rating: 4.0, vicinity: 'Via Torino', 
            types: ['shopping_mall'], lat: 45.4587, lng: 9.1856),
    ];
  }

  List<Place> _getMilanMixedPlaces() {
    return [..._getMilanRestaurants(), ..._getMilanAttractions(), ..._getMilanShopping()];
  }

  PlaceDetails _getMockPlaceDetails(String placeId) {
    return PlaceDetails(
      placeId: placeId,
      name: 'Milan Location',
      rating: 4.2 + (_random.nextDouble() * 0.8),
      formattedAddress: 'Via Example, Milan, Italy',
      reviews: [],
    );
  }

  MilanDashboardData _generateFullMilanMockDashboard(UserLocation userLocation, String userEmail) {
    return MilanDashboardData(
      userLocation: userLocation,
      userStats: _generateMilanUserStats(userLocation),
      nearbyRestaurants: _getMilanRestaurants(),
      nearbyAttractions: _getMilanAttractions(),
      nearbyShopping: _getMilanShopping(),
      recentActivities: [],
      recommendations: _generateMilanRecommendations(userLocation),
    );
  }
}

class UserMapsStats {
  final int totalReviews;
  final int totalPhotos;
  final int viewsThisMonth;
  final int totalViews;
  final String contributorLevel;
  final int pointsEarned;
  final DateTime lastReviewDate;
  final double averageRating;
  final String currentCity;
  final String currentLocation;

  UserMapsStats({
    required this.totalReviews,
    required this.totalPhotos,
    required this.viewsThisMonth,
    required this.totalViews,
    required this.contributorLevel,
    required this.pointsEarned,
    required this.lastReviewDate,
    required this.averageRating,
    required this.currentCity,
    required this.currentLocation,
  });
}

class UserReview {
  final String placeName;
  final int rating;
  final String reviewText;
  final DateTime date;
  final int likes;

  UserReview({
    required this.placeName,
    required this.rating,
    required this.reviewText,
    required this.date,
    required this.likes,
  });
  
  String get timeAgo {
    final difference = DateTime.now().difference(date);
    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inMinutes} minutes ago';
    }
  }
}

class MilanDashboardData {
  final UserLocation userLocation;
  final UserMapsStats userStats;
  final List<Place> nearbyRestaurants;
  final List<Place> nearbyAttractions;
  final List<Place> nearbyShopping;
  final List<UserActivity> recentActivities;
  final List<Recommendation> recommendations;

  MilanDashboardData({
    required this.userLocation,
    required this.userStats,
    required this.nearbyRestaurants,
    required this.nearbyAttractions,
    required this.nearbyShopping,
    required this.recentActivities,
    required this.recommendations,
  });
}

class Place {
  final String id;
  final String name;
  final double rating;
  final String vicinity;
  final List<String> types;
  final double lat;
  final double lng;

  Place({
    required this.id,
    required this.name,
    required this.rating,
    required this.vicinity,
    required this.types,
    required this.lat,
    required this.lng,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['place_id'] ?? '',
      name: json['name'] ?? '',
      rating: (json['rating'] ?? 0.0).toDouble(),
      vicinity: json['vicinity'] ?? '',
      types: List<String>.from(json['types'] ?? []),
      lat: json['geometry']['location']['lat'].toDouble(),
      lng: json['geometry']['location']['lng'].toDouble(),
    );
  }

  String get coordinates => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
}

class PlaceDetails {
  final String placeId;
  final String name;
  final double rating;
  final String formattedAddress;
  final List<Review> reviews;

  PlaceDetails({
    required this.placeId,
    required this.name,
    required this.rating,
    required this.formattedAddress,
    required this.reviews,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    return PlaceDetails(
      placeId: json['place_id'] ?? '',
      name: json['name'] ?? '',
      rating: (json['rating'] ?? 0.0).toDouble(),
      formattedAddress: json['formatted_address'] ?? '',
      reviews: (json['reviews'] as List? ?? [])
          .map((reviewJson) => Review.fromJson(reviewJson))
          .toList(),
    );
  }
}

class Review {
  final String authorName;
  final int rating;
  final String text;
  final DateTime time;

  Review({
    required this.authorName,
    required this.rating,
    required this.text,
    required this.time,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      authorName: json['author_name'] ?? '',
      rating: json['rating'] ?? 0,
      text: json['text'] ?? '',
      time: DateTime.fromMillisecondsSinceEpoch((json['time'] ?? 0) * 1000),
    );
  }
}

enum ActivityType { review, photo, checkin, edit }

class UserActivity {
  final ActivityType type;
  final String placeName;
  final int? rating;
  final String text;
  final DateTime timestamp;
  final MilanLocation location;

  UserActivity({
    required this.type,
    required this.placeName,
    this.rating,
    required this.text,
    required this.timestamp,
    required this.location,
  });

  String get timeAgo {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inMinutes} minutes ago';
    }
  }

  IconData get icon {
    switch (type) {
      case ActivityType.review:
        return Icons.rate_review;
      case ActivityType.photo:
        return Icons.photo_camera;
      case ActivityType.checkin:
        return Icons.location_on;
      case ActivityType.edit:
        return Icons.edit_location;
    }
  }

  String get typeDisplayName {
    switch (type) {
      case ActivityType.review:
        return 'Review';
      case ActivityType.photo:
        return 'Photo';
      case ActivityType.checkin:
        return 'Check-in';
      case ActivityType.edit:
        return 'Edit';
    }
  }
}

class Recommendation {
  final String title;
  final String subtitle;
  final String type;
  final String priority;

  Recommendation({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.priority,
  });

  IconData get icon {
    switch (type) {
      case 'food':
        return Icons.restaurant;
      case 'culture':
        return Icons.museum;
      case 'social':
        return Icons.local_bar;
      case 'shopping':
        return Icons.shopping_bag;
      default:
        return Icons.place;
    }
  }

  Color get priorityColor {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}