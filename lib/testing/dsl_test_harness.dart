import 'dart:async';

import 'package:flutter/material.dart';

import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/repositories/ble/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/testing/rule_evaluation_test_effects.dart';

/// Fake BLE-type die (type=pixel) for use in RollDomain tests where the
/// virtual-die filter must be bypassed.  Has no real BLE; roll state is
/// fired manually via [fireRollState].
class TestBleDie extends GenericDie {
  @override
  final GenericDieType type = GenericDieType.pixel;

  final String id;
  Color? _blinkColor;

  TestBleDie(this.id);

  /// Simulate the die entering [rs] and invoke registered callbacks.
  void fireRollState(DiceRollState rs) {
    state.rollState = rs.index;
    if (rollCallbacks.containsKey(rs)) {
      for (final fn in List.of(rollCallbacks[rs]!.values)) {
        fn(rs);
      }
    }
  }

  Future<void> _init() async {}

  @override
  String get dieId => id;

  @override
  String get friendlyName => id;

  @override
  set friendlyName(String name) {}

  @override
  GenericDType get dType => GenericDTypeFactory.getKnownChecked('d20');

  @override
  set dType(GenericDType df) {}

  @override
  Color? get blinkColor => _blinkColor;

  @override
  set blinkColor(Color? c) => _blinkColor = c;
}

/// Fake GoDice-type die for UI tests that check GoDice-specific sections.
class TestGoDiceDie extends GenericDie {
  @override
  final GenericDieType type = GenericDieType.godice;

  final String id;
  Color? _blinkColor;

  TestGoDiceDie(this.id);

  Future<void> _init() async {}

  @override
  String get dieId => id;

  @override
  String get friendlyName => id;

  @override
  set friendlyName(String name) {}

  @override
  GenericDType get dType => GenericDTypeFactory.getKnownChecked('d6');

  @override
  set dType(GenericDType df) {}

  @override
  Color? get blinkColor => _blinkColor;

  @override
  set blinkColor(Color? c) => _blinkColor = c;
}

/// Simple fake die that lets us control id, type, and face value.
class TestDie extends GenericDie {
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

  Future<void> _init() async {}

  @override
  String get dieId => id;

  @override
  String get friendlyName => name;

  @override
  set friendlyName(String name) {}

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
  Future<void> scan({List<String>? services, List<String>? namePrefix, Duration? timeout = const Duration(seconds: 5)}) async {}

  @override
  Stream<bool> subscribeBleEnabled() => const Stream.empty();

  @override
  Stream<Map<String, BleDeviceWrapper>> subscribeBleDevices() => const Stream.empty();

  @override
  Future<void> stopScan() async {}
}

/// Fake DieDomain that records blink, blinkRolling, and stopAnimations calls.
class RecordingDieDomain extends DieDomain {
  final List<String> blinked = [];
  final List<String> rollingBlinked = [];
  final List<String> animationsStopped = [];

  final _testDiceStream =
      StreamController<Map<String, GenericDie>>.broadcast();

  RecordingDieDomain() : super(TestBleRepository(), HaRepositoryEmpty());

  /// Push a dice map into the stream so RollDomain registers callbacks.
  void emitDice(Map<String, GenericDie> dice) => _testDiceStream.add(dice);

  @override
  Stream<Map<String, GenericDie>> getDiceStream() => _testDiceStream.stream;

  @override
  Future<void> blink(
      Color blinkColor,
      GenericDie die, {
        bool withHa = true,
        int blinkCount = 2,
        Duration blinkInterval = const Duration(milliseconds: 500),
      }) async {
    blinked.add('${die.dieId}:${blinkColor.toARGB32()}');
  }

  @override
  Future<void> blinkRolling(GenericDie die) async =>
      rollingBlinked.add(die.dieId);

  @override
  Future<void> stopAnimations(GenericDie die) async =>
      animationsStopped.add(die.dieId);
}

/// Minimal AppService that stores rules and die settings in-memory.
/// Overrides ALL methods that would otherwise hit SharedPreferences.
class InMemoryAppService extends AppService {
  List<String> _saved = [];
  List<String> _ruleOrder = [];
  List<String> _hiddenRuleNames = [];
  bool _webhooksEnabled = true;
  bool _keepScreenOn = false;
  bool _useAsyncEvaluator = false;
  ThemeMode _themeMode = ThemeMode.system;
  DicePaneOrientation _dicePaneOrientation = DicePaneOrientation.auto;
  final Map<String, DieSettings> _dieSettings = {};

  @override
  Future<List<String>> getSavedScripts() async => _saved;

  @override
  Future<void> setSavedScripts(List<String> rules) async {
    _saved = rules;
  }

  @override
  Future<List<String>> getRuleOrder() async => List.from(_ruleOrder);

  @override
  Future<void> setRuleOrder(List<String> order) async {
    _ruleOrder = List.from(order);
  }

  @override
  Future<List<String>> getHiddenRuleNames() async => List.from(_hiddenRuleNames);

  @override
  Future<void> setHiddenRuleNames(List<String> names) async {
    _hiddenRuleNames = List.from(names);
  }

  @override
  Future<bool> getWebhooksEnabled() async => _webhooksEnabled;

  @override
  Future<void> setWebhooksEnabled(bool enabled) async {
    _webhooksEnabled = enabled;
  }

  @override
  Future<bool> getKeepScreenOn() async => _keepScreenOn;

  @override
  Future<void> setKeepScreenOn(bool keepScreenOn) async {
    _keepScreenOn = keepScreenOn;
  }

  @override
  Future<bool> getUseAsyncEvaluator() async => _useAsyncEvaluator;

  @override
  Future<void> setUseAsyncEvaluator(bool useAsync) async {
    _useAsyncEvaluator = useAsync;
  }

  @override
  Future<ThemeMode> getThemeMode() async => _themeMode;

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
  }

  @override
  Future<DicePaneOrientation> getDicePaneOrientation() async => _dicePaneOrientation;

  @override
  Future<void> setDicePaneOrientation(DicePaneOrientation orientation) async {
    _dicePaneOrientation = orientation;
  }

  @override
  Future<DieSettings?> getDieSettings(String dieId) async =>
      _dieSettings[dieId];

  @override
  Future<void> saveDieSettings(String dieId, DieSettings settings) async {
    _dieSettings[dieId] = settings;
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
  final RuleEvaluator parser;

  DslTestRunner._(this.dieDomain, this.rollDomain, this.appService, this.parser);

  static Future<DslTestRunner> create() async {
    final dd = RecordingDieDomain();
    final app = InMemoryAppService();
    final wd = WebhookDomain(appService: app);
    final rp = RuleEvaluator(dd, app, wd);
    await rp.init();
    final rd = await RollDomain.create(dd, app, ruleParser: rp);
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
    final result = parser.evaluateRule(rule, testDice, threshold: threshold, modifier: modifier);
    await result.runEffects();

    // Map blink events to ActionLogEntries. We infer 'blink' action; 'sequence' results in blink calls too.
    final actions = <ActionLogEntry>[];
    for (final entry in dieDomain.blinked) {
      // entry is '<dieId>:<colorValue>'
      final parts = entry.split(':');
      final dieId = parts[0];
      final color = int.tryParse(parts[1]);
      actions.add(ActionLogEntry(dieId: dieId, action: 'blink', colorValue: color, args: const []));
    }

    return DslTestResult(actions: actions, parse: result.result);
  }
}
