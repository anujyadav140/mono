import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mono/pages/home_page.dart';

const String? kClientId = null;       // e.g. 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com' (optional)
const String? kServerClientId = null; // e.g. 'YOUR_SERVER_CLIENT_ID.apps.googleusercontent.com' (optional)


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GoogleSignIn _google = GoogleSignIn.instance;

  bool _busy = false;
  String? _error;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _initGoogle();
  }

  Future<void> _initGoogle() async {
    await _google.initialize(clientId: kClientId, serverClientId: kServerClientId);

    _google.authenticationEvents.listen((event) {
      if (!mounted) return;
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          setState(() {
            _error = null;
          });
          _signInToFirebase(event.user);
          break;
        case GoogleSignInAuthenticationEventSignOut():
          // User signed out
          break;
      }
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _error = e is GoogleSignInException
            ? (e.code == GoogleSignInExceptionCode.canceled
                ? 'Sign-in canceled'
                : 'GoogleSignInException ${e.code}: ${e.description}')
            : 'Error: $e';
      });
    });

    // Restore session if possible.
    _google.attemptLightweightAuthentication();
  }

  void _signInToFirebase(GoogleSignInAccount googleUser) {
    // Just navigate - only use Google Sign In, no Firebase Auth integration
    _navigateToHomeOnce(googleUser);
  }

  void _navigateToHomeOnce(GoogleSignInAccount user) {
    if (_didNavigate || !mounted) return;
    _didNavigate = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomePage(user: user)),
    );
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_google.supportsAuthenticate()) {
        await _google.authenticate(); // Triggers native/web Google Sign-In
        // On success, the auth event listener will navigate.
      } else {
        throw Exception('Unsupported platform for Google Sign-In');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Icon(Icons.travel_explore_rounded, size: 32, color: scheme.primary),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Welcome to Mono Moments',
                      style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Plan your perfect trip with AI-powered recommendations',
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 14)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _busy ? scheme.onSurface.withValues(alpha: 0.12) : scheme.primary,
                        ),
                        child: _busy
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                  SizedBox(width: 12),
                                  Text('Signing in...'),
                                ],
                              )
                            : const Text('Continue with Google'),
                      ),
                    ),

                    const SizedBox(height: 18),
                    Text(
                      'By continuing, you agree to our Terms of Service and Privacy Policy',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
