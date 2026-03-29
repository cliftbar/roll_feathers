import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:roll_feathers/domains/roll_parser/parser.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/repositories/ble/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/domains/roll_domain.dart';

/// Simple fake die that lets us control id, type, and face value.
class TestDie extends GenericDie {
  @override
  final Logger _log = Logger('TestDie');

  @override
  final GenericDieType type = GenericDieType.virtual;

  @override
  Color? blinkColor;

  GenericDType _dType = GenericDTypeFactory.getKnownChecked('d6');

  final String id;
  final String name;

  TestDie(this.id, this.name, int value, {String dName = 'd6'}) {
    _dType = GenericDTypeFactory.getKnownChecked(dName);
    state = DiceState(currentFaceValue: value);
  }

  @override
  Future<void> _init() async {}

  @override
  String get dieId => id;

  @override
  String get friendlyName => name;

  @override
  GenericDType get dType => _dType;

  @override
  set dType(GenericDType df) {
    _dType = df;
  }
}

class TestBleRepository extends BleRepository {
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
  Future<void> scan({List<String>? services, Duration? timeout = const Duration(seconds: 5)}) async {}

  @override
  Stream<bool> subscribeBleEnabled() => const Stream.empty();

  @override
  Stream<Map<String, BleDeviceWrapper>> subscribeBleDevices() => const Stream.empty();

  @override
  Future<void> stopScan() async {}
}

/// Fake DieDomain that records blink actions for later inspection.
class RecordingDieDomain extends DieDomain {
  final List<String> blinked = [];
  RecordingDieDomain() : super(TestBleRepository(), HaRepositoryEmpty());
  @override
  Future<void> blink(
      Color blinkColor,
      GenericDie die, {
        bool withHa = true,
        int blinkCount = 2,
        Duration blinkInterval = const Duration(milliseconds: 500),
      }) async {
    blinked.add('${(die as TestDie).id}:${blinkColor.toARGB32()}');
  }
}

/// Minimal AppService that stores rules in-memory for harness use.
class InMemoryAppService extends AppService {
  List<String> _saved = [];
  @override
  Future<List<String>> getSavedScripts() async => _saved;
  @override
  Future<void> setSavedScripts(List<String> rules) async {
    _saved = rules;
  }
}

/// Input spec for one die (type and face value).
class DieInput {
  final String dType; // e.g., 'd6'
  final int faceValue;
  final String? id; // optional custom id for reporting
  DieInput(this.dType, this.faceValue, {this.id});
}

/// Output log for a single action taken on a specific die.
class ActionLogEntry {
  final String dieId;
  final String action; // e.g., 'blink' or 'sequence'
  final int? colorValue; // ARGB int if applicable
  final List<String> args; // remaining args after special tokens removed
  ActionLogEntry({required this.dieId, required this.action, this.colorValue, this.args = const []});
}

/// Result of running the DSL test harness once.
class DslTestResult {
  final List<ActionLogEntry> actions;
  final ParseResult parse;
  DslTestResult({required this.actions, required this.parse});
}

/// A simple runner that executes a rule against a provided set of dice and
/// records actions per die.
class DslTestRunner {
  final RecordingDieDomain dieDomain;
  final RollDomain rollDomain;
  final InMemoryAppService appService;
  final RuleParser parser;

  DslTestRunner._(this.dieDomain, this.rollDomain, this.appService, this.parser);

  static Future<DslTestRunner> create() async {
    final dd = RecordingDieDomain();
    final app = InMemoryAppService();
    final rd = await RollDomain.create(dd, app);
    final rp = RuleParser(dd, rd, app);
    await rp.init();
    return DslTestRunner._(dd, rd, app, rp);
  }

  /// Convert DieInput specs into TestDie instances.
  List<TestDie> _makeDice(List<DieInput> dice) {
    final result = <TestDie>[];
    for (var i = 0; i < dice.length; i++) {
      final d = dice[i];
      final id = d.id ?? 'D$i';
      result.add(TestDie(id, id, d.faceValue, dName: d.dType));
    }
    return List.unmodifiable(result);
  }

  /// Run a rule and return the actions observed.
  Future<DslTestResult> run({
    required String rule,
    required List<DieInput> dice,
    int threshold = 0,
    int modifier = 0,
  }) async {
    dieDomain.blinked.clear();
    final testDice = _makeDice(dice);
    final result = await parser.runRuleAsync(rule, testDice, threshold: threshold, modifier: modifier);

    // Map blink events to ActionLogEntries. We infer 'blink' action; 'sequence' results in blink calls too.
    final actions = <ActionLogEntry>[];
    for (final entry in dieDomain.blinked) {
      // entry is '<dieId>:<colorValue>'
      final parts = entry.split(':');
      final dieId = parts[0];
      final color = int.tryParse(parts[1]);
      actions.add(ActionLogEntry(dieId: dieId, action: 'blink', colorValue: color, args: const []));
    }

    return DslTestResult(actions: actions, parse: result);
  }
}
