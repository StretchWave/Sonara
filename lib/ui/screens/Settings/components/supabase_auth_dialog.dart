import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../services/supabase/supabase_service.dart';
import '../../../widgets/common_dialog_widget.dart';
import '../../../widgets/modified_text_field.dart';
import '../../../widgets/snackbar.dart';

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

  @override
  void initState() {
    super.initState();
    // Auto-dismiss dialog if OAuth login completes while dialog is visible
    ever(_supabaseService.isLoggedIn, (bool loggedIn) {
      if (loggedIn && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(context, "Signed in successfully!", size: SanckBarSize.BIG),
        );
      }
    });
  }

  void _loginWithGoogle() async {
    setState(() {
      _validationError = '';
    });
    final success = await _supabaseService.signInWithGoogle();
    if (!mounted) return;
    if (success && _supabaseService.isLoggedIn.value) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, "Signed in with Google successfully!",
            size: SanckBarSize.BIG),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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

    bool success = false;
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

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      final msg = _authMode == SupabaseAuthMode.magicLink
          ? 'Magic link sent! Please check your email.'
          : _authMode == SupabaseAuthMode.signUp
              ? 'Account created successfully!'
              : 'Signed in successfully!';
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, msg, size: SanckBarSize.BIG),
      );
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
              Obx(() {
                final isLoading = _supabaseService.isAuthenticating.value;
                return OutlinedButton(
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
                  onPressed: isLoading ? null : _loginWithGoogle,
                  child: Row(
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
                );
              }),

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
              Obx(() {
                final isLoading = _supabaseService.isAuthenticating.value;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: isLoading ? null : _submit,
                  child: isLoading
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
                );
              }),

              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
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
