import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/roll_domain.dart';

import '../../helpers/fakes.dart';

/// Spins up a real loopback HTTP server on a random port.
/// Collects all received requests; closes automatically in tearDown.
class _LocalServer {
  late HttpServer _server;
  final List<_Captured> received = [];
  StreamSubscription? _sub;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _sub = _server.listen((req) async {
      final body = await utf8.decodeStream(req);
      received.add(_Captured(
        method: req.method,
        uri: req.uri,
        body: body,
        statusCode: req.response.statusCode,
      ));
      req.response.statusCode = 200;
      await req.response.close();
    });
  }

  int get port => _server.port;
  String get url => 'http://127.0.0.1:$port';

  Future<void> stop() async {
    await _sub?.cancel();
    await _server.close(force: true);
  }
}

class _Captured {
  final String method;
  final Uri uri;
  final String body;
  final int statusCode;

  _Captured({required this.method, required this.uri, required this.body, required this.statusCode});
}

// Full v11 script for integration test.
String _integrationScript({String method = 'POST', required String url}) => '''
define intTest for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] webhook $method $url
''';

void main() {
  // Integration tests use real I/O — they are inherently slightly slower.
  group('Webhook integration — real HTTP server', () {
    late _LocalServer server;
    late FakeDieDomain dd;
    late FakeAppService app;

    setUp(() async {
      server = _LocalServer();
      await server.start();
      dd = FakeDieDomain();
      app = FakeAppService();
    });

    tearDown(() async {
      await server.stop();
    });

    test('4.1 POST reaches real server', () async {
      final rd = await RollDomain.create(dd, app);
      await rd.ruleParser.runRuleAsync(
        _integrationScript(url: '${server.url}/roll'),
        [FakeDie('a', 'A', 5)],
      );
      expect(server.received.length, equals(1));
      expect(server.received.first.method, equals('POST'));
    });

    test('4.2 POST body is valid JSON with rule and aggregate', () async {
      final rd = await RollDomain.create(dd, app);
      await rd.ruleParser.runRuleAsync(
        _integrationScript(url: '${server.url}/roll'),
        [FakeDie('a', 'A', 6)],
      );
      final body = jsonDecode(server.received.first.body) as Map<String, dynamic>;
      expect(body.containsKey('rule'), isTrue);
      expect(body.containsKey('aggregate'), isTrue);
    });

    test('4.3 GET reaches real server with correct query params', () async {
      final rd = await RollDomain.create(dd, app);
      await rd.ruleParser.runRuleAsync(
        _integrationScript(method: 'GET', url: '${server.url}/hook'),
        [FakeDie('a', 'A', 8)],
      );
      expect(server.received.length, equals(1));
      expect(server.received.first.method, equals('GET'));
      expect(server.received.first.uri.queryParameters['aggregate'], equals('8'));
      expect(server.received.first.uri.queryParameters.containsKey('rule'), isTrue);
    });

    test('4.4 dice not interrupted when server returns 500', () async {
      // Override handler to return 500.
      final server500 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server500.listen((req) async {
        req.response.statusCode = 500;
        await req.response.close();
      });
      addTearDown(() => server500.close(force: true));

      final rd = await RollDomain.create(dd, app);
      // Should complete without throwing.
      await expectLater(
        rd.ruleParser.runRuleAsync(
          _integrationScript(url: 'http://127.0.0.1:${server500.port}/roll'),
          [FakeDie('a', 'A', 3)],
        ),
        completes,
      );
    });

    test('4.5 dice not interrupted when server is unreachable', () async {
      // Use a port with no server listening.
      final rd = await RollDomain.create(dd, app);
      await expectLater(
        rd.ruleParser.runRuleAsync(
          _integrationScript(url: 'http://127.0.0.1:19999/roll'),
          [FakeDie('a', 'A', 3)],
        ),
        completes,
      );
    });
  });
}
