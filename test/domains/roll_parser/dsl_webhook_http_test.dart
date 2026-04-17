import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';
import 'package:roll_feathers/domains/roll_parser/target_dtos.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import '../../helpers/fakes.dart';

void main() {
  final app = FakeAppService();
  final dummyRange = RollResultRange(true, 0, 100, true);

  group('fireWebhook — POST', () {
    test('2.1 sends request to the correct URL', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('', 200);
      });
      final payload = RollResultDTO(
        rule: 'r',
        aggregate: 7,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      await WebhookDomain(appService: app, httpClient: client).fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: payload);
      expect(captured, isNotNull);
      expect(captured.toString(), equals('http://localhost/roll'));
    });

    test('2.2 sets Content-Type: application/json header', () async {
      String? contentType;
      final client = MockClient((req) async {
        contentType = req.headers['content-type'];
        return http.Response('', 200);
      });
      final payload = RollResultDTO(
        rule: 'r',
        aggregate: 7,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      await WebhookDomain(appService: app, httpClient: client).fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: payload);
      expect(contentType, equals('application/json'));
    });

    test('2.3 body decodes to the provided payload', () async {
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('', 200);
      });
      final payload = RollResultDTO(
        rule: 'test',
        aggregate: 7,
        timestamp: DateTime.utc(2024, 1, 1),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [ActionDTO(type: 'blink', args: [])],
      );
      await WebhookDomain(appService: app, httpClient: client).fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: payload);
      expect(body?['rule'], equals('test'));
      expect(body?['aggregate'], equals(7));
      expect(body?['actions'], equals([{'type': 'blink', 'args': []}]));
    });
  });

  group('fireWebhook — GET', () {
    test('2.4 uses the correct base URL', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('', 200);
      });
      final payload = RollResultDTO(
        rule: 'test',
        aggregate: 7,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      await WebhookDomain(appService: app, httpClient: client).fireWebhook(
        url: 'http://localhost/hook',
        method: 'GET',
        payload: payload,
      );
      expect(captured, isNotNull);
      expect(captured!.host, equals('localhost'));
      expect(captured!.path, equals('/hook'));
    });

    test('2.5 appends aggregate query param', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('', 200);
      });
      final payload = RollResultDTO(
        rule: 'test',
        aggregate: 7,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      await WebhookDomain(appService: app, httpClient: client).fireWebhook(
        url: 'http://localhost/hook',
        method: 'GET',
        payload: payload,
      );
      expect(captured!.queryParameters['aggregate'], equals('7'));
    });

    test('2.6 appends rule query param', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('', 200);
      });
      final payload = RollResultDTO(
        rule: 'myRule',
        aggregate: 3,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      await WebhookDomain(appService: app, httpClient: client).fireWebhook(
        url: 'http://localhost/hook',
        method: 'GET',
        payload: payload,
      );
      expect(captured!.queryParameters['rule'], equals('myRule'));
    });

    test('2.7 GET sends no body', () async {
      String? body;
      final client = MockClient((req) async {
        body = req.body;
        return http.Response('', 200);
      });
      final payload = RollResultDTO(
        rule: 'r',
        aggregate: 5,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      await WebhookDomain(appService: app, httpClient: client).fireWebhook(
        url: 'http://localhost/hook',
        method: 'GET',
        payload: payload,
      );
      expect(body, isEmpty);
    });

    test('2.11 GET replaces all existing query params (documents Uri.replace behavior)', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('', 200);
      });
      final payload = RollResultDTO(
        rule: 'r',
        aggregate: 5,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      // URL already has ?foo=bar
      await WebhookDomain(appService: app, httpClient: client).fireWebhook(
        url: 'http://localhost/hook?foo=bar',
        method: 'GET',
        payload: payload,
      );
      // Uri.replace replaces all query params — foo should be gone
      expect(captured!.queryParameters.containsKey('foo'), isFalse);
      expect(captured!.queryParameters['aggregate'], equals('5'));
      expect(captured!.queryParameters['rule'], equals('r'));
    });
  });

  group('fireWebhook — error handling', () {
    test('2.8 HTTP network error does not throw', () async {
      final client = MockClient((req) async => throw Exception('network error'));
      final payload = RollResultDTO(
        rule: 'r',
        aggregate: 0,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      // Must complete without throwing
      await expectLater(
        WebhookDomain(appService: app, httpClient: client).fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: payload),
        completes,
      );
    });

    test('2.9 malformed URL does not throw', () async {
      final payload = RollResultDTO(
        rule: 'r',
        aggregate: 0,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      // No client needed — Uri.parse of a bad URL throws, caught by try/catch
      await expectLater(
        WebhookDomain(appService: app).fireWebhook(url: 'not a url ://', method: 'POST', payload: payload),
        completes,
      );
    });

    test('2.10 injected client is called', () async {
      bool wasCalled = false;
      final client = MockClient((req) async {
        wasCalled = true;
        return http.Response('', 200);
      });
      final payload = RollResultDTO(
        rule: 'r',
        aggregate: 0,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      await WebhookDomain(appService: app, httpClient: client).fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: payload);
      expect(wasCalled, isTrue);
    });

    test('2.12 RollResultDTO toQueryParams returns rule and aggregate', () {
      final payload = RollResultDTO(
        rule: 'myRule',
        aggregate: 42,
        timestamp: DateTime.now(),
        matchedRange: dummyRange,
        allDice: [],
        resultDice: [],
        actions: [],
      );
      final params = payload.toQueryParams();
      expect(params['rule'], equals('myRule'));
      expect(params['aggregate'], equals('42'));
    });
  });
}
