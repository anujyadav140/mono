import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';

import 'auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mono Moments',
      theme: _buildTheme(),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }

  ThemeData _buildTheme() {
    const primaryColor = Color(0xFF1E40AF); // Blue-700
    const surfaceColor = Color(0xFFFAFAFA); // Neutral-50
    const cardColor = Color(0xFFFFFFFF); // White
    
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
        surface: surfaceColor,
        onSurface: const Color(0xFF0F172A), // Slate-900
        surfaceContainerHighest: const Color(0xFFF1F5F9), // Slate-100
        onSurfaceVariant: const Color(0xFF64748B), // Slate-500
      ),
      textTheme: GoogleFonts.interTextTheme(),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1), // Slate-200
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)), // Slate-200
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)), // Slate-200
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: GoogleFonts.inter(
          color: const Color(0xFF64748B), // Slate-500
          fontSize: 14,
        ),
        hintStyle: GoogleFonts.inter(
          color: const Color(0xFF94A3B8), // Slate-400
          fontSize: 14,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: cardColor,
        foregroundColor: const Color(0xFF0F172A), // Slate-900
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: const Color(0xFF0F172A), // Slate-900
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
