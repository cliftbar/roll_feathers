import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/domains/api_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:shelf/shelf.dart';

import '../test_util.dart';

// Exercises buildApiHandler() directly via constructed Request objects,
// rather than binding a real socket through ApiDomainServer.create() — the
// handler is a plain `Future<Response> Function(Request)`, so no port is
// needed at all.
void main() {
  late MockRollDomain rollDomain;

  setUp(() {
    rollDomain = MockRollDomain();
  });

  Request getRequest(String path) => Request('GET', Uri.parse('http://localhost$path'));

  group('GET /api/last-roll', () {
    test('returns 404 when roll history is empty', () async {
      when(() => rollDomain.rollHistory).thenReturn([]);
      final response = await buildApiHandler(rollDomain)(getRequest('/api/last-roll'));
      expect(response.statusCode, 404);
    });

    test('returns the most recent roll as JSON', () async {
      final result = RollResult(rollType: RollType.sum, rollResult: 7, rolls: {'die-A': 7});
      when(() => rollDomain.rollHistory).thenReturn([result]);

      final response = await buildApiHandler(rollDomain)(getRequest('/api/last-roll'));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(body['rollResult'], 7);
      expect(body['rollType'], 'sum');
      expect(body['rolls'], {'die-A': 7});
    });
  });

  test('unknown route returns 404', () async {
    when(() => rollDomain.rollHistory).thenReturn([]);
    final response = await buildApiHandler(rollDomain)(getRequest('/api/unknown'));
    expect(response.statusCode, 404);
  });
}
