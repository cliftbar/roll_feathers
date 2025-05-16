import 'dart:io';

import 'package:home_assistant/home_assistant.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HomeAssistantController {
  late final HomeAssistant homeAssistant;

  HomeAssistantController() {
    var url = dotenv.env['HA_URL'];
    var token = dotenv.env['HA_TOKEN'];
    homeAssistant = HomeAssistant(baseUrl: url!, bearerToken: token!);
  }

  Future<void> blinkEntity(Blinker blink) async {
    await homeAssistant.executeService("light.blamp", "turn_off");

    sleep(Duration(milliseconds: blink.getDuration()));
    await homeAssistant.executeService("light.blamp", "turn_on");

    print("HA blink");
  }
}
