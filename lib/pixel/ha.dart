import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_assistant/home_assistant.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late HomeAssistant _homeAssistant;

  // late String _haUrl;
  // late String _haToken;
  late String _haEntity;
  late bool _haEnabled;

  HomeAssistantController(SharedPreferences prefs) {
    // _haEnabled = bool.parse(dotenv.env['HA_ENABLED'] ?? "false");
    // _haUrl = dotenv.env['HA_URL'] ?? "";
    // _haToken = dotenv.env['HA_TOKEN'] ?? "";
    // _haEntity = dotenv.env['HA_ENTITY'] ?? "";
    _haEnabled = prefs.getBool("ha.enabled") ?? false;
    _haEntity = prefs.getString("ha.entity") ?? "";
    _homeAssistant = HomeAssistant(
      baseUrl: prefs.getString("ha.url") ?? "",
      bearerToken: prefs.getString("ha.token") ?? "",
    );
  }

  static Future<HomeAssistantController> makeController() async {
    final prefs = await SharedPreferences.getInstance();
    return HomeAssistantController(prefs);
  }

  void updateSettings({bool enabled = false, String? url, String? token, String? entity}) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null) {
      await prefs.setString("ha.url", url);
    }
    if (token != null) {
      await prefs.setString("ha.token", token);
    }
    if (entity != null) {
      await prefs.setString("ha.entity", entity);
      _haEntity = entity;
    }
    await prefs.setBool("ha.enabled", enabled);
    _haEnabled = enabled;
    _homeAssistant = HomeAssistant(
      baseUrl: prefs.getString("ha.url") ?? "",
      bearerToken: prefs.getString("ha.token") ?? "",
    );
    print("ha settings updated");
  }

  Future<HaSettings> getHaSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.getKeys().forEach((k) => print('$k ${prefs.get(k)}'));
    return HaSettings(_haEnabled, prefs.getString("ha.url") ?? "", prefs.getString("ha.token") ?? "", _haEntity);
  }

  Future<void> blinkEntity(String entity, Blinker blink) async {
    Map<String, dynamic> revertPayload = {};
    var revertAction = LightServiceActions.on;

    try {
      var currentState = await _homeAssistant.fetchState(entity);
      revertPayload = {
        "rgb_color": currentState.attributes.rgbColor,
        "brightness": currentState.attributes.brightness
      };
    } catch (e) {
      print("error reading ha state $e");
      revertAction = LightServiceActions.off;
    }

    Map<String, dynamic> blinkPayload = {
      "rgb_color": [blink.r255(), blink.g255(), blink.b255()],
      "brightness": blink.a255()
    };

    await _homeAssistant.executeService(entity, LightServiceActions.on.action, additionalActions: blinkPayload);
    sleep(Duration(milliseconds: blink.getDuration()));
    await _homeAssistant.executeService(entity, LightServiceActions.off.action);

    sleep(Duration(milliseconds: blink.getDuration()));
    await _homeAssistant.executeService(entity, revertAction.action, additionalActions: revertPayload);

    print("HA blink");
  }
}
