import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roll_feathers/domains/roll_parser/target_dtos.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import '../../helpers/fakes.dart';

void main() {
  final app = FakeAppService();
  group('Discord Webhook', () {
    test('sends correctly formatted Discord embed', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((req) async {
        capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('', 200);
      });

      final payload = DiscordRollDTO(
        rule: 'Crit Test',
        aggregate: 20,
        timestamp: DateTime.utc(2024, 1, 1),
        resultDice: [
          DieInfoDTO(id: 'd1', name: 'Main Die', type: 'd20', value: 20),
        ],
      );

      await WebhookDomain(appService: app, httpClient: client).fireWebhook(
        url: 'https://discord.com/api/webhooks/123',
        method: 'POST',
        payload: payload,
      );

      expect(capturedBody, isNotNull);
      expect(capturedBody!['embeds'], isNotEmpty);
      final embed = capturedBody!['embeds'][0];
      expect(embed['title'], equals('Rule: Crit Test'));
      expect(embed['fields'], contains(equals(
        {'name': 'Aggregate', 'value': '20', 'inline': false},
      )));
      expect(embed['fields'], contains(equals(
        {'name': 'Main Die', 'value': '20 (d20)', 'inline': true},
      )));
    });

    test('always uses POST and sets JSON header', () async {
      String? method;
      String? contentType;
      final client = MockClient((req) async {
        method = req.method;
        contentType = req.headers['content-type'];
        return http.Response('', 200);
      });

      final payload = DiscordRollDTO(
        rule: 'r',
        aggregate: 10,
        timestamp: DateTime.now(),
        resultDice: [],
      );

      await WebhookDomain(appService: app, httpClient: client).fireWebhook(
        url: 'https://discord.com/api/webhooks/123',
        method: 'POST',
        payload: payload,
      );

      expect(method, equals('POST'));
      expect(contentType, equals('application/json'));
    });

    test('network errors are caught', () async {
      final client = MockClient((req) async => throw Exception('Discord down'));
      final payload = DiscordRollDTO(
        rule: 'r', aggregate: 10, timestamp: DateTime.now(), resultDice: [],
      );

      await expectLater(
        WebhookDomain(appService: app, httpClient: client).fireWebhook(
          url: 'https://discord.com/api/webhooks/123',
          method: 'POST',
          payload: payload,
        ),
        completes,
      );
    });

    test('DiscordRollDTO toQueryParams returns rule name', () {
      final payload = DiscordRollDTO(
        rule: 'myRule',
        aggregate: 10,
        timestamp: DateTime.now(),
        resultDice: [],
      );
      final params = payload.toQueryParams();
      expect(params['rule'], equals('myRule'));
      expect(params.length, equals(1));
    });
  });
}
