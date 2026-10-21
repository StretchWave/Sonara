import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '/services/ytaccount/yt_account_service.dart';
import '../../widgets/common_dialog_widget.dart';
import '../../widgets/modified_text_field.dart';
import '../../widgets/snackbar.dart';

/// Mobile sign-in: a real Google login inside an embedded browser, landing
/// back on YouTube Music where the `.youtube.com` cookie jar (SID/SAPISID)
/// is harvested to authorize our InnerTube calls.
class YtLoginScreen extends StatefulWidget {
  const YtLoginScreen({super.key});

  @override
  State<YtLoginScreen> createState() => _YtLoginScreenState();
}

class _YtLoginScreenState extends State<YtLoginScreen> {
  static const _allowedHostSuffixes = [
    '.google.com',
    '.youtube.com',
    '.gstatic.com',
    '.googleusercontent.com',
    '.youtube-nocookie.com',
  ];

  bool _allowedHost(String host) =>
      host == 'accounts.google.com' ||
      host == 'music.youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'myaccount.google.com' ||
      _allowedHostSuffixes.any(host.endsWith);

  Future<void> _tryCapture({bool shouldPop = true}) async {
    try {
      final cookies = await CookieManager.instance()
          .getCookies(url: WebUri(YtAccountService.ytmOrigin));
      final map = <String, String>{
        for (final c in cookies)
          if (c.value != null) c.name: c.value!,
      };
      final ok = Get.find<YtAccountService>().applyCookies(map);
      if (ok) {
        if (shouldPop && context.mounted) Navigator.of(context).pop();
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "ytAccountLinkedSuccess".tr,
            size: SanckBarSize.MEDIUM));
      } else {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "ytAccountSapisidMiss".tr,
            size: SanckBarSize.MEDIUM));
      }
    } catch (e) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "ytAccountCaptureError".tr,
          size: SanckBarSize.MEDIUM));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text("ytAccountLogin".tr),
        actions: [
          IconButton(
              tooltip: "ytAccountCapture".tr,
              onPressed: _tryCapture,
              icon: const Icon(Icons.sync))
        ],
      ),
      body: InAppWebView(
        initialUrlRequest:
            URLRequest(url: WebUri(YtAccountService.loginUrl)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useHybridComposition: true,
          thirdPartyCookiesEnabled: true,
        ),
        onLoadStart: (controller, url) {
          final host = url?.host ?? '';
          if (!_allowedHost(host)) {
            controller.stopLoading();
          }
        },
        onLoadStop: (controller, url) {
          if ((url?.host ?? '').endsWith('music.youtube.com')) {
            _tryCapture();
          }
        },
      ),
    );
  }
}

/// Desktop sign-in: no supported embedded browser, so the cookie string
/// is copied from a signed-in music.youtube.com tab (Application > Cookies)
/// and pasted here; verify that SAPISID is included before accepting.
void showYtPasteCookiesDialog(BuildContext context) {
  final inputController = TextEditingController();
  showDialog(
      context: context,
      builder: (context) {
        return CommonDialog(
          child: Container(
            height: 350,
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("ytAccountLogin".tr,
                    style: Theme.of(context).textTheme.titleLarge),
                Padding(
                  padding: const EdgeInsets.only(top: 15, bottom: 10),
                  child: Text("ytAccountPasteDes".tr,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ModifiedTextField(
                    controller: inputController,
                    cursorColor: Theme.of(context).textTheme.titleSmall!.color,
                    decoration: InputDecoration(hintText: "ytAccountPasteHint".tr)),
                Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).textTheme.titleLarge!.color,
                        borderRadius: BorderRadius.circular(10)),
                    child: InkWell(
                      onTap: () {
                        String text = inputController.text.trim();
                        if (text.startsWith('Cookie:')) {
                          text = text.substring('Cookie:'.length).trim();
                        }
                        final map = <String, String>{};
                        for (var part in text.split(';')) {
                          final parts = part.split('=');
                          if (parts.length >= 2) {
                            map[parts.first.trim()] =
                                parts.sublist(1).join('=').trim();
                          }
                        }
                        final ok =
                            Get.find<YtAccountService>().applyCookies(map);
                        if (ok) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(Get.context!).showSnackBar(
                              snackbar(
                                  Get.context!, "ytAccountLinkedSuccess".tr,
                                  size: SanckBarSize.MEDIUM));
                        } else {
                          ScaffoldMessenger.of(Get.context!).showSnackBar(
                              snackbar(
                                  Get.context!, "ytAccountSapisidMiss".tr,
                                  size: SanckBarSize.MEDIUM));
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        child: Text("link".tr,
                            style: TextStyle(
                                color: Theme.of(context).canvasColor)),
                      ),
                    )),
              ],
            ),
          ),
        );
      });
}
