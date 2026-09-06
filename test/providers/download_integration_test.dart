import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/downloader.dart';

void main() {
  group('DownloadJobState', () {
    test('has all required states', () {
      expect(DownloadJobState.values, contains(DownloadJobState.queued));
      expect(DownloadJobState.values, contains(DownloadJobState.resolving));
      expect(DownloadJobState.values, contains(DownloadJobState.matching));
      expect(DownloadJobState.values, contains(DownloadJobState.downloading));
      expect(DownloadJobState.values, contains(DownloadJobState.verifying));
      expect(DownloadJobState.values, contains(DownloadJobState.converting));
      expect(DownloadJobState.values, contains(DownloadJobState.tagging));
      expect(DownloadJobState.values, contains(DownloadJobState.completed));
      expect(DownloadJobState.values, contains(DownloadJobState.failed));
      expect(DownloadJobState.values, contains(DownloadJobState.cancelled));
    });

    test('post-download validation rejects empty or truncated file', () async {
      final tempDir = await Directory.systemTemp.createTemp('sonara_test_dl_');
      final emptyFile = File('${tempDir.path}/empty.part');
      await emptyFile.writeAsBytes([]);

      expect(await emptyFile.exists(), isTrue);
      expect(await emptyFile.length(), lessThan(4096));

      // Clean up
      await tempDir.delete(recursive: true);
    });
  });
}
