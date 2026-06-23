import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:roll_feathers/services/home_assistant/ha_api_service.dart';

import 'package:roll_feathers/dice_sdks/godice.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart';
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels_patterns.dart';
import 'package:roll_feathers/domains/api_domain.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/domains/dddice_domain.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/repositories/app_repository.dart';
import 'package:roll_feathers/repositories/dddice_repository.dart';
import 'package:roll_feathers/services/dddice/dddice_config_service.dart';
import 'package:roll_feathers/repositories/ble/ble_noop_repository.dart';
import 'package:roll_feathers/repositories/ble/ble_repository.dart';
import 'package:roll_feathers/repositories/ble/ble_universal_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_noop_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_service.dart';
import 'package:roll_feathers/di/http/http_client_provider.dart'
    if (dart.library.js_interop) 'package:roll_feathers/di/http/web_http_client_provider.dart'
    as http_factory;

class DiWrapper {
  final HaService haService;
  final HaConfigService haConfigService;
  final AppService appService;

  final HaRepository haRepository;
  final AppRepository appRepository;

  final BleRepository bleRepository;
  final DieDomain dieDomain;
  final String appVersion;
  final RuleEvaluator ruleParser;
  final WebhookDomain webhookDomain;
  final RollDomain rollDomain;
  final ApiDomain apiDomain;
  final DddiceDomain dddiceDomain;

  static Future<DiWrapper> initDi() async {
    registerBuiltinPatterns(kBuiltinPatterns);
    late HaRepository haRepository;
    late HaService haService;
    HaConfigService haConfigService = HaConfigService();
    Client httpClient = http_factory.provideHttpClient();
    haService = await HaApiService.create(httpClient);
    if (kIsWeb) {
      HaConfig conf = await haConfigService.getConfig();
      haRepository = HaRepositoryImpl(haConfigService, haService, conf.enabled);
    } else {
      HaConfig conf = await haConfigService.getConfig();
      haRepository = HaRepositoryImpl(haConfigService, haService, conf.enabled);
    }

    String appVersion = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.buildNumber.isNotEmpty ? '${info.version}+${info.buildNumber}' : info.version;
    } catch (e) {
      debugPrint('PackageInfo.fromPlatform() failed: $e');
    }

    AppService appService = AppService();
    AppRepository appRepo = AppRepository(appService);

    const bool integrationTest = bool.fromEnvironment('INTEGRATION_TEST');
    BleRepository bleRepo = integrationTest ? NoopBleRepository() : BleUniversalRepository();
    await bleRepo.init();
    if (!kIsWeb && !integrationTest) {
      // Windows: no service filter — improves discovery reliability on WinRT
      final services = Platform.isWindows ? const <String>[] : [pixelsService, godiceServiceGuid];
      bleRepo.scan(services: services, namePrefix: ['GoDice_']);
    }

    DieDomain dieDomain = DieDomain(bleRepo, haRepository, appService);

    WebhookDomain webhookDomain =
        WebhookDomain(httpClient: httpClient, appVersion: appVersion, appService: appService);

    // Lets integration tests redirect dddice traffic to a local mock server
    // (see lib/testing/dddice_mock_server.dart) via
    // --dart-define=DDDICE_BASE_URL=http://127.0.0.1:<port>/api/1.0
    const String dddiceBaseUrlOverride = String.fromEnvironment('DDDICE_BASE_URL');
    DddiceConfigService dddiceConfigService = DddiceConfigService();
    DddiceRepository dddiceRepository = DddiceRepository(httpClient,
        baseUrl: dddiceBaseUrlOverride.isEmpty ? null : dddiceBaseUrlOverride);
    DddiceDomain dddiceDomain = DddiceDomain(dddiceRepository, dddiceConfigService);

    RuleEvaluator ruleParser = RuleEvaluator(dieDomain, appService, webhookDomain);
    await ruleParser.init();

    RollDomain rollDomain = await RollDomain.create(dieDomain, appService,
        ruleParser: ruleParser, observers: [dddiceDomain]);
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
      dieDomain,
      bleRepo,
      appVersion,
      ruleParser,
      webhookDomain,
      rollDomain,
      apiDomain,
      dddiceDomain,
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
    this.appVersion,
    this.ruleParser,
    this.webhookDomain,
    this.rollDomain,
    this.apiDomain,
    this.dddiceDomain,
  );

  @visibleForTesting
  static Future<DiWrapper> forTesting({
    required AppService appService,
    required DieDomain dieDomain,
    required RuleEvaluator ruleParser,
    required WebhookDomain webhookDomain,
    BleRepository? bleRepository,
    DddiceConfigService? dddiceConfigService,
    DddiceRepository? dddiceRepository,
  }) async {
    final ble = bleRepository ?? NoopBleRepository();
    final ha = HaRepositoryEmpty();
    final dddiceCs = dddiceConfigService ?? DddiceConfigService();
    final dddiceRepo = dddiceRepository ?? DddiceRepository(http_factory.provideHttpClient());
    final rollDomain = await RollDomain.create(dieDomain, appService,
        ruleParser: ruleParser);
    return DiWrapper._(
      NoopHaService(),
      appService,
      HaConfigService(),
      ha,
      AppRepository(appService),
      dieDomain,
      ble,
      'test',
      ruleParser,
      webhookDomain,
      rollDomain,
      EmptyApiDomain(),
      DddiceDomain(dddiceRepo, dddiceCs),
    );
  }
}
