import 'dart:io';

import 'package:home_assistant/home_assistant.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';


import '../../dice_sdks/message_sdk.dart';

enum LightServiceActions {
  on(action: "turn_on"),
  off(action: "turn_off");

  const LightServiceActions({required this.action});

  final String action;
}

class HaService {
  final HaConfigService _haConfig;
  late HomeAssistant _homeAssistant;

  HaService._(this._haConfig);

  Future<void> init() async {
    HaConfig conf = await _haConfig.getConfig();
    _homeAssistant = HomeAssistant(baseUrl: conf.url, bearerToken: conf.token);
  }

  static Future<HaService> create() async {
    HaService service = HaService._(HaConfigService());
    service.init();

    return service;
  }

  Future<void> blinkEntity(String entity, Blinker blink) async {
    Map<String, dynamic> revertPayload = {};
    var revertAction = LightServiceActions.on;

    try {
      var currentState = await _homeAssistant.fetchState(entity);
      revertPayload = {"rgb_color": currentState.attributes.rgbColor, "brightness": currentState.attributes.brightness};
    } catch (e) {
      print("error reading ha state of '$entity': $e");
      revertAction = LightServiceActions.off;
    }

    Map<String, dynamic> blinkPayload = {
      "rgb_color": [blink.r255(), blink.g255(), blink.b255()],
      "brightness": blink.a255(),
    };

    await _homeAssistant.executeService(entity, LightServiceActions.on.action, additionalActions: blinkPayload);
    sleep(Duration(milliseconds: blink.getOnDuration().inMilliseconds));
    await _homeAssistant.executeService(entity, LightServiceActions.off.action);

    sleep(Duration(milliseconds: blink.getOffDuration().inMilliseconds));
    await _homeAssistant.executeService(entity, revertAction.action, additionalActions: revertPayload);

    print("HA blink");
  }
}
