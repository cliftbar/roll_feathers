import 'dart:async';

import 'package:logging/logging.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_service.dart';
import 'package:roll_feathers/util/strings.dart';

import '../dice_sdks/message_sdk.dart';

abstract class HaRepository {
  Stream<HaConfig> subscribeHaSettings();

  Future<HaConfig> getHaConfig();

  Future<void> updateSettings({bool enabled = false, String url = "", String token = "", String entity = ""});

  Future<void> blinkEntity({required Blinker blink, String? entity, bool force = false});

  bool get enabled;

  bool get available;
}

class HaRepositoryEmpty extends HaRepository {
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
  bool get enabled => false;

  @override
  bool get available => false;
}

class HaRepositoryImpl extends HaRepository {
  final _log = Logger("HaRepository");
  final HaConfigService _haConfigService;
  final HaService _haService;
  late bool isEnabled;

  final _settingsStream = StreamController<HaConfig>.broadcast();

  HaRepositoryImpl(this._haConfigService, this._haService, this.isEnabled);

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
    isEnabled = conf.enabled;
    if (enabled || force) {
      await _haService.blinkEntity(presentOrElse(entity, conf.entity), blink);
    }
  }

  @override
  bool get enabled => isEnabled;

  @override
  bool get available => true;
}
