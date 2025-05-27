import 'package:roll_feathers/domains/api_domain.dart';
import 'package:roll_feathers/domains/pixel_die_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/pixel/pixel_constants.dart';
import 'package:roll_feathers/repositories/app_repository.dart';
import 'package:roll_feathers/repositories/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_service.dart';

class DiWrapper {
  final HaService haService;
  final HaConfigService haConfigService;
  final AppService appService;

  final HaRepository haRepository;
  final AppRepository appRepository;

  final BleRepository bleRepository;
  final PixelDieDomain rfController;
  final RollDomain rollDomain;
  final ApiDomain apiDomain;

  static Future<DiWrapper> initDi() async {
    var haService = await HaService.create();
    var haConfigService = HaConfigService();
    var haRepository = HaRepository(haConfigService, haService);

    var appService = AppService();
    var appRepo = AppRepository(appService);

    var bleRepo = BleRepository();
    await bleRepo.init(services: [pixelsService]);
    bleRepo.scan(services: [pixelsService]);

    var rfController = PixelDieDomain(bleRepo, haRepository);

    var rollDomain = await RollDomain.create(rfController);

    var apiDomain = await ApiDomain.create(rollDomain: rollDomain);

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
