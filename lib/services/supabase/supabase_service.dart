import 'dart:async';
import 'dart:io';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/helper.dart';

/// Service managing optional Supabase authentication and client lifecycle.
///
/// Follows Sonara's GetxService pattern. Keeps auth state reactive and provides
/// safe, non-blocking auth methods (Password and Magic Link).
class SupabaseService extends GetxService {
  SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSubscription;

  final isLoggedIn = false.obs;
  final userEmail = ''.obs;
  final userId = ''.obs;
  final isAuthenticating = false.obs;
  final authErrorMessage = ''.obs;

  SupabaseClient? get client => _client;

  @override
  void onInit() {
    super.onInit();
    try {
      _client = Supabase.instance.client;
      _updateUserFromSession(_client?.auth.currentSession);
      _authSubscription = _client?.auth.onAuthStateChange.listen(
        (data) {
          _updateUserFromSession(data.session);
        },
        onError: (error, stackTrace) {
          printERROR("Supabase auth stream error: $error");
          isAuthenticating.value = false;
          authErrorMessage.value =
              error is AuthException ? error.message : error.toString();
        },
      );
    } catch (e) {
      printERROR("SupabaseService initialization failed: $e");
    }
  }

  /// Resets authenticating state and error message (e.g. on dialog cancel/dismiss).
  void cancelAuthentication() {
    isAuthenticating.value = false;
    authErrorMessage.value = '';
  }

  /// Handles incoming OAuth deep links from Android/iOS.
  Future<void> handleAuthDeeplink(Uri uri) async {
    try {
      printINFO("SupabaseService handling auth deep link: $uri");
      isAuthenticating.value = true;
      authErrorMessage.value = '';

      if (_client?.auth.currentSession != null) {
        _updateUserFromSession(_client?.auth.currentSession);
        return;
      }

      final res = await _client?.auth.getSessionFromUrl(uri);
      if (res?.session != null) {
        _updateUserFromSession(res!.session);
      } else {
        _updateUserFromSession(_client?.auth.currentSession);
      }
    } on AuthException catch (e) {
      printERROR("Supabase AuthException from deep link: ${e.message}");
      authErrorMessage.value = e.message;
    } catch (e) {
      printERROR("Supabase deep link error: $e");
      authErrorMessage.value = e.toString();
    } finally {
      isAuthenticating.value = false;
    }
  }

  void _updateUserFromSession(Session? session) {
    if (session != null && session.user.email != null) {
      isLoggedIn.value = true;
      userEmail.value = session.user.email ?? '';
      userId.value = session.user.id;
      isAuthenticating.value = false;
      authErrorMessage.value = '';
    } else {
      isLoggedIn.value = false;
      userEmail.value = '';
      userId.value = '';
    }
  }

  /// Sign in with email and password
  Future<bool> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (_client == null) {
      authErrorMessage.value = "Supabase client not initialized";
      return false;
    }
    isAuthenticating.value = true;
    authErrorMessage.value = '';
    try {
      final response = await _client!.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      _updateUserFromSession(response.session);
      isAuthenticating.value = false;
      return true;
    } on AuthException catch (e) {
      printERROR("Supabase signInWithPassword AuthException: ${e.message}");
      authErrorMessage.value = e.message;
      isAuthenticating.value = false;
      return false;
    } catch (e) {
      printERROR("Supabase signInWithPassword error: $e");
      authErrorMessage.value = e.toString();
      isAuthenticating.value = false;
      return false;
    }
  }

  /// Sign up with email and password
  Future<bool> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    if (_client == null) {
      authErrorMessage.value = "Supabase client not initialized";
      return false;
    }
    isAuthenticating.value = true;
    authErrorMessage.value = '';
    try {
      final response = await _client!.auth.signUp(
        email: email.trim(),
        password: password,
      );
      _updateUserFromSession(response.session);
      isAuthenticating.value = false;
      return true;
    } on AuthException catch (e) {
      printERROR("Supabase signUpWithPassword AuthException: ${e.message}");
      authErrorMessage.value = e.message;
      isAuthenticating.value = false;
      return false;
    } catch (e) {
      printERROR("Supabase signUpWithPassword error: $e");
      authErrorMessage.value = e.toString();
      isAuthenticating.value = false;
      return false;
    }
  }

  /// Send an email OTP / magic link for passwordless login
  Future<bool> sendMagicLink({required String email}) async {
    if (_client == null) {
      authErrorMessage.value = "Supabase client not initialized";
      return false;
    }
    isAuthenticating.value = true;
    authErrorMessage.value = '';
    try {
      await _client!.auth.signInWithOtp(
        email: email.trim(),
        emailRedirectTo: 'io.supabase.sonara://login-callback/',
      );
      isAuthenticating.value = false;
      return true;
    } on AuthException catch (e) {
      printERROR("Supabase sendMagicLink AuthException: ${e.message}");
      authErrorMessage.value = e.message;
      isAuthenticating.value = false;
      return false;
    } catch (e) {
      printERROR("Supabase sendMagicLink error: $e");
      authErrorMessage.value = e.toString();
      isAuthenticating.value = false;
      return false;
    }
  }

  /// Sign in with Google using OAuth.
  /// Works across Desktop (via local loopback callback) and Mobile (via deep link).
  Future<bool> signInWithGoogle() async {
    if (_client == null) {
      authErrorMessage.value = "Supabase client not initialized";
      return false;
    }
    isAuthenticating.value = true;
    authErrorMessage.value = '';

    HttpServer? loopbackServer;
    try {
      String redirectTo;
      if (GetPlatform.isDesktop) {
        try {
          loopbackServer =
              await HttpServer.bind(InternetAddress.loopbackIPv4, 54321);
        } catch (_) {
          loopbackServer =
              await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        }
        redirectTo = 'http://localhost:${loopbackServer.port}/auth/callback';
        _listenToLoopbackAuth(loopbackServer);
      } else {
        redirectTo = 'io.supabase.sonara://login-callback/';
      }

      final success = await _client!.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      if (!success) {
        authErrorMessage.value = "Could not open browser for Google Sign-In.";
        await loopbackServer?.close(force: true);
        isAuthenticating.value = false;
        return false;
      }

      // Safety timeout: if OAuth callback is never received (e.g. user closed browser),
      // reset authenticating flag after 90 seconds so UI does not stay frozen.
      Future.delayed(const Duration(seconds: 90), () {
        if (isAuthenticating.value && !isLoggedIn.value) {
          isAuthenticating.value = false;
        }
      });

      return true;
    } on AuthException catch (e) {
      printERROR("Supabase Google AuthException: ${e.message}");
      if (e.message.toLowerCase().contains("not enabled")) {
        authErrorMessage.value =
            "Google provider is not enabled in your Supabase project dashboard. Please enable it under Authentication -> Providers.";
      } else {
        authErrorMessage.value = e.message;
      }
      await loopbackServer?.close(force: true);
      isAuthenticating.value = false;
      return false;
    } catch (e) {
      printERROR("Supabase Google Sign-In error: $e");
      authErrorMessage.value = e.toString();
      await loopbackServer?.close(force: true);
      isAuthenticating.value = false;
      return false;
    }
  }

  void _listenToLoopbackAuth(HttpServer server) async {
    try {
      final request = await server.first.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw TimeoutException("Login timed out"),
      );

      final uri = request.uri;
      try {
        final response = await _client?.auth.getSessionFromUrl(uri);
        _updateUserFromSession(response?.session);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('''
<!DOCTYPE html>
<html>
<head>
  <title>Sonara - Sign In Successful</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; background: #121212; color: #fff; text-align: center; padding: 60px 20px; }
    h1 { color: #4ade80; font-size: 24px; margin-bottom: 8px; }
    p { color: #a1a1aa; font-size: 16px; }
  </style>
</head>
<body>
  <h1>Sign In Successful!</h1>
  <p>You can close this window and return to Sonara.</p>
</body>
</html>
''');
        await request.response.close();
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.html
          ..write('Authentication error: $e');
        await request.response.close();
      }
    } catch (e) {
      printERROR("Loopback auth listener error: $e");
    } finally {
      await server.close(force: true);
      isAuthenticating.value = false;
    }
  }

  /// Manually handles an auth callback URI (e.g. if passed from deep link or pasted)
  Future<bool> handleAuthCallbackUri(Uri uri) async {
    if (_client == null) return false;
    try {
      final response = await _client!.auth.getSessionFromUrl(uri);
      _updateUserFromSession(response.session);
      return true;
    } catch (e) {
      printERROR("handleAuthCallbackUri error: $e");
      authErrorMessage.value = e.toString();
      return false;
    }
  }

  /// Sign out without deleting local playlists or user data
  Future<void> signOut() async {
    if (_client == null) return;
    try {
      await _client!.auth.signOut();
    } catch (e) {
      printERROR("Supabase signOut error: $e");
    } finally {
      isLoggedIn.value = false;
      userEmail.value = '';
      userId.value = '';
      authErrorMessage.value = '';
    }
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    super.onClose();
  }
}
