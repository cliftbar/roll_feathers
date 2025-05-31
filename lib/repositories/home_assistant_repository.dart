import 'dart:async';

import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_service.dart';
import 'package:roll_feathers/util/strings.dart';

import 'package:roll_feathers/dice_sdks/generic_die.dart';

class HaRepository {
  final HaConfigService _haConfigService;
  final HaService _haService;

  final _settingsStream = StreamController<HaConfig>.broadcast();

  HaRepository(this._haConfigService, this._haService);

  Stream<HaConfig> subscribeHaSettings() => _settingsStream.stream;

  Future<HaConfig> getHaConfig() async {
    return _haConfigService.getConfig();
  }

  Future<void> updateSettings({bool enabled = false, String url = "", String token = "", String entity = ""}) async {
    var conf = HaConfig(enabled: enabled, url: url, token: token, entity: entity);
    await _haConfigService.setConfig(conf);
    await _haService.init();
    var newConf = await _haConfigService.getConfig();
    _settingsStream.add(newConf);
    print("ha settings updated");
  }

  Future<void> blinkEntity({required Blinker blink, String? entity, bool force = false}) async {
    var conf = await _haConfigService.getConfig();
    bool enabled = conf.enabled;
    if (enabled || force) {
      await _haService.blinkEntity(presentOrElse(entity, conf.entity), blink);
    }
  }
}
