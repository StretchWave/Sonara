/// Pre-playback and pre-download stream validation to prevent playing
/// broken URLs, previews, or wrong recordings.
library;

import 'matching/duration_policy.dart';
import 'resolved_stream.dart';

/// Result of stream validation.
class StreamValidationResult {
  final bool isValid;
  final String? failureReason;
  final bool isPreview;

  const StreamValidationResult({
    required this.isValid,
    this.failureReason,
    this.isPreview = false,
  });

  factory StreamValidationResult.valid() =>
      const StreamValidationResult(isValid: true);

  factory StreamValidationResult.invalid(String reason, {bool isPreview = false}) =>
      StreamValidationResult(
        isValid: false,
        failureReason: reason,
        isPreview: isPreview,
      );
}

/// Comprehensive validator for a resolved stream before playback or download.
class StreamValidator {
  const StreamValidator._();

  /// Validates [stream] against expected parameters.
  static StreamValidationResult validate(
    ResolvedStream stream, {
    int? expectedDurationMs,
    String? expectedProviderId,
  }) {
    // 1. Playability check
    if (!stream.playable) {
      return StreamValidationResult.invalid(
        stream.statusMSG.isNotEmpty ? stream.statusMSG : 'Stream is marked unplayable',
      );
    }

    // 2. Audio format presence
    if (stream.audioFormats.isEmpty) {
      return StreamValidationResult.invalid('Stream contains no audio formats');
    }

    final primaryAudio = stream.audioFormats.first;

    // 3. URL validity and protocol
    final url = primaryAudio.url;
    if (url.trim().isEmpty) {
      return StreamValidationResult.invalid('Stream URL is empty');
    }

    final uri = Uri.tryParse(url.trim());
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return StreamValidationResult.invalid('Invalid stream URL protocol or format');
    }

    // 4. Provider identity check
    if (expectedProviderId != null &&
        expectedProviderId.isNotEmpty &&
        stream.providerId.isNotEmpty &&
        stream.providerId != expectedProviderId) {
      return StreamValidationResult.invalid(
        'Stream provider (${stream.providerId}) does not match expected provider ($expectedProviderId)',
      );
    }

    // 5. Preview detection via duration check
    final actualDurationMs =
        primaryAudio.duration > 0 ? primaryAudio.duration : null;
    if (expectedDurationMs != null && actualDurationMs != null) {
      if (isStreamDurationMismatched(
        expectedMs: expectedDurationMs,
        actualMs: actualDurationMs,
        providerId: stream.providerId,
      )) {
        return StreamValidationResult.invalid(
          'Stream is a preview or truncated (${actualDurationMs ~/ 1000}s vs expected ${expectedDurationMs ~/ 1000}s)',
          isPreview: true,
        );
      }
    }

    return StreamValidationResult.valid();
  }
}
