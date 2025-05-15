import 'dart:io';

import 'package:home_assistant/home_assistant.dart';
import 'package:roll_feathers/pixel/pixelMessages.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HomeAssistantController {
  // var token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI0ODVmOTY2NzgwMGQ0MjdlOTMyYWIwYWZlNjQyN2Y0NiIsImlhdCI6MTc0NTcwNTQ0MSwiZXhwIjoyMDYxMDY1NDQxfQ.nn4v9DDktRgM4AO8ew80TcWBRpPgszvjJnjslKz7w-0";
  // var url = "https://ha.cliftbar.site";
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