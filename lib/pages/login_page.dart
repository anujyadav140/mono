import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mono/services/user_service.dart';
import 'package:mono/services/auth_service.dart';
import 'package:mono/pages/itinerary_choice_page.dart';

const String? kClientId = null;       // e.g. 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com' (optional)
const String? kServerClientId = null; // e.g. 'YOUR_SERVER_CLIENT_ID.apps.googleusercontent.com' (optional)

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GoogleSignIn _google = GoogleSignIn.instance; // kept for possible future use

  bool _busy = false;
  String? _error;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    // No GoogleSignIn init required when using FirebaseAuth provider flow.
  }

  // Removed GoogleSignIn-based silent restore. AuthGate handles Firebase session.

  Future<void> _signIn() async {
    if (_busy) return;
    
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final cred = await AuthService().signInWithGoogle();
      if (cred?.user != null && UserService.isSupported) {
        await UserService.upsertFromFirebaseUser(cred!.user!);
      }
      // Navigate forward explicitly to avoid relying solely on stream rebuilds.
      if (!_didNavigate && mounted && cred?.user != null) {
        _didNavigate = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ItineraryChoicePage(user: null)),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Sign-in failed: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() { _busy = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final screenSize = MediaQuery.of(context).size;
    final fontScale = screenSize.width / 400; // Base width for scaling

    return Scaffold(
      backgroundColor: scheme.surface,
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
                const SizedBox(height: 60),
                // Header content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.travel_explore,
                          color: Colors.white,
                          size: 48,
                        ),
                      ).animate().scale(delay: 200.ms, duration: 300.ms),
                      const SizedBox(height: 24),
                      Text(
                        'Welcome to Mono Moments',
                        textAlign: TextAlign.center,
                        style: text.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.1,
                          fontSize: (text.headlineLarge?.fontSize ?? 32) * 0.7 * fontScale,
                        ),
                      ).animate().fadeIn(delay: 300.ms, duration: 300.ms).slideY(begin: 0.3),
                      const SizedBox(height: 16),
                      Text(
                        'Your AI-powered travel companion for creating perfect 4-day adventures',
                        textAlign: TextAlign.center,
                        style: text.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                          height: 1.4,
                          fontSize: (text.bodyLarge?.fontSize ?? 16) * 0.85 * fontScale,
                        ),
                      ).animate().fadeIn(delay: 400.ms, duration: 300.ms).slideY(begin: 0.3),
                      const SizedBox(height: 60),
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
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Container(
                            padding: const EdgeInsets.all(32),
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
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Get Started',
                                  style: text.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                    fontSize: (text.headlineMedium?.fontSize ?? 28) * 0.7 * fontScale,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Sign in to create your personalized travel experiences',
                                  textAlign: TextAlign.center,
                                  style: text.bodyMedium?.copyWith(
                                    color: scheme.onSurface.withValues(alpha: 0.7),
                                    fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.85 * fontScale,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _busy ? null : _signIn,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: scheme.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: _busy
                                        ? Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'Signing you in...',
                                                style: text.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                  fontSize: (text.titleMedium?.fontSize ?? 16) * 0.85 * fontScale,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Icon(
                                                  Icons.login,
                                                  color: scheme.primary,
                                                  size: 18,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'Continue with Google',
                                                style: text.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                  fontSize: (text.titleMedium?.fontSize ?? 16) * 0.85 * fontScale,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.red.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _error!,
                                            style: text.bodySmall?.copyWith(
                                              color: Colors.red.shade600,
                                              fontSize: (text.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ).animate().fadeIn(duration: 200.ms).shake(),
                                ],
                              ],
                            ),
                          ).animate().fadeIn(delay: 500.ms, duration: 300.ms).slideY(begin: 0.3),
                          const SizedBox(height: 40),
                          // Features preview
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: scheme.outline.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Column(
                              children: [
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
                                      child: Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'AI-Powered Planning',
                                            style: text.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface,
                                              fontSize: (text.titleSmall?.fontSize ?? 14) * 0.85 * fontScale,
                                            ),
                                          ),
                                          Text(
                                            'Personalized recommendations based on your preferences',
                                            style: text.bodySmall?.copyWith(
                                              color: scheme.onSurface.withValues(alpha: 0.7),
                                              fontSize: (text.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.green.shade400,
                                            Colors.teal.shade400,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.schedule, color: Colors.white, size: 16),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '4-Day Perfect Itineraries',
                                            style: text.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface,
                                              fontSize: (text.titleSmall?.fontSize ?? 14) * 0.85 * fontScale,
                                            ),
                                          ),
                                          Text(
                                            'Detailed day-by-day plans with local insights',
                                            style: text.bodySmall?.copyWith(
                                              color: scheme.onSurface.withValues(alpha: 0.7),
                                              fontSize: (text.bodySmall?.fontSize ?? 12) * 0.85 * fontScale,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: 600.ms, duration: 300.ms).slideY(begin: 0.3),
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
