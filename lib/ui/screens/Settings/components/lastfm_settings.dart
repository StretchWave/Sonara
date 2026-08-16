import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../services/lastfm_service.dart';
import '../../../widgets/common_dialog_widget.dart';

/// Dialog for configuring Last.fm API credentials and running the
/// authorization flow.
class LastFmSettingsDialog extends StatefulWidget {
  const LastFmSettingsDialog({super.key});

  @override
  State<LastFmSettingsDialog> createState() => _LastFmSettingsDialogState();
}

class _LastFmSettingsDialogState extends State<LastFmSettingsDialog> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _secretController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _awaitingAuth = false;

  @override
  void initState() {
    super.initState();
    final service = Get.find<LastFmService>();
    _apiKeyController = TextEditingController(text: service.apiKey.value);
    _secretController = TextEditingController(text: service.apiSecret.value);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    final service = Get.find<LastFmService>();
    await service.setCredentials(
      key: _apiKeyController.text,
      secret: _secretController.text,
    );
    final started = await service.startAuthorization();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _awaitingAuth = started;
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = Get.find<LastFmService>();
    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("lastfmScrobbling".tr,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text("lastfmCredentialsDes".tr,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: "lastfmApiKey".tr,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? "allFieldsReqMsg".tr
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _secretController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "lastfmApiSecret".tr,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? "allFieldsReqMsg".tr
                          : null,
                ),
                const SizedBox(height: 16),
                Obx(() => service.statusMessage.value.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          service.statusMessage.value,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : const SizedBox.shrink()),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text("cancel".tr),
                    ),
                    const SizedBox(width: 8),
                    _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _awaitingAuth
                            ? FilledButton(
                                onPressed: () async {
                                  setState(() => _isLoading = true);
                                  final ok = await service
                                      .completeAuthorization();
                                  if (!mounted) return;
                                  setState(() {
                                    _isLoading = false;
                                    _awaitingAuth = !ok;
                                  });
                                },
                                child: Text("lastfmAuthorizedDone".tr),
                              )
                            : FilledButton(
                                onPressed: _connect,
                                child: Text("lastfmConnect".tr),
                              ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_awaitingAuth)
                  Text("lastfmAuthInstruction".tr,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
