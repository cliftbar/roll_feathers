import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_assistant/home_assistant.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';

enum LightServiceActions {
  on(action: "turn_on"),
  off(action: "turn_off");

  const LightServiceActions({required this.action});

  final String action;
}

class HaSettings {
  bool enabled;
  String url;
  String token;
  String entity;

  HaSettings(this.enabled, this.url, this.token, this.entity);
}

class HomeAssistantController {
  late HomeAssistant homeAssistant;
  late String _haUrl;
  late String _haToken;
  late String _haEntity;
  late bool _haEnabled;

  HomeAssistantController() {
    _haEnabled = bool.parse(dotenv.env['HA_ENABLED'] ?? "false");
    _haUrl = dotenv.env['HA_URL'] ?? "";
    _haToken = dotenv.env['HA_TOKEN'] ?? "";
    _haEntity = dotenv.env['HA_ENTITY'] ?? "";
    homeAssistant = HomeAssistant(baseUrl: _haUrl, bearerToken: _haToken);
  }

  void updateSettings({bool enabled = false, String? url, String? token, String? entity}) {
    if (url != null) {
      _haUrl = url;
    }
    if (token != null) {
      _haToken = token;
    }
    if (entity != null) {
      _haEntity = entity;
    }
    _haEnabled = enabled;
    homeAssistant = HomeAssistant(baseUrl: _haUrl, bearerToken: _haToken);
  }

  HaSettings getHaSettings() {
    return HaSettings(_haEnabled, _haUrl, _haToken, _haEntity);
  }
  Future<void> blinkEntity(Blinker blink) async {
    Map<String, dynamic> revertPayload = {};
    var entity = _haEntity;
    var revertAction = LightServiceActions.on;

    try {
      var currentState = await homeAssistant.fetchState(entity);
      revertPayload = {"rgb_color": currentState.attributes.rgbColor};
    } catch (e) {
      print("error reading ha state $e");
      revertAction = LightServiceActions.off;
    }

    Map<String, dynamic> blinkPayload = {
      "rgb_color": [blink.r255(), blink.g255(), blink.b255()],
    };

    await homeAssistant.executeService(entity, LightServiceActions.on.action, additionalActions: blinkPayload);
    sleep(Duration(milliseconds: blink.getDuration()));
    await homeAssistant.executeService(entity, LightServiceActions.off.action);

    sleep(Duration(milliseconds: blink.getDuration()));
    await homeAssistant.executeService(entity, revertAction.action, additionalActions: revertPayload);

    print("HA blink");
  }
}