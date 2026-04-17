import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:roll_feathers/dice_sdks/message_sdk.dart';
import 'package:roll_feathers/services/home_assistant/ha_service.dart';

@visibleForTesting
class NoopHaService extends HaService {
  @override
  Future<void> blinkLightEntity(String entity, Blinker blink, {int times = 1}) async {}
  @override
  Future<void> init() async {}
  @override
  Future<void> setEntityColor(String entity, Color color) async {}
}
