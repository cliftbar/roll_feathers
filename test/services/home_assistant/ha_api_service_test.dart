import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:roll_feathers/dice_sdks/message_sdk.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_api_service.dart';
import 'package:roll_feathers/testing/ha_mock_server.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// Exercises HaApiService end-to-end over a real HTTP client against an
// in-process HaMockServer, instead of MockClient stubs — the same approach
// dddice_mock_server_test.dart uses for DddiceRepository. HaApiService reads
// its base URL from HaConfigService at call time (not a constructor param),
// so pointing it at the mock is just a matter of seeding HaConfig.url.
void main() {
  late HaMockServer mock;
  late HaApiService service;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    mock = HaMockServer();
    await mock.start();
    await HaConfigService().setConfig(
      HaConfig(enabled: true, url: mock.baseUrl, token: 'test-token', entity: 'light.default'),
    );
    service = await HaApiService.create(http.Client());
  });

  tearDown(() => mock.close());

  group('blinkLightEntity', () {
    test('turns the light on with the requested color, then restores prior state', () async {
      mock.seedState('light.test', state: 'off');

      await service.blinkLightEntity('light.test', BasicBlinker(1, const Duration(milliseconds: 1), Duration.zero,
          const Color.fromARGB(255, 10, 20, 30)));

      final calls = mock.serviceCalls;
      expect(calls, hasLength(2));
      expect(calls[0].domain, 'light');
      expect(calls[0].service, 'turn_on');
      expect(calls[0].body['rgb_color'], [10, 20, 30]);
      expect(calls[1].service, 'turn_off');
    });

    test('restores to on with prior color when light was already on', () async {
      mock.seedState('light.test',
          state: 'on', attributes: {'color_mode': 'rgb', 'rgb_color': [1, 2, 3], 'brightness': 99});

      await service.blinkLightEntity('light.test', BasicBlinker(1, const Duration(milliseconds: 1), Duration.zero,
          const Color.fromARGB(255, 10, 20, 30)));

      final restoreCall = mock.serviceCalls.last;
      expect(restoreCall.service, 'turn_on');
      expect(restoreCall.body['rgb_color'], [1, 2, 3]);
      expect(restoreCall.body['brightness'], 99);
    });
  });

  test('setEntityColor turns the light on with the given color', () async {
    await service.setEntityColor('light.test', const Color.fromARGB(255, 4, 5, 6));

    final call = mock.serviceCalls.single;
    expect(call.domain, 'light');
    expect(call.service, 'turn_on');
    expect(call.body['rgb_color'], [4, 5, 6]);
  });
}
