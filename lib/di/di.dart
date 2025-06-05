import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:roll_feathers/dice_sdks/godice.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart';
import 'package:roll_feathers/domains/api_domain.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/repositories/app_repository.dart';
import 'package:roll_feathers/repositories/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_service.dart';

import 'package:roll_feathers/repositories/ble_windows_repository.dart';

class DiWrapper {
  final HaService haService;
  final HaConfigService haConfigService;
  final AppService appService;

  final HaRepository haRepository;
  final AppRepository appRepository;

  final BleRepository bleRepository;
  final DieDomain rfController;
  final RollDomain rollDomain;
  final ApiDomain apiDomain;

  static Future<DiWrapper> initDi() async {
    late HaRepository haRepository;
    var haService = await HaService.create();
    var haConfigService = HaConfigService();
    if (kIsWeb) {
      haRepository = HaRepositoryEmpty();
    } else {
      haRepository = HaRepositoryImpl(haConfigService, haService);
    }

    var appService = AppService();
    var appRepo = AppRepository(appService);

    BleRepository bleRepo;
    if (Platform.isWindows) {
      bleRepo = BleWindowsRepository();
    } else {
      bleRepo = BleCrossRepository();
    }

    // Run ble init and scan in background
    bleRepo.init().whenComplete(() => bleRepo.scan(services: [pixelsService, godiceServiceGuid]));

    var rfController = DieDomain(bleRepo, haRepository);

    var rollDomain = await RollDomain.create(rfController);
    late ApiDomain apiDomain;
    if (kIsWeb) {
      apiDomain = EmptyApiDomain();
    } else {
      apiDomain = await ApiDomainServer.create(rollDomain: rollDomain);
    }

    return DiWrapper._(
      haService,
      appService,
      haConfigService,
      haRepository,
      appRepo,
      rfController,
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
    this.rfController,
    this.bleRepository,
    this.rollDomain,
    this.apiDomain,
  );
}
