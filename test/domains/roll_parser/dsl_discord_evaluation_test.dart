import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/testing/rule_evaluation_test_effects.dart';

import '../../helpers/fakes.dart';

// Records requests for verification.
class _Recorder {
  final List<http.BaseRequest> requests = [];
  final List<Map<String, dynamic>> bodies = [];

  MockClient get client => MockClient((req) async {
        requests.add(req);
        if (req.method == 'POST') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          bodies.add(body);
        }
        return http.Response('', 200);
      });
}

String _discordScript({
  String name = 'discordTest',
  String selection = r'$ALL_DICE',
  String aggregate = 'sum',
  String range = '[*:*]',
  String url = 'https://discord.com/api/webhooks/123/abc',
}) {
  return '''
define $name for roll *d*
  use selection $selection
    aggregate over selection $aggregate
    on result $range discord $url
''';
}

Future<RuleEvaluator> _parser(FakeDieDomain dd, FakeAppService app, http.Client client) async {
  final parser = RuleEvaluator(dd, app, WebhookDomain(appService: app, httpClient: client));
  await parser.init();
  return parser;
}

void main() {
  group('DSL discord dispatch', () {
    late FakeDieDomain dd;
    late FakeAppService app;
    late _Recorder rec;

    setUp(() async {
      dd = FakeDieDomain();
      app = FakeAppService();
      rec = _Recorder();
    });

    test('Discord target fires POST with embeds', () async {
      final parser = await _parser(dd, app, rec.client);
      final die = FakeDie('d1', 'Main Die', 20, dName: 'd20');
      
      await parser.evaluateRule(_discordScript(), [die]).runEffects();
      
      expect(rec.requests.length, equals(1));
      expect(rec.requests.first.method, equals('POST'));
      expect(rec.requests.first.url.toString(), equals('https://discord.com/api/webhooks/123/abc'));
      
      final body = rec.bodies.first;
      expect(body.containsKey('embeds'), isTrue);
      final embed = (body['embeds'] as List).first;
      expect(embed['title'], contains('discordTest'));
      
      final fields = embed['fields'] as List;
      // Should have Aggregate field + 1 die field
      expect(fields.any((f) => f['name'] == 'Aggregate' && f['value'] == '20'), isTrue);
      expect(fields.any((f) => f['name'] == 'Main Die' && f['value'] == '20 (d20)'), isTrue);
    });

    test('Discord target respects matched range', () async {
      final parser = await _parser(dd, app, rec.client);
      final die = FakeDie('d1', 'A', 5);
      
      // Range [10:*] should not fire for sum=5
      await parser.evaluateRule(_discordScript(range: '[10:*]'), [die]).runEffects();
      expect(rec.requests.length, equals(0));
      
      // Range [5:*] should fire
      await parser.evaluateRule(_discordScript(range: '[5:*]'), [die]).runEffects();
      expect(rec.requests.length, equals(1));
    });
  });
}
