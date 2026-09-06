import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '/ui/widgets/cust_switch.dart';
import '../settings_screen_controller.dart';

/// Dedicated screen for configuring individual audio streaming sources,
/// custom resolver endpoints, audio qualities, and session credentials.
///
/// Keeps the main Settings screen clean and un-congested.
class ConfigureSourcesScreen extends StatelessWidget {
  const ConfigureSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure sources'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader(
            context,
            title: 'Hi-Res & Lossless Resolvers',
            subtitle:
                'Community or self-hosted resolvers for lossless FLAC / AAC audio.',
          ),
          const SizedBox(height: 4),

          // ---- Qobuz ----
          _buildSourceCard(
            context,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.album),
                  title: const Text('Qobuz (no login, resolver-based)'),
                  subtitle: Text(
                    'Streams Hi-Res 24-bit FLAC / CD FLAC through Kenny-style scraper instances.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  trailing: Obx(
                    () => CustSwitch(
                      value: settingsController.qobuzEnabled.value,
                      onChanged: settingsController.toggleQobuzEnabled,
                    ),
                  ),
                ),
                Obx(() => settingsController.qobuzEnabled.isTrue
                    ? Padding(
                        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: const Text('Resolver instances'),
                              subtitle: Obx(() => Text(
                                    settingsController.qobuzInstances.value.isEmpty
                                        ? 'One URL per line (e.g. https://kqobuz.example.com)'
                                        : settingsController.qobuzInstances.value,
                                    style: theme.textTheme.bodySmall,
                                  )),
                              trailing: const Icon(Icons.edit, size: 18),
                              onTap: () => _showQobuzInstancesDialog(
                                  context, settingsController),
                            ),
                            ListTile(
                              dense: true,
                              title: const Text('Country catalog'),
                              subtitle: Obx(() => Text(
                                    settingsController.qobuzCountry.value,
                                    style: theme.textTheme.bodySmall,
                                  )),
                              trailing: const Icon(Icons.public, size: 18),
                              onTap: () => _showQobuzCountryDialog(
                                  context, settingsController),
                            ),
                            ListTile(
                              dense: true,
                              title: const Text('Stream quality'),
                              trailing: Obx(
                                () => DropdownButton<int>(
                                  dropdownColor: theme.cardColor,
                                  underline: const SizedBox.shrink(),
                                  value: settingsController.qobuzQuality.value,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 27,
                                        child: Text('Hi-Res (24-bit / 192 kHz)')),
                                    DropdownMenuItem(
                                        value: 7, child: Text('24-bit / 96 kHz')),
                                    DropdownMenuItem(
                                        value: 6, child: Text('CD FLAC (16-bit)')),
                                    DropdownMenuItem(
                                        value: 5, child: Text('MP3 320 kbps')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      settingsController.changeQobuzQuality(val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- Tidal ----
          _buildSourceCard(
            context,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.waves),
                  title: const Text('Tidal (no login, resolver-based)'),
                  subtitle: Text(
                    'Streams Hi-Res FLAC, lossless FLAC, or high-bitrate AAC via resolver endpoints.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  trailing: Obx(
                    () => CustSwitch(
                      value: settingsController.tidalEnabled.value,
                      onChanged: settingsController.toggleTidalEnabled,
                    ),
                  ),
                ),
                Obx(() => settingsController.tidalEnabled.isTrue
                    ? Padding(
                        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: const Text('Resolver endpoints'),
                              subtitle: Obx(() => Text(
                                    settingsController.tidalEndpoints.value.isEmpty
                                        ? 'One URL per line'
                                        : settingsController.tidalEndpoints.value,
                                    style: theme.textTheme.bodySmall,
                                  )),
                              trailing: const Icon(Icons.edit, size: 18),
                              onTap: () => _showTidalEndpointsDialog(
                                  context, settingsController),
                            ),
                            ListTile(
                              dense: true,
                              title: const Text('Stream quality'),
                              trailing: Obx(
                                () => DropdownButton<String>(
                                  dropdownColor: theme.cardColor,
                                  underline: const SizedBox.shrink(),
                                  value: settingsController.tidalQuality.value,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'HI_RES_LOSSLESS',
                                        child: Text('Hi-Res FLAC')),
                                    DropdownMenuItem(
                                        value: 'LOSSLESS',
                                        child: Text('Lossless (16-bit FLAC)')),
                                    DropdownMenuItem(
                                        value: 'HIGH',
                                        child: Text('High (320 kbps AAC)')),
                                    DropdownMenuItem(
                                        value: 'LOW',
                                        child: Text('Low (96 kbps AAC)')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      settingsController.changeTidalQuality(val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- Deezer ----
          _buildSourceCard(
            context,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.equalizer),
                  title: const Text('Deezer (resolver-based)'),
                  subtitle: Text(
                    'Streams FLAC (16-bit / 44.1 kHz) and MP3 via community or self-hosted resolvers.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  trailing: Obx(
                    () => CustSwitch(
                      value: settingsController.deezerEnabled.value,
                      onChanged: settingsController.toggleDeezerEnabled,
                    ),
                  ),
                ),
                Obx(() => settingsController.deezerEnabled.isTrue
                    ? Padding(
                        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: const Text('Resolver endpoints'),
                              subtitle: Obx(() => Text(
                                    settingsController.deezerEndpoints.value.isEmpty
                                        ? 'Using default community endpoints'
                                        : settingsController.deezerEndpoints.value,
                                    style: theme.textTheme.bodySmall,
                                  )),
                              trailing: const Icon(Icons.edit, size: 18),
                              onTap: () => _showDeezerEndpointsDialog(
                                  context, settingsController),
                            ),
                            ListTile(
                              dense: true,
                              title: const Text('Stream quality'),
                              trailing: Obx(
                                () => DropdownButton<String>(
                                  dropdownColor: theme.cardColor,
                                  underline: const SizedBox.shrink(),
                                  value: settingsController.deezerQuality.value,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'FLAC',
                                        child: Text('FLAC (16-bit / 44.1 kHz)')),
                                    DropdownMenuItem(
                                        value: 'MP3_320',
                                        child: Text('MP3 320 kbps')),
                                    DropdownMenuItem(
                                        value: 'MP3_128',
                                        child: Text('MP3 128 kbps')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      settingsController.changeDeezerQuality(val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- Apple Music ----
          _buildSourceCard(
            context,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.apple),
                  title: const Text('Apple Music (resolver-based)'),
                  subtitle: Text(
                    'Streams AAC (up to 256 kbps) or Dolby Atmos via gamdl resolver.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  trailing: Obx(
                    () => CustSwitch(
                      value: settingsController.appleEnabled.value,
                      onChanged: settingsController.toggleAppleEnabled,
                    ),
                  ),
                ),
                Obx(() => settingsController.appleEnabled.isTrue
                    ? Padding(
                        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: const Text('Resolver endpoints'),
                              subtitle: Obx(() => Text(
                                    settingsController.appleEndpoints.value.isEmpty
                                        ? 'Using default community endpoints'
                                        : settingsController.appleEndpoints.value,
                                    style: theme.textTheme.bodySmall,
                                  )),
                              trailing: const Icon(Icons.edit, size: 18),
                              onTap: () => _showAppleEndpointsDialog(
                                  context, settingsController),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- Amazon Music ----
          _buildSourceCard(
            context,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.music_note),
                  title: const Text('Amazon Music (resolver-based)'),
                  subtitle: Text(
                    'Streams Ultra HD Hi-Res FLAC (24-bit) or HD FLAC (16-bit) via ASIN resolver.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  trailing: Obx(
                    () => CustSwitch(
                      value: settingsController.amazonEnabled.value,
                      onChanged: settingsController.toggleAmazonEnabled,
                    ),
                  ),
                ),
                Obx(() => settingsController.amazonEnabled.isTrue
                    ? Padding(
                        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: const Text('Resolver endpoints'),
                              subtitle: Obx(() => Text(
                                    settingsController.amazonEndpoints.value.isEmpty
                                        ? 'Using default community endpoints'
                                        : settingsController.amazonEndpoints.value,
                                    style: theme.textTheme.bodySmall,
                                  )),
                              trailing: const Icon(Icons.edit, size: 18),
                              onTap: () => _showAmazonEndpointsDialog(
                                  context, settingsController),
                            ),
                            ListTile(
                              dense: true,
                              title: const Text('Stream quality'),
                              trailing: Obx(
                                () => DropdownButton<String>(
                                  dropdownColor: theme.cardColor,
                                  underline: const SizedBox.shrink(),
                                  value: settingsController.amazonQuality.value,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'HI_RES',
                                        child: Text('Hi-Res (24-bit FLAC)')),
                                    DropdownMenuItem(
                                        value: 'LOSSLESS',
                                        child: Text('HD (16-bit FLAC)')),
                                    DropdownMenuItem(
                                        value: 'HIGH',
                                        child: Text('Standard (256 kbps)')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      settingsController.changeAmazonQuality(val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _buildSectionHeader(
            context,
            title: 'Open & Catalog Sources',
            subtitle: 'Free streaming fallback sources and audio archives.',
          ),
          const SizedBox(height: 4),

          // ---- SoundCloud ----
          _buildSourceCard(
            context,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.cloud_queue),
              title: const Text('SoundCloud'),
              subtitle: Text(
                'Direct streaming fallback for indie tracks, bootlegs, remixes, and podcasts.',
                style: theme.textTheme.bodyMedium,
              ),
              trailing: Obx(
                () => CustSwitch(
                  value: settingsController.soundcloudEnabled.value,
                  onChanged: settingsController.toggleSoundCloudEnabled,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ---- Internet Archive ----
          _buildSourceCard(
            context,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.account_balance),
              title: const Text('Internet Archive'),
              subtitle: Text(
                'Free lossless FLAC and MP3 for thousands of live concerts, bootlegs, and public recordings.',
                style: theme.textTheme.bodyMedium,
              ),
              trailing: Obx(
                () => CustSwitch(
                  value: settingsController.internetArchiveEnabled.value,
                  onChanged: settingsController.toggleInternetArchiveEnabled,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ---- Instagram ----
          _buildSourceCard(
            context,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Instagram Audio (Reels/Clips)'),
                  subtitle: Text(
                    'Resolves direct CDN audio streams from Instagram links and clips.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  trailing: Obx(
                    () => CustSwitch(
                      value: settingsController.instagramEnabled.value,
                      onChanged: settingsController.toggleInstagramEnabled,
                    ),
                  ),
                ),
                Obx(() => settingsController.instagramEnabled.isTrue
                    ? Padding(
                        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: const Text('Session cookie'),
                              subtitle: Obx(() => Text(
                                    settingsController.instagramCookie.value.isEmpty
                                        ? 'No cookie set (login required for private audio)'
                                        : 'Cookie saved',
                                    style: theme.textTheme.bodySmall,
                                  )),
                              trailing: const Icon(Icons.lock_outline, size: 18),
                              onTap: () => _showInstagramCookieDialog(
                                  context, settingsController),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildSourceCard(BuildContext context, {required Widget child}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.secondary.withAlpha(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: child,
    );
  }

  // ---- Dialogs -----------------------------------------------------------

  Future<void> _showQobuzInstancesDialog(
      BuildContext context, SettingsScreenController settingsController) {
    final input =
        TextEditingController(text: settingsController.qobuzInstances.value);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Qobuz resolver instances'),
        content: TextField(
          controller: input,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'One URL per line'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settingsController.changeQobuzInstances(input.text.trim());
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTidalEndpointsDialog(
      BuildContext context, SettingsScreenController settingsController) {
    final input =
        TextEditingController(text: settingsController.tidalEndpoints.value);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tidal resolver endpoints'),
        content: TextField(
          controller: input,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'One URL per line'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settingsController.changeTidalEndpoints(input.text.trim());
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeezerEndpointsDialog(
      BuildContext context, SettingsScreenController settingsController) {
    final input =
        TextEditingController(text: settingsController.deezerEndpoints.value);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deezer resolver endpoints'),
        content: TextField(
          controller: input,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'One URL per line (leave empty to use default)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settingsController.changeDeezerEndpoints(input.text.trim());
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAppleEndpointsDialog(
      BuildContext context, SettingsScreenController settingsController) {
    final input =
        TextEditingController(text: settingsController.appleEndpoints.value);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apple Music stream resolver'),
        content: TextField(
          controller: input,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'One URL per line (leave empty to use default)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settingsController.changeAppleEndpoints(input.text.trim());
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAmazonEndpointsDialog(
      BuildContext context, SettingsScreenController settingsController) {
    final input =
        TextEditingController(text: settingsController.amazonEndpoints.value);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Amazon Music resolver endpoints'),
        content: TextField(
          controller: input,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'One URL per line (leave empty to use default)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settingsController.changeAmazonEndpoints(input.text.trim());
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showInstagramCookieDialog(
      BuildContext context, SettingsScreenController settingsController) {
    final input =
        TextEditingController(text: settingsController.instagramCookie.value);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Instagram session cookie'),
        content: TextField(
          controller: input,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Paste your sessionid cookie value',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settingsController.changeInstagramCookie(input.text.trim());
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showQobuzCountryDialog(
      BuildContext context, SettingsScreenController settingsController) {
    final input =
        TextEditingController(text: settingsController.qobuzCountry.value);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Qobuz country'),
        content: TextField(
          controller: input,
          maxLength: 2,
          decoration: const InputDecoration(
            hintText: 'Two-letter country code, e.g. US',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (input.text.trim().length == 2) {
                settingsController.changeQobuzCountry(input.text.trim());
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
