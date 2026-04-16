import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';

void main() {
  group('fireWebhook — POST', () {
    test('2.1 sends request to the correct URL', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('', 200);
      });
      await fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: {'rule': 'r', 'aggregate': 7}, httpClient: client);
      expect(captured, isNotNull);
      expect(captured.toString(), equals('http://localhost/roll'));
    });

    test('2.2 sets Content-Type: application/json header', () async {
      String? contentType;
      final client = MockClient((req) async {
        contentType = req.headers['content-type'];
        return http.Response('', 200);
      });
      await fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: {'rule': 'r', 'aggregate': 7}, httpClient: client);
      expect(contentType, equals('application/json'));
    });

    test('2.3 body decodes to the provided payload', () async {
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('', 200);
      });
      final payload = {'rule': 'test', 'aggregate': 7, 'extra': 'data'};
      await fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: payload, httpClient: client);
      expect(body, equals(payload));
    });
  });

  group('fireWebhook — GET', () {
    test('2.4 uses the correct base URL', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('', 200);
      });
      await fireWebhook(
        url: 'http://localhost/hook',
        method: 'GET',
        payload: {'aggregate': 7, 'rule': 'test'},
        httpClient: client,
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
      await fireWebhook(
        url: 'http://localhost/hook',
        method: 'GET',
        payload: {'aggregate': 7, 'rule': 'test'},
        httpClient: client,
      );
      expect(captured!.queryParameters['aggregate'], equals('7'));
    });

    test('2.6 appends rule query param', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('', 200);
      });
      await fireWebhook(
        url: 'http://localhost/hook',
        method: 'GET',
        payload: {'aggregate': 3, 'rule': 'myRule'},
        httpClient: client,
      );
      expect(captured!.queryParameters['rule'], equals('myRule'));
    });

    test('2.7 GET sends no body', () async {
      String? body;
      final client = MockClient((req) async {
        body = req.body;
        return http.Response('', 200);
      });
      await fireWebhook(
        url: 'http://localhost/hook',
        method: 'GET',
        payload: {'aggregate': 5, 'rule': 'r'},
        httpClient: client,
      );
      expect(body, isEmpty);
    });

    test('2.11 GET replaces all existing query params (documents Uri.replace behavior)', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('', 200);
      });
      // URL already has ?foo=bar
      await fireWebhook(
        url: 'http://localhost/hook?foo=bar',
        method: 'GET',
        payload: {'aggregate': 5, 'rule': 'r'},
        httpClient: client,
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
      // Must complete without throwing
      await expectLater(
        fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: {'rule': 'r', 'aggregate': 0}, httpClient: client),
        completes,
      );
    });

    test('2.9 malformed URL does not throw', () async {
      // No client needed — Uri.parse of a bad URL throws, caught by try/catch
      await expectLater(
        fireWebhook(url: 'not a url ://', method: 'POST', payload: {'rule': 'r', 'aggregate': 0}),
        completes,
      );
    });

    test('2.10 injected client is called', () async {
      bool wasCalled = false;
      final client = MockClient((req) async {
        wasCalled = true;
        return http.Response('', 200);
      });
      await fireWebhook(url: 'http://localhost/roll', method: 'POST', payload: {'rule': 'r', 'aggregate': 0}, httpClient: client);
      expect(wasCalled, isTrue);
    });
  });
}
