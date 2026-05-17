import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/testing/rule_evaluation_test_effects.dart';

import '../../helpers/fakes.dart';

// Builds a MockClient that records every request body/URL.
class _Recorder {
  final List<http.BaseRequest> requests = [];
  final List<Map<String, dynamic>> bodies = [];

  MockClient get client => MockClient((req) async {
        requests.add(req);
        if (req.method == 'POST') {
          final body = jsonDecode((req).body) as Map<String, dynamic>;
          bodies.add(body);
        }
        return http.Response('', 200);
      });
}

// Full v11 script targeting a webhook — parameterised for method and range.
String _script({
  String name = 'hookTest',
  String selection = r'$ALL_DICE',
  String aggregate = 'sum',
  String range = '[*:*]',
  String method = 'POST',
  String url = 'http://localhost/hook',
  String? extraAction,
}) {
  final extra = extraAction != null ? '\n    $extraAction' : '';
  return '''
define $name for roll *d*
  use selection $selection
    aggregate over selection $aggregate
    on result $range webhook $method $url$extra
''';
}

// Script with an extra action target in the same block before the webhook.
String _scriptWithCoAction({
  String method = 'POST',
  String url = 'http://localhost/hook',
}) => '''
define coAction for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink blue
    on result [*:*] webhook $method $url
''';

Future<RuleEvaluator> _parser(FakeDieDomain dd, FakeAppService app, http.Client client) async {
  final parser = RuleEvaluator(dd, app, WebhookDomain(appService: app, httpClient: client));
  await parser.init();
  return parser;
}

void main() {
  group('Evaluator — dispatch', () {
    late FakeDieDomain dd;
    late FakeAppService app;
    late _Recorder rec;

    setUp(() async {
      dd = FakeDieDomain();
      app = FakeAppService();
      rec = _Recorder();
    });

    test('3.1 POST fires when range matches', () async {
      final parser = await _parser(dd, app, rec.client);
      final die = FakeDie('a', 'Alpha', 10);
      await parser.evaluateRule(_script(), [die]).runEffects();
      expect(rec.requests.length, equals(1));
      expect(rec.requests.first.method, equals('POST'));
    });

    test('3.2 POST does not fire when range does not match', () async {
      final parser = await _parser(dd, app, rec.client);
      final die = FakeDie('a', 'Alpha', 5);
      // Range [10:20] — die sum=5 won't match
      await parser.evaluateRule(_script(range: '[10:20]'), [die]).runEffects();
      expect(rec.requests.length, equals(0));
    });

    test('3.3 payload contains rule name', () async {
      final parser = await _parser(dd, app, rec.client);
      await parser.evaluateRule(_script(name: 'myRule'), [FakeDie('a', 'A', 3)]).runEffects();
      expect(rec.bodies.first['rule'], equals('myRule'));
    });

    test('3.4 payload contains aggregate value', () async {
      final parser = await _parser(dd, app, rec.client);
      await parser.evaluateRule(_script(), [FakeDie('a', 'A', 7)]).runEffects();
      expect(rec.bodies.first['aggregate'], equals(7));
    });

    test('3.5 payload timestamp is valid ISO-8601 UTC', () async {
      final parser = await _parser(dd, app, rec.client);
      await parser.evaluateRule(_script(), [FakeDie('a', 'A', 4)]).runEffects();
      final ts = rec.bodies.first['timestamp'] as String;
      final dt = DateTime.parse(ts);
      expect(dt.isUtc, isTrue);
    });

    test('3.6 payload matched_range has correct inclusive bounds for [5:15]', () async {
      final parser = await _parser(dd, app, rec.client);
      await parser.evaluateRule(_script(range: '[5:15]'), [FakeDie('a', 'A', 10)]).runEffects();
      final mr = rec.bodies.first['matched_range'] as Map<String, dynamic>;
      expect(mr['start'], equals(5));
      expect(mr['end'], equals(15));
      expect(mr['start_inclusive'], isTrue);
      expect(mr['end_inclusive'], isTrue);
    });

    test('3.7 payload matched_range stores raw pre-adjustment bounds for (5:15)', () async {
      final parser = await _parser(dd, app, rec.client);
      // Exclusive bounds: (5:15) — getStart()=6, getEnd()=14, but stored raw as 5 and 15
      await parser.evaluateRule(_script(range: '(5:15)'), [FakeDie('a', 'A', 10)]).runEffects();
      final mr = rec.bodies.first['matched_range'] as Map<String, dynamic>;
      expect(mr['start'], equals(5));
      expect(mr['end'], equals(15));
      expect(mr['start_inclusive'], isFalse);
      expect(mr['end_inclusive'], isFalse);
    });

    test('3.8 result_dice contains only the selection dice', () async {
      // Script selects top 1 die from 3; result_dice should have 1 entry.
      const script = '''
define topOne for roll *d*
  make selection @TOP with top 1
  use selection @TOP
    aggregate over selection max
    on result [*:*] webhook POST http://localhost/hook
''';
      final parser = await _parser(dd, app, rec.client);
      final dice = [FakeDie('a', 'Low', 1), FakeDie('b', 'Mid', 3), FakeDie('c', 'High', 5)];
      await parser.evaluateRule(script, dice).runEffects();
      final resultDice = rec.bodies.first['result_dice'] as List;
      expect(resultDice.length, equals(1));
      expect((resultDice.first as Map)['id'], equals('c'));
    });

    test('3.9 all_dice contains all rolled dice', () async {
      final parser = await _parser(dd, app, rec.client);
      final dice = [FakeDie('x', 'X', 1), FakeDie('y', 'Y', 2), FakeDie('z', 'Z', 3)];
      await parser.evaluateRule(_script(), dice).runEffects();
      final allDice = rec.bodies.first['all_dice'] as List;
      expect(allDice.length, equals(3));
    });

    test('3.10 die object contains id, name, type, value', () async {
      final parser = await _parser(dd, app, rec.client);
      final die = FakeDie('abc', 'MyDie', 6, dName: 'd6');
      await parser.evaluateRule(_script(), [die]).runEffects();
      final allDice = rec.bodies.first['all_dice'] as List;
      final dieJson = allDice.first as Map<String, dynamic>;
      expect(dieJson['id'], equals('abc'));
      expect(dieJson['name'], equals('MyDie'));
      expect(dieJson['type'], equals('d6'));
      expect(dieJson['value'], equals(6));
    });

    test('3.11 battery included in die object when available', () async {
      final parser = await _parser(dd, app, rec.client);
      final die = FakeDie('a', 'A', 4);
      die.state = DiceState(currentFaceValue: 4, batteryLevel: 80);
      await parser.evaluateRule(_script(), [die]).runEffects();
      final allDice = rec.bodies.first['all_dice'] as List;
      expect((allDice.first as Map)['battery'], equals(80));
      final resultDice = rec.bodies.first['result_dice'] as List;
      expect((resultDice.first as Map)['battery'], equals(80));
    });

    test('3.12 battery omitted from die object when null', () async {
      final parser = await _parser(dd, app, rec.client);
      final die = FakeDie('a', 'A', 4);
      // batteryLevel defaults to null in DiceState
      await parser.evaluateRule(_script(), [die]).runEffects();
      final allDice = rec.bodies.first['all_dice'] as List;
      expect((allDice.first as Map).containsKey('battery'), isFalse);
    });

    test('3.13 actions contains co-action blink with args', () async {
      final parser = await _parser(dd, app, rec.client);
      await parser.evaluateRule(_scriptWithCoAction(), [FakeDie('a', 'A', 5)]).runEffects();
      final actions = rec.bodies.first['actions'] as List;
      expect(actions.length, equals(1));
      expect((actions.first as Map)['type'], equals('blink'));
      expect((actions.first as Map)['args'], equals(['blue']));
    });

    test('3.14 actions excludes other webhook targets', () async {
      // Two webhooks in the same block — neither should appear in actions.
      const script = '''
define twoHooks for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] webhook POST http://localhost/hook1
    on result [*:*] webhook POST http://localhost/hook2
''';
      final parser = await _parser(dd, app, rec.client);
      await parser.evaluateRule(script, [FakeDie('a', 'A', 3)]).runEffects();
      // Both hooks fire
      expect(rec.requests.length, equals(2));
      // Neither appears in actions
      for (final body in rec.bodies) {
        final actions = body['actions'] as List;
        expect(actions, isEmpty);
      }
    });

    test('3.15 actions strips \$ALL_DICE token from args', () async {
      const script = r'''
define stripToken for roll *d*
  use selection $ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink $ALL_DICE
    on result [*:*] webhook POST http://localhost/hook
''';
      final parser = await _parser(dd, app, rec.client);
      await parser.evaluateRule(script, [FakeDie('a', 'A', 3)]).runEffects();
      final actions = rec.bodies.first['actions'] as List;
      expect(actions.length, equals(1));
      final args = (actions.first as Map)['args'] as List;
      expect(args, isNot(contains(r'$ALL_DICE')));
    });

    test('3.16 GET fires with aggregate and rule as query params', () async {
      final parser = await _parser(dd, app, rec.client);
      final die = FakeDie('a', 'A', 9);
      await parser.evaluateRule(_script(method: 'GET', name: 'getRule'), [die]).runEffects();
      expect(rec.requests.length, equals(1));
      final uri = rec.requests.first.url;
      expect(uri.queryParameters['aggregate'], equals('9'));
      expect(uri.queryParameters['rule'], equals('getRule'));
    });

    test('3.17 webhook failure does not prevent co-action blink', () async {
      // Client that always throws — blink should still fire.
      final throwingClient = MockClient((_) async => throw Exception('network down'));
      final parser = await _parser(dd, app, throwingClient);
      await parser.evaluateRule(_scriptWithCoAction(), [FakeDie('a', 'A', 5)]).runEffects();
      expect(dd.blinked, isNotEmpty);
    });

    test('3.18 multiple webhooks in same block all fire', () async {
      const script = '''
define multi for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] webhook POST http://localhost/hook1
    on result [*:*] webhook POST http://localhost/hook2
''';
      final parser = await _parser(dd, app, rec.client);
      await parser.evaluateRule(script, [FakeDie('a', 'A', 3)]).runEffects();
      expect(rec.requests.length, equals(2));
    });
  });

}
