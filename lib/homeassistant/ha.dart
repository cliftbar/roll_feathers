import 'dart:io';

import 'package:home_assistant/home_assistant.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roll_feathers/config.dart';

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

    _haEnabled = prefs.getBool(haEnabledKey) ?? false;

    _haEntity = prefs.getString(haEntityKey) ?? "";

    _homeAssistant = HomeAssistant(
      baseUrl: prefs.getString(kaUrlKey) ?? "",
      bearerToken: prefs.getString(haTokenKey) ?? "",
    );
  }

  static Future<HomeAssistantController> makeController() async {
    final prefs = await SharedPreferences.getInstance();
    return HomeAssistantController(prefs);
  }

  void updateSettings({bool enabled = false, String? url, String? token, String? entity}) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null) {
      await prefs.setString(kaUrlKey, url);
    }
    if (token != null) {
      await prefs.setString(haTokenKey, token);
    }
    if (entity != null) {
      await prefs.setString(haEntityKey, entity);
      _haEntity = entity;
    }
    await prefs.setBool(haEnabledKey, enabled);
    _haEnabled = enabled;
    _homeAssistant = HomeAssistant(
      baseUrl: prefs.getString(kaUrlKey) ?? "",
      bearerToken: prefs.getString(haTokenKey) ?? "",
    );
    print("ha settings updated");
  }

  Future<HaSettings> getHaSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.getKeys().forEach((k) => print('$k ${prefs.get(k)}'));
    return HaSettings(_haEnabled, prefs.getString(kaUrlKey) ?? "", prefs.getString(haTokenKey) ?? "", _haEntity);
  }

  Future<void> blinkEntity(String entity, Blinker blink) async {
    Map<String, dynamic> revertPayload = {};
    var revertAction = LightServiceActions.on;

    try {
      var currentState = await _homeAssistant.fetchState(entity);
      revertPayload = {"rgb_color": currentState.attributes.rgbColor, "brightness": currentState.attributes.brightness};
    } catch (e) {
      print("error reading ha state $e");
      revertAction = LightServiceActions.off;
    }

    Map<String, dynamic> blinkPayload = {
      "rgb_color": [blink.r255(), blink.g255(), blink.b255()],
      "brightness": blink.a255(),
    };

    await _homeAssistant.executeService(entity, LightServiceActions.on.action, additionalActions: blinkPayload);
    sleep(Duration(milliseconds: blink.getDuration()));
    await _homeAssistant.executeService(entity, LightServiceActions.off.action);

    sleep(Duration(milliseconds: blink.getDuration()));
    await _homeAssistant.executeService(entity, revertAction.action, additionalActions: revertPayload);

    print("HA blink");
  }
}
