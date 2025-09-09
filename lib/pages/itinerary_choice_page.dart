import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mono/pages/home_page.dart';
import 'package:mono/pages/group_itinerary_page.dart';
import 'package:mono/pages/login_page.dart';

class ItineraryChoicePage extends StatelessWidget {
  final GoogleSignInAccount? user;

  const ItineraryChoicePage({super.key, this.user});

  void _goToHome(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomePage(user: user)),
    );
  }

  void _logout(BuildContext context) async {
    try {
      await GoogleSignIn.instance.disconnect();
      await GoogleSignIn.instance.signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

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
                // Header with logout button
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Spacer(),
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
                            Icons.logout,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        onPressed: () => _logout(context),
                      ).animate().fadeIn(delay: 100.ms, duration: 200.ms).scale(begin: const Offset(0.8, 0.8)),
                    ],
                  ),
                ),
                // Header content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose Your\nPlanning Style',
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ).animate().fadeIn(delay: 150.ms, duration: 200.ms).slideY(begin: 0.3),
                      const SizedBox(height: 12),
                      Text(
                        'Select how you\'d like to create your perfect itinerary',
                        style: text.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                          height: 1.4,
                        ),
                      ).animate().fadeIn(delay: 200.ms, duration: 200.ms).slideY(begin: 0.3),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
                // Cards section
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
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          // Cards in a row
                          Row(
                            children: [
                              // Group Itinerary Card
                              Expanded(
                                child: _ChoiceCard(
                                  icon: Icons.group_rounded,
                                  title: 'Group',
                                  subtitle: 'Plan with friends',
                                  description: 'Collaborate in real-time and create memories together',
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.purple.shade400,
                                      Colors.pink.shade400,
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => GroupItineraryPage(user: user),
                                      ),
                                    );
                                  },
                                  delay: 300.ms,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Individual Itinerary Card
                              Expanded(
                                child: _ChoiceCard(
                                  icon: Icons.person_rounded,
                                  title: 'Individual',
                                  subtitle: 'Personal trip',
                                  description: 'AI-powered recommendations based on your preferences',
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue.shade400,
                                      Colors.cyan.shade400,
                                    ],
                                  ),
                                  onTap: () => _goToHome(context),
                                  delay: 350.ms,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                          // Bottom hint text
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: scheme.outline.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline,
                                  color: scheme.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'You can always switch between planning styles later in your settings.',
                                    style: text.bodySmall?.copyWith(
                                      color: scheme.onSurface.withValues(alpha: 0.7),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: 400.ms, duration: 200.ms).slideY(begin: 0.3),
                        ],
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

class _ChoiceCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final Gradient gradient;
  final VoidCallback onTap;
  final Duration delay;

  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.gradient,
    required this.onTap,
    required this.delay,
  });

  @override
  State<_ChoiceCard> createState() => _ChoiceCardState();
}

class _ChoiceCardState extends State<_ChoiceCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: _isPressed 
            ? (Matrix4.identity()..scale(0.98, 0.98))
            : (_isHovered 
              ? (Matrix4.identity()..scale(1.02, 1.02))
              : Matrix4.identity()),
          child: Container(
            padding: const EdgeInsets.all(20),
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
                color: _isHovered 
                    ? scheme.primary.withValues(alpha: 0.3)
                    : scheme.outline.withValues(alpha: 0.1),
                width: _isHovered ? 2 : 1,
              ),
              boxShadow: [
                if (_isHovered)
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                else
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
                Row(
                  children: [
                    // Gradient Icon Container
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: widget.gradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: widget.gradient.colors.first.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _isHovered ? 0.125 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_forward,
                          color: scheme.onSurfaceVariant,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.subtitle,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.description,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: widget.delay, duration: 300.ms)
     .slideY(begin: 0.3, duration: 250.ms)
     .scale(begin: const Offset(0.9, 0.9), duration: 200.ms);
  }
}
