import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../services/onboarding_controller.dart';
import '../../../../services/supabase/playlist_sync_service.dart';
import '../../../../services/supabase/supabase_service.dart';
import '../../../widgets/common_dialog_widget.dart';
import '../../../widgets/modified_text_field.dart';
import '../../../widgets/snackbar.dart';
import '../../Onboarding/onboarding_screen.dart';

enum SupabaseAuthMode { signIn, signUp, magicLink }

class SupabaseAuthDialog extends StatefulWidget {
  const SupabaseAuthDialog({super.key});

  @override
  State<SupabaseAuthDialog> createState() => _SupabaseAuthDialogState();
}

class _SupabaseAuthDialogState extends State<SupabaseAuthDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final SupabaseService _supabaseService = Get.find<SupabaseService>();

  SupabaseAuthMode _authMode = SupabaseAuthMode.signIn;
  bool _isPasswordVisible = false;
  String _validationError = '';
  bool _hasDismissed = false;
  bool _isGoogleLoading = false;
  bool _isEmailSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Auto-dismiss dialog if OAuth login completes while dialog is visible
    ever(_supabaseService.isLoggedIn, (bool loggedIn) {
      if (loggedIn && mounted) {
        _onSuccessfulAuth("Signed in successfully!");
      }
    });
  }

  void _onSuccessfulAuth(String message) async {
    if (_hasDismissed) return;
    _hasDismissed = true;

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, message, size: SanckBarSize.BIG),
      );
    }

    // Sync existing local playlists to cloud
    try {
      final syncService = Get.find<PlaylistSyncService>();
      syncService.syncAll();
    } catch (_) {}

    // Check if onboarding preferences are missing and resume
    try {
      final onboarding = Get.find<OnboardingController>();
      final needsOnboarding = await onboarding.resumeOnboardingAfterLateLogin();
      if (needsOnboarding) {
        Get.to(() => OnboardingScreen(
              onComplete: () {
                Get.back();
              },
            ));
      }
    } catch (_) {}
  }

  void _loginWithGoogle() async {
    setState(() {
      _validationError = '';
      _isGoogleLoading = true;
    });
    final success = await _supabaseService.signInWithGoogle();
    if (!mounted) return;
    if (success && _supabaseService.isLoggedIn.value) {
      _onSuccessfulAuth("Signed in with Google successfully!");
    } else if (!success) {
      setState(() {
        _isGoogleLoading = false;
        _validationError = _supabaseService.authErrorMessage.value;
      });
    } else {
      // Browser opened for OAuth; wait for redirect callback.
      // Reset local loading flag after 30s so user can retry if they closed browser.
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && !_hasDismissed) {
          setState(() {
            _isGoogleLoading = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _supabaseService.cancelAuthentication();
    super.dispose();
  }

  void _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _validationError = '';
    });

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _validationError = 'Please enter a valid email address.';
      });
      return;
    }

    if (_authMode != SupabaseAuthMode.magicLink) {
      if (password.length < 6) {
        setState(() {
          _validationError = 'Password must be at least 6 characters.';
        });
        return;
      }
    }

    setState(() {
      _isEmailSubmitting = true;
    });

    bool success = false;
    try {
      if (_authMode == SupabaseAuthMode.signIn) {
        success = await _supabaseService.signInWithPassword(
          email: email,
          password: password,
        );
      } else if (_authMode == SupabaseAuthMode.signUp) {
        success = await _supabaseService.signUpWithPassword(
          email: email,
          password: password,
        );
      } else if (_authMode == SupabaseAuthMode.magicLink) {
        success = await _supabaseService.sendMagicLink(email: email);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEmailSubmitting = false;
        });
      }
    }

    if (!mounted) return;

    if (success) {
      if (_authMode == SupabaseAuthMode.magicLink) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(context, 'Magic link sent! Please check your email.',
              size: SanckBarSize.BIG),
        );
      } else {
        final msg = _authMode == SupabaseAuthMode.signUp
            ? 'Account created successfully!'
            : 'Signed in successfully!';
        _onSuccessfulAuth(msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleSmall!.color;
    final primaryColor = Theme.of(context).colorScheme.secondary;

    return CommonDialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Row(
                children: [
                  Icon(Icons.cloud_sync, color: primaryColor, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    "Cloud Playlist Backup",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Sign in to back up and sync your playlists across devices.",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),

              // Continue with Google Button
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColorLight,
                  side: BorderSide(
                    color: Theme.of(context)
                        .dividerColor
                        .withValues(alpha: 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: (_isGoogleLoading || _isEmailSubmitting)
                    ? null
                    : _loginWithGoogle,
                child: _isGoogleLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              "G",
                              style: TextStyle(
                                color: Color(0xFF4285F4),
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "Continue with Google",
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 14),

              // OR divider
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      "or continue with email",
                      style: TextStyle(
                        color: textColor?.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Mode Selector Tabs
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTab(SupabaseAuthMode.signIn, "Sign In"),
                  const SizedBox(width: 8),
                  _buildTab(SupabaseAuthMode.signUp, "Sign Up"),
                  const SizedBox(width: 8),
                  _buildTab(SupabaseAuthMode.magicLink, "Magic Link"),
                ],
              ),
              const SizedBox(height: 16),

              // Email Input
              ModifiedTextField(
                controller: _emailController,
                cursorColor: textColor,
                textInputAction: _authMode == SupabaseAuthMode.magicLink
                    ? TextInputAction.done
                    : TextInputAction.next,
                onSubmitted: (_) {
                  if (_authMode == SupabaseAuthMode.magicLink) {
                    _submit();
                  }
                },
                decoration: InputDecoration(
                  hintText: "Email address",
                  prefixIcon: Icon(Icons.email_outlined, color: textColor),
                  filled: true,
                  fillColor: Theme.of(context).primaryColorLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),

              // Password Input (if not magic link)
              if (_authMode != SupabaseAuthMode.magicLink) ...[
                const SizedBox(height: 12),
                ModifiedTextField(
                  controller: _passwordController,
                  cursorColor: textColor,
                  obscureText: !_isPasswordVisible,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: "Password",
                    prefixIcon: Icon(Icons.lock_outline, color: textColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: textColor,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: Theme.of(context).primaryColorLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ],

              // Error messages
              Obx(() {
                final apiError = _supabaseService.authErrorMessage.value;
                final errorToShow = _validationError.isNotEmpty
                    ? _validationError
                    : apiError;
                if (errorToShow.isEmpty) return const SizedBox(height: 12);
                return Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Text(
                    errorToShow,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                );
              }),

              const SizedBox(height: 8),

              // Submit Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: (_isGoogleLoading || _isEmailSubmitting)
                    ? null
                    : _submit,
                child: _isEmailSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _authMode == SupabaseAuthMode.signIn
                            ? "Sign In"
                            : _authMode == SupabaseAuthMode.signUp
                                ? "Create Account"
                                : "Send Magic Link",
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
              ),

              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () {
                    _supabaseService.cancelAuthentication();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: textColor, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(SupabaseAuthMode mode, String label) {
    final isSelected = _authMode == mode;
    final primaryColor = Theme.of(context).colorScheme.secondary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        setState(() {
          _authMode = mode;
          _validationError = '';
          _supabaseService.authErrorMessage.value = '';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? primaryColor
                : Theme.of(context).textTheme.titleSmall!.color,
          ),
        ),
      ),
    );
  }
}
