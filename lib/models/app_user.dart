class AppUser {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  factory AppUser.fromMap(String id, Map<String, dynamic> data) {
    return AppUser(
      id: id,
      email: (data['email'] ?? '') as String,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
    };
  }
}

