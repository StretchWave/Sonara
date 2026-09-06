import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../services/supabase/playlist_sync_service.dart';
import '../../../../services/supabase/supabase_service.dart';
import '../../../widgets/snackbar.dart';
import 'supabase_auth_dialog.dart';

class CloudSyncTile extends StatelessWidget {
  const CloudSyncTile({super.key});

  @override
  Widget build(BuildContext context) {
    final supabaseService = Get.find<SupabaseService>();
    final syncService = Get.find<PlaylistSyncService>();

    return Obx(() {
      final isLoggedIn = supabaseService.isLoggedIn.value;
      final isSyncing = syncService.isSyncing.value;
      final email = supabaseService.userEmail.value;

      if (!isLoggedIn) {
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 5, right: 10),
          leading: const Icon(Icons.cloud_outlined),
          title: const Text("Cloud Playlist Backup"),
          subtitle: Text(
            "Sign in to back up and sync your playlists across devices.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          isThreeLine: true,
          trailing: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const SupabaseAuthDialog(),
              );
            },
            child: const Text(
              "Sign In",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        );
      }

      // Logged In view
      return ListTile(
        contentPadding: const EdgeInsets.only(left: 5, right: 10),
        leading: const Icon(Icons.cloud_done),
        title: const Text("Cloud Playlist Backup"),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            Text(
              "Signed in as: $email",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 14,
                  color: Colors.greenAccent[400],
                ),
                const SizedBox(width: 4),
                Text(
                  "Playlist sync enabled",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.greenAccent[400],
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
            if (syncService.syncError.value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  "Sync notice: ${syncService.syncError.value}",
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                ),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sync Now button
            IconButton(
              tooltip: "Sync Now",
              icon: isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              onPressed: isSyncing
                  ? null
                  : () async {
                      await syncService.syncAll();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          snackbar(
                            context,
                            syncService.syncError.value.isEmpty
                                ? "Playlists synchronized with cloud!"
                                : "Sync completed with warning.",
                            size: SanckBarSize.MEDIUM,
                          ),
                        );
                      }
                    },
            ),
            // Sign Out button
            IconButton(
              tooltip: "Sign Out",
              icon: const Icon(Icons.logout),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text("Sign Out"),
                    content: const Text(
                      "Are you sure you want to sign out? Your local playlists will be kept safely on this device.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.secondary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await supabaseService.signOut();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              snackbar(
                                context,
                                "Signed out. Local playlists preserved.",
                                size: SanckBarSize.MEDIUM,
                              ),
                            );
                          }
                        },
                        child: const Text("Sign Out"),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );
    });
  }
}
