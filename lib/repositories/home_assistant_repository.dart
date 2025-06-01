import 'dart:async';

import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_service.dart';
import 'package:roll_feathers/util/strings.dart';

abstract class HaRepository {
  Stream<HaConfig> subscribeHaSettings();

  Future<HaConfig> getHaConfig();

  Future<void> updateSettings({bool enabled = false, String url = "", String token = "", String entity = ""});

  Future<void> blinkEntity({required Blinker blink, String? entity, bool force = false});

  bool get enabled;
}

class HaRepositoryEmpty extends HaRepository {
  final bool _enabled = true;
  @override
  Stream<HaConfig> subscribeHaSettings() => Stream.empty();
  @override
  Future<HaConfig> getHaConfig() async {
    return HaConfig(enabled: false, url: "", token: "", entity: "");
  }

  @override
  Future<void> updateSettings({bool enabled = false, String url = "", String token = "", String entity = ""}) async {}
  @override
  Future<void> blinkEntity({required Blinker blink, String? entity, bool force = false}) async {}

  @override
  // TODO: implement enabled
  bool get enabled => _enabled;
}

class HaRepositoryImpl extends HaRepository {
  final _log = Logger("HaRepository");
  final HaConfigService _haConfigService;
  final HaService _haService;
  final bool _enabled = true;

  final _settingsStream = StreamController<HaConfig>.broadcast();

  HaRepositoryImpl(this._haConfigService, this._haService);

  @override
  Stream<HaConfig> subscribeHaSettings() => _settingsStream.stream;

  @override
  Future<HaConfig> getHaConfig() async {
    return _haConfigService.getConfig();
  }

  @override
  Future<void> updateSettings({bool enabled = false, String url = "", String token = "", String entity = ""}) async {
    var conf = HaConfig(enabled: enabled, url: url, token: token, entity: entity);
    await _haConfigService.setConfig(conf);
    await _haService.init();
    var newConf = await _haConfigService.getConfig();
    _settingsStream.add(newConf);
    _log.info("ha settings updated");
  }

  @override
  Future<void> blinkEntity({required Blinker blink, String? entity, bool force = false}) async {
    var conf = await _haConfigService.getConfig();
    bool enabled = conf.enabled;
    if (enabled || force) {
      await _haService.blinkEntity(presentOrElse(entity, conf.entity), blink);
    }
  }

  @override
  // TODO: implement enabled
  bool get enabled => _enabled;
}
