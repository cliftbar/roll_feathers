import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:roll_feathers/domains/roll_parser/parser.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/repositories/ble/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/util/color.dart';

// Simple fakes to observe actions without real hardware
class FakeDie extends GenericDie {
  @override
  final Logger _log = Logger('FakeDie');

  @override
  final GenericDieType type = GenericDieType.virtual;

  @override
  Color? blinkColor;

  GenericDType _dType = GenericDTypeFactory.getKnownChecked('d6');

  final String id;
  final String name;

  FakeDie(this.id, this.name, int value, {String dName = 'd6'}) {
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
  Future<void> scan({List<String>? services, Duration? timeout = const Duration(seconds: 5)}) async {}

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
  @override
  Future<List<String>> getSavedScripts() async => _saved;
  @override
  Future<void> setSavedScripts(List<String> rules) async {
    _saved = rules;
  }
}

void main() {
  group('DSL v1.1 evaluation basics', () {
    late FakeDieDomain dd;
    late AppService app;
    late RuleParser parser;

    setUp(() async {
      dd = FakeDieDomain();
      app = FakeAppService();
      final rd = await RollDomain.create(dd, app);
      parser = rd.ruleParser;
    });

    test('highest/lowest selections act on intended dice', () async {
      // Rule: extremes (from fixtures spec but inlined here for direct use)
      const script =
          'define extremes for roll *d* make selection @HIGHEST with top 1 make selection @LOWEST with bottom 1 '
          'use selection @HIGHEST aggregate over selection max on result [*:*] action blink green '
          'use selection @LOWEST aggregate over selection min on result [*:*] action blink red';

      final d1 = FakeDie('A', 'A', 2, dName: 'd6');
      final d2 = FakeDie('B', 'B', 5, dName: 'd6');
      final d3 = FakeDie('C', 'C', 4, dName: 'd6');
      final rolls = [d1, d2, d3];

      final res = await parser.runRuleAsync(script, rolls);
      expect(res.ruleName, equals('extremes'));
      // Expect two blinks: highest (B) green and lowest (A) red
      // We can't assert colors easily without importing color map; just assert die ids present
      final actedIds = dd.blinked.map((s) => s.split(':').first).toList();
      expect(actedIds, containsAll(<String>['A', 'B']));
      expect(actedIds.length, equals(2));
    });
  });

  group('DSL v1.1 dupes transform', () {
    late FakeDieDomain dd;
    late AppService app;
    late RuleParser parser;

    setUp(() async {
      dd = FakeDieDomain();
      app = FakeAppService();
      final rd = await RollDomain.create(dd, app);
      parser = rd.ruleParser;
    });

    test('dupes [2:*] selects all dice that are part of pairs/triples/quads', () async {
      final d1 = FakeDie('a', 'A', 5);
      final d2 = FakeDie('b', 'B', 5);
      final d3 = FakeDie('c', 'C', 2);
      final d4 = FakeDie('d', 'D', 2);
      final d5 = FakeDie('e', 'E', 2);

      final script = '''
define pairsPlus for roll *d*

  make selection @DUPE
    with match [*:*]
    with dupes [2:*]

  use selection @DUPE
    aggregate over selection count
    on result [5:5] action blink green
''';

      final parsed = RuleParser.v11ScriptParser.parse(script);
      expect(parsed.isSuccess, isTrue);

      final res = await parser.runRuleAsync(script, [d1, d2, d3, d4, d5]);
      // Two 5s + three 2s => 5 dice selected, expect one blink per selection count target
      // We check that at least one blink occurred (exact color value from util map)
      expect(dd.blinked.isNotEmpty, isTrue);
    });

    test('dupes exact [2:2] selects pairs but excludes triples', () async {
      dd.blinked.clear();
      final d1 = FakeDie('a', 'A', 5);
      final d2 = FakeDie('b', 'B', 5);
      final d3 = FakeDie('c', 'C', 2);
      final d4 = FakeDie('d', 'D', 2);
      final d5 = FakeDie('e', 'E', 2);

      final script = '''
define pairsOnly for roll *d*

  make selection @PAIRS
    with dupes [2:2]

  use selection @PAIRS
    aggregate over selection count
    on result [2:2] action blink blue
''';

      final parsed = RuleParser.v11ScriptParser.parse(script);
      expect(parsed.isSuccess, isTrue);

      final res = await parser.runRuleAsync(script, [d1, d2, d3, d4, d5]);
      // Only the two 5s should be selected (not the triple 2s). Count == 2 triggers the action
      expect(dd.blinked.isNotEmpty, isTrue);
    });
  });

  group('DSL v1.1 evaluation extended scenarios', () {
    late FakeDieDomain dd;
    late AppService app;
    late RuleParser parser;

    setUp(() async {
      dd = FakeDieDomain();
      app = FakeAppService();
      final rd = await RollDomain.create(dd, app);
      parser = rd.ruleParser;
    });

    test('interval match and aggregate min/max/avg gating', () async {
      const script =
          'define bands for roll *d* '
          'make selection @LOW with match [*:3] '
          'make selection @MID with match [4:5] '
          'make selection @HIGH with match [6:*] '
          'use selection @LOW aggregate over selection min on result [*:*] action blink red '
          'use selection @MID aggregate over selection avg on result [*:*] action blink orange '
          'use selection @HIGH aggregate over selection max on result [*:*] action blink green';

      final a = FakeDie('A', 'A', 2, dName: 'd6');
      final b = FakeDie('B', 'B', 4, dName: 'd6');
      final c = FakeDie('C', 'C', 6, dName: 'd6');
      final rolls = [a, b, c];
      await parser.runRuleAsync(script, rolls);

      final ids = dd.blinked.map((s) => s.split(':').first).toSet();
      expect(ids, containsAll(<String>['A', 'B', 'C']));
    });

    test('use \$ALL_DICE convenience selection', () async {
      final script =
          'define allice for roll *d* '
          'use selection \$ALL_DICE aggregate over selection sum on result [*:*] action blink blue';
      final a = FakeDie('A', 'A', 1, dName: 'd6');
      final b = FakeDie('B', 'B', 2, dName: 'd6');
      await parser.runRuleAsync(script, [a, b]);
      final ids = dd.blinked.map((s) => s.split(':').first).toList();
      expect(ids, containsAll(<String>['A', 'B']));
    });

    test('derived selection chains from @PARENT', () async {
      const script =
          'define derived for roll *d* '
          'make selection @BASE with match [*:20] '
          'make selection @MID from @BASE with over 3 '
          'make selection @TOP from @MID with top 1 '
          'use selection @TOP aggregate over selection sum on result [*:*] action blink purple';
      final a = FakeDie('A', 'A', 2, dName: 'd20');
      final b = FakeDie('B', 'B', 19, dName: 'd20');
      final c = FakeDie('C', 'C', 7, dName: 'd20');
      await parser.runRuleAsync(script, [a, b, c]);
      final ids = dd.blinked.map((s) => s.split(':').first).toList();
      expect(ids, equals(['B']));
    });

    test('multiple use-blocks sharing one selection apply both actions based on ranges', () async {
      const script =
          'define shared for roll *d* '
          'make selection @PASS with match [10:*] '
          'use selection @PASS aggregate over selection sum on result [10:14] action blink green '
          'use selection @PASS aggregate over selection sum on result [15:*] action sequence red blue';
      final a = FakeDie('A', 'A', 12, dName: 'd20');
      final b = FakeDie('B', 'B', 18, dName: 'd20');

      // First, value 12 triggers first block only
      dd.blinked.clear();
      await parser.runRuleAsync(script, [a]);
      expect(dd.blinked.map((s) => s.split(':').first).toList(), equals(['A']));

      // Second, value 18 triggers second block only
      dd.blinked.clear();
      await parser.runRuleAsync(script, [b]);
      final ids2 = dd.blinked.map((s) => s.split(':').first).toList();
      // Sequence emits multiple blink events; assert that only die 'B' was acted on
      expect(ids2.toSet().toList(), equals(['B']));
    });

    test('args immutability across blocks (no mutation between blocks)', () async {
      // Two use-blocks with identical args; ensure both execute and counts match (args not mutated away).
      const script =
          'define immut for roll *d* '
          'make selection @ALL with match [*:*] '
          'use selection @ALL aggregate over selection sum on result [*:*] action blink red '
          'use selection @ALL aggregate over selection sum on result [*:*] action blink red';
      final a = FakeDie('A', 'A', 3, dName: 'd6');
      dd.blinked.clear();
      await parser.runRuleAsync(script, [a]);
      // two blocks × one blink each = 2
      expect(dd.blinked.length, equals(2));
    });

    test('in-block action invocation order is preserved', () async {
      // Same block, two on-result targets with the same always-true range; expect red then blue.
      const script =
          'define order for roll *d* '
          'make selection @ONE with match [*:*] '
          'use selection @ONE aggregate over selection sum '
          'on result [*:*] action blink red '
          'on result [*:*] action blink blue';

      final a = FakeDie('X', 'X', 5, dName: 'd6');
      dd.blinked.clear();
      await parser.runRuleAsync(script, [a]);

      // Expect exactly two blinks in order: red then blue
      expect(dd.blinked.length, equals(2));
      final firstColorVal = int.parse(dd.blinked[0].split(':')[1]);
      final secondColorVal = int.parse(dd.blinked[1].split(':')[1]);
      expect(firstColorVal, equals(colorMap['red']!.value));
      expect(secondColorVal, equals(colorMap['blue']!.value));
    });

    test('cross-block independence: different aggregates do not affect each other', () async {
      // Two use-blocks reference the same selection but use different aggregates.
      // Both blocks should evaluate against the original selection without influencing each other.
      const script =
          'define cross for roll *d* '
          'make selection @S with match [*:*] '
          'use selection @S aggregate over selection max on result [4:*] action blink green '
          'use selection @S aggregate over selection min on result [*:3] action blink red';

      final a = FakeDie('A', 'A', 3, dName: 'd6');
      final b = FakeDie('B', 'B', 4, dName: 'd6');
      dd.blinked.clear();
      await parser.runRuleAsync(script, [a, b]);

      // Both blocks should trigger: first due to max >= 4, second due to min <= 3
      // Each block blinks all dice in the selection, so expect 4 total blinks
      expect(dd.blinked.length, equals(4));
      final ids = dd.blinked.map((s) => s.split(':').first).toList();
      expect(ids.where((id) => id == 'A').length, equals(2));
      expect(ids.where((id) => id == 'B').length, equals(2));
    });

    test('shared selection reuse with multi-step pipeline across multiple blocks', () async {
      // One selection with a multi-step transform reused across three use-blocks.
      // We assert all blocks see the same selected dice and all actions fire.
      const script =
          'define reuse for roll *d* '
          'make selection @TOP2 with top 2 '
          'use selection @TOP2 aggregate over selection sum on result [*:*] action blink purple '
          'use selection @TOP2 aggregate over selection max on result [*:*] action blink blue '
          'use selection @TOP2 aggregate over selection min on result [*:*] action blink orange';

      final a = FakeDie('A', 'A', 2, dName: 'd6');
      final b = FakeDie('B', 'B', 5, dName: 'd6');
      final c = FakeDie('C', 'C', 4, dName: 'd6');
      dd.blinked.clear();
      await parser.runRuleAsync(script, [a, b, c]);

      // TOP2 should be B (5) and C (4). We have 3 blocks, each blinking both dice => 6 blinks total
      expect(dd.blinked.length, equals(6));
      final ids = dd.blinked.map((s) => s.split(':').first).toSet();
      expect(ids, equals({'B', 'C'}));
    });
  });
}
