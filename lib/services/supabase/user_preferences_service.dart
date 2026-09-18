import 'package:get/get.dart';
import '../../utils/helper.dart';
import 'supabase_service.dart';

/// Handles Supabase CRUD for the `user_preferences` table.
///
/// All methods are best-effort and return `null` / swallow errors
/// gracefully so the app never blocks on cloud preference failures.
class UserPreferencesService extends GetxService {
  SupabaseService get _supabase => Get.find<SupabaseService>();

  /// Loads the user's preferences from Supabase.
  ///
  /// Returns the raw row as a `Map`, or `null` if unavailable.
  Future<Map<String, dynamic>?> loadPreferences(String userId) async {
    final client = _supabase.client;
    if (client == null) return null;

    try {
      final rows = await client
          .from('user_preferences')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (rows.isNotEmpty) {
        return Map<String, dynamic>.from(rows.first);
      }
      return null;
    } catch (e) {
      printERROR('UserPreferencesService.loadPreferences error: $e');
      return null;
    }
  }

  /// Upserts the user's preferences to Supabase.
  Future<void> savePreferences({
    required String userId,
    required List<String> musicLanguages,
    required List<Map<String, dynamic>> favoriteArtists,
    required bool onboardingCompleted,
  }) async {
    final client = _supabase.client;
    if (client == null) return;

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      await client.from('user_preferences').upsert(
        {
          'user_id': userId,
          'music_languages': musicLanguages,
          'favorite_artists': favoriteArtists,
          'onboarding_completed': onboardingCompleted,
          'updated_at': nowIso,
        },
        onConflict: 'user_id',
      );
    } catch (e) {
      printERROR('UserPreferencesService.savePreferences error: $e');
    }
  }
}
