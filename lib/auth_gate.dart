import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'pages/itinerary_choice_page.dart';
import 'pages/login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          // App pages read FirebaseAuth directly; pass null for Google account.
          return const ItineraryChoicePage(user: null);
        }
        return const LoginPage();
      },
    );
  }
}
