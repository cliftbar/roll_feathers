import 'package:flutter/material.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/repositories/ble/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/app_service.dart';

class FakeDie extends GenericDie {
  @override
  final GenericDieType type = GenericDieType.virtual;

  @override
  Color? blinkColor;

  GenericDType _dType = GenericDTypeFactory.getKnownChecked('d6');

  final String id;
  final String _name;

  FakeDie(this.id, this._name, int value, {String dName = 'd6'}) {
    _dType = GenericDTypeFactory.getKnownChecked(dName);
    state = DiceState(currentFaceValue: value);
  }

  @override
  String get dieId => id;

  @override
  String get friendlyName => _name;

  @override
  set friendlyName(String n) {}

  @override
  GenericDType get dType => _dType;

  @override
  set dType(GenericDType df) {
    _dType = df;
  }
}

class FakeBleRepository extends BleRepository {
  @override
  Map<String, BleDeviceWrapper> get discoveredBleDevices => {};

  @override
  void dispose() {}

  @override
  Future<void> disconnectAllDevices() async {}

  @override
  Future<void> disconnectDevice(String deviceId) async {}

  @override
  Future<void> init() async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> scan({
    List<String>? services,
    List<String>? namePrefix,
    Duration? timeout = const Duration(seconds: 5),
  }) async {}

  @override
  Stream<bool> subscribeBleEnabled() => const Stream.empty();

  @override
  Stream<Map<String, BleDeviceWrapper>> subscribeBleDevices() => const Stream.empty();

  @override
  Future<void> stopScan() async {}
}

class FakeDieDomain extends DieDomain {
  final List<String> blinked = [];

  FakeDieDomain() : super(FakeBleRepository(), HaRepositoryEmpty());

  @override
  Future<void> blink(
    Color blinkColor,
    GenericDie die, {
    bool withHa = true,
    int blinkCount = 2,
    Duration blinkInterval = const Duration(milliseconds: 500),
  }) async {
    blinked.add('${(die as FakeDie).id}:${blinkColor.toARGB32()}');
  }
}

class FakeAppService extends AppService {
  List<String> _saved = [];
  bool _webhooksEnabled = true;

  @override
  Future<List<String>> getSavedScripts() async => _saved;

  @override
  Future<void> setSavedScripts(List<String> rules) async {
    _saved = rules;
  }

  @override
  Future<bool> getWebhooksEnabled() async => _webhooksEnabled;

  @override
  Future<void> setWebhooksEnabled(bool enabled) async {
    _webhooksEnabled = enabled;
  }
}
