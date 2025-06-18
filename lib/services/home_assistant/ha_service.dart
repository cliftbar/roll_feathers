import 'dart:ui';

import '../../dice_sdks/message_sdk.dart';

enum HaDomainService {
  lightOn(domain: "light", service: "turn_on"),
  lightOff(domain: "light", service: "turn_off");

  const HaDomainService({required this.domain, required this.service});

  final String domain;
  final String service;
}

abstract class HaService {
  Future<void> blinkLightEntity(String entity, Blinker blink, {int times = 1});

  Future<void> init();

  Future<void> setEntityColor(String entity, Color color);
}
