import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:roll_feathers/domains/roll_parser/parser.dart';

import '../dice_sdks/godice.dart';
import '../dice_sdks/pixels.dart';
import '../domains/api_domain.dart';
import '../domains/die_domain.dart';
import '../domains/roll_domain.dart';
import '../repositories/app_repository.dart';
import '../repositories/ble/ble_repository.dart';
import '../repositories/ble/ble_universal_repository.dart';
import '../repositories/home_assistant_repository.dart';
import '../services/app_service.dart';
import '../services/home_assistant/ha_config_service.dart';
import '../services/home_assistant/ha_service.dart';

class DiWrapper {
  final HaService haService;
  final HaConfigService haConfigService;
  final AppService appService;

  final HaRepository haRepository;
  final AppRepository appRepository;

  final BleRepository bleRepository;
  final DieDomain dieDomain;
  final RollDomain rollDomain;
  final ApiDomain apiDomain;

  static Future<DiWrapper> initDi() async {
    late HaRepository haRepository;
    var haService = await HaService.create();
    var haConfigService = HaConfigService();
    if (kIsWeb) {
      haRepository = HaRepositoryEmpty();
    } else {
      var conf = await haConfigService.getConfig();
      haRepository = HaRepositoryImpl(haConfigService, haService, conf.enabled);
    }

    var appService = AppService();
    var appRepo = AppRepository(appService);

    BleRepository bleRepo;
    if (kIsWeb) {
      bleRepo = BleUniversalRepository();
      bleRepo.init();
    } else if (Platform.isWindows) {
      bleRepo = BleUniversalRepository();
      bleRepo.init().whenComplete(() => bleRepo.scan(services: [pixelsService, godiceServiceGuid]));
    } else {
      bleRepo = BleUniversalRepository();
      bleRepo.init().whenComplete(() => bleRepo.scan(services: [pixelsService, godiceServiceGuid]));
    }

    var dieDomain = DieDomain(bleRepo, haRepository);

    var rollDomain = await RollDomain.create(dieDomain);
    late ApiDomain apiDomain;
    if (kIsWeb) {
      apiDomain = EmptyApiDomain();
    } else {
      apiDomain = await ApiDomainServer.create(rollDomain: rollDomain);
    }

    var ruleParser = RuleParser(dieDomain, rollDomain);

    return DiWrapper._(
      haService,
      appService,
      haConfigService,
      haRepository,
      appRepo,
      dieDomain,
      bleRepo,
      rollDomain,
      apiDomain,
    );
  }

  DiWrapper._(
    this.haService,
    this.appService,
    this.haConfigService,
    this.haRepository,
    this.appRepository,
    this.dieDomain,
    this.bleRepository,
    this.rollDomain,
    this.apiDomain,
  );
}
