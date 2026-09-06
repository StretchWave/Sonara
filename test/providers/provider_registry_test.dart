import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/models/provider_id.dart';
import 'package:sonara/services/providers/provider_registry.dart';
import 'package:sonara/services/providers/stream_route_config.dart';

void main() {
  group('ProviderRegistry', () {
    test('has all standard providers registered with capabilities', () {
      final registry = ProviderRegistry.instance;
      expect(registry.allDescriptors.length, greaterThanOrEqualTo(9));

      final qobuz = registry.getDescriptor(ProviderId.qobuz);
      expect(qobuz, isNotNull);
      expect(qobuz!.capabilities.supportsLossless, isTrue);
      expect(qobuz.capabilities.supportsHiRes, isTrue);
      expect(qobuz.capabilities.supportsIsrcSearch, isTrue);

      final yt = registry.getDescriptor(ProviderId.youtubeMusic);
      expect(yt, isNotNull);
      expect(yt!.capabilities.supportsLossless, isFalse);
    });

    test('builds ordered provider chain respecting config', () {
      final registry = ProviderRegistry.instance;
      const config = StreamRouteConfig(
        qobuzEnabled: true,
        qobuzInstances: ['https://q.example'],
        tidalEnabled: false,
        soundcloudEnabled: true,
        providerOrder: ['soundcloud', 'qobuz', 'youtube_music'],
      );

      final chain = registry.buildProviderChain(config);
      final ids = chain.map((p) => p.id).toList();

      expect(ids, contains('soundcloud'));
      expect(ids, contains('qobuz'));
      expect(ids, contains('youtube_music'));
      expect(ids.indexOf('soundcloud'), lessThan(ids.indexOf('qobuz')));
    });

    test('forceProviderId returns only that provider if configured', () {
      final registry = ProviderRegistry.instance;
      const config = StreamRouteConfig(
        qobuzEnabled: true,
        qobuzInstances: ['https://q.example'],
      );

      final forced = registry.buildProviderChain(config, forceProviderId: 'qobuz');
      expect(forced, hasLength(1));
      expect(forced.first.id, 'qobuz');

      final forcedMissing = registry.buildProviderChain(config, forceProviderId: 'nonexistent');
      expect(forcedMissing, isEmpty);
    });
  });
}
