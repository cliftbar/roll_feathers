import 'dart:io';
import 'dart:ui';

import 'package:home_assistant/home_assistant.dart';
import 'package:logging/logging.dart';

import '../../dice_sdks/message_sdk.dart';
import '../../util/color.dart';
import 'ha_config_service.dart';
import 'ha_service.dart';

class HaLibService implements HaService {
  final _log = Logger("HaLibService");
  final HaConfigService _haConfig;
  late HomeAssistant _homeAssistant;

  HaLibService._(this._haConfig);

  @override
  Future<void> init() async {
    HaConfig conf = await _haConfig.getConfig();
    _homeAssistant = HomeAssistant(baseUrl: conf.url, bearerToken: conf.token);
  }

  static Future<HaService> create() async {
    HaLibService service = HaLibService._(HaConfigService());
    service.init();

    return service;
  }

  @override
  Future<void> blinkLightEntity(String entity, Blinker blink, {int times = 1}) async {
    Map<String, dynamic> revertPayload = {};
    var revertAction = HaDomainService.lightOn;

    try {
      var currentState = await _homeAssistant.fetchState(entity);
      revertPayload = {"rgb_color": currentState.attributes.rgbColor, "brightness": currentState.attributes.brightness};
    } catch (e) {
      ("error reading ha state of '$entity': $e");
      revertAction = HaDomainService.lightOff;
    }

    Map<String, dynamic> blinkPayload = {
      "rgb_color": [blink.r255(), blink.g255(), blink.b255()],
      "brightness": blink.a255(),
    };

    for (int i = 0; i < times; i++) {
      await _homeAssistant.executeService(entity, HaDomainService.lightOn.service, additionalActions: blinkPayload);
      sleep(Duration(milliseconds: blink.getOnDuration().inMilliseconds));
    }

    await _homeAssistant.executeService(entity, revertAction.service, additionalActions: revertPayload);

    _log.fine("HA blink");
  }

  @override
  Future<void> setEntityColor(String entity, Color color) async {
    RFColor c = RFColor.of(color);

    Map<String, dynamic> setPayload = {
      "rgb_color": [c.r255(), c.g255(), c.b255()],
      "brightness": c.a255(),
    };

    await _homeAssistant.executeService(entity, HaDomainService.lightOn.service, additionalActions: setPayload);
  }
}
