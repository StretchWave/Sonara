import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/onboarding_controller.dart';
import '../../../services/supabase/supabase_service.dart';
import '../Settings/components/supabase_auth_dialog.dart';

/// First onboarding step: Welcome screen with Sign-In or Continue as Guest.
///
/// Designed to match Sonara's aesthetic with glowing branding, feature highlights,
/// Google OAuth, and guest progression.
class WelcomeStep extends StatefulWidget {
  const WelcomeStep({super.key});

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep> {
  final OnboardingController _onboarding = Get.find<OnboardingController>();
  final SupabaseService _supabase = Get.find<SupabaseService>();
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Listen for OAuth completing in the background
    ever(_supabase.isLoggedIn, (bool loggedIn) {
      if (loggedIn && mounted) {
        _onLoginSuccess();
      }
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final success = await _supabase.signInWithGoogle();
    if (!mounted) return;

    if (success && _supabase.isLoggedIn.value) {
      _onLoginSuccess();
    } else if (!success) {
      setState(() {
        _isLoading = false;
        _errorMessage = _supabase.authErrorMessage.value;
      });
    } else {
      // Browser opened for Google OAuth; waiting for redirect deep-link callback
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _onLoginSuccess() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _onboarding.completeLogin();
    if (mounted) setState(() => _isLoading = false);
  }

  void _showEmailAuthDialog() {
    showDialog(
      context: context,
      builder: (context) => const SupabaseAuthDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.secondary;
    final textColor = theme.textTheme.bodyMedium?.color;
    final size = MediaQuery.of(context).size;
    final horizontalPad = size.width > 600 ? size.width * 0.22 : 24.0;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glowing Sonara Icon
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryColor.withValues(alpha: 0.35),
                    primaryColor.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.2),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipOval(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Image.asset(
                    'assets/icons/icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              "Welcome to Sonara",
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // Subtitle
            Text(
              "Stream your favorite music, synchronize playlists, and enjoy personalized recommendations without limits.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor?.withValues(alpha: 0.7),
                fontSize: 14.5,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // Feature Badges matching Sonara design
            _buildFeatureBadges(context, primaryColor, textColor),
            const SizedBox(height: 32),

            // Error Message (if any)
            if (_errorMessage.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Continue with Google Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColorLight,
                  foregroundColor: textColor,
                  elevation: 0,
                  side: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.25),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: _isLoading ? null : _signInWithGoogle,
                child: _isLoading
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryColor,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'G',
                              style: TextStyle(
                                color: Color(0xFF4285F4),
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Text(
                            "Continue with Google",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),

            // Sign In with Email option
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: textColor,
                  side: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.18),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isLoading ? null : _showEmailAuthDialog,
                icon: Icon(Icons.email_outlined, size: 18, color: textColor?.withValues(alpha: 0.8)),
                label: const Text(
                  "Sign In with Email",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Continue as Guest (moves to language selection)
            TextButton(
              onPressed: _isLoading ? null : () => _onboarding.skipLogin(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Continue as Guest",
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: primaryColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureBadges(
    BuildContext context,
    Color primaryColor,
    Color? textColor,
  ) {
    final theme = Theme.of(context);

    final features = [
      {'icon': Icons.graphic_eq_rounded, 'title': 'High Fidelity', 'desc': 'Unthrottled audio'},
      {'icon': Icons.cloud_sync_rounded, 'title': 'Cloud Sync', 'desc': 'Playlists & backup'},
      {'icon': Icons.tune_rounded, 'title': 'Tailored Feed', 'desc': 'Personalized discover'},
    ];

    return Row(
      children: features.map((f) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: theme.primaryColorLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              children: [
                Icon(f['icon'] as IconData, size: 22, color: primaryColor),
                const SizedBox(height: 6),
                Text(
                  f['title'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  f['desc'] as String,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: textColor?.withValues(alpha: 0.55),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
