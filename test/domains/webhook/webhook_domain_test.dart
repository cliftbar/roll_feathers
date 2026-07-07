import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_context.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/repositories/webhook/webhook_payload_repository.dart';

import '../../helpers/fakes.dart';

class _FakeRepo implements WebhookPayloadRepository {
  final List<PayloadTemplate> user;
  _FakeRepo([this.user = const []]);
  @override
  List<PayloadTemplate> builtins() => kBuiltinPayloads;
  @override
  Future<List<PayloadTemplate>> loadUserItems() async => user;
  @override
  Future<void> upsert(PayloadTemplate item) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<PayloadTemplate?> byName(String ref) async {
    for (final p in [...kBuiltinPayloads, ...user]) {
      if (p.id == ref || p.name == ref) return p;
    }
    return null;
  }
}

void main() {
  final ctx = PayloadContext.sample;

  WebhookDomain domain(http.Client client, {FakeAppService? app, List<PayloadTemplate> user = const []}) =>
      WebhookDomain(appService: app ?? FakeAppService(), httpClient: client, payloads: _FakeRepo(user));

  test('POST sends the rendered JSON body with content-type', () async {
    http.Request? req;
    String? body;
    final client = MockClient((r) async {
      req = r;
      body = r.body;
      return http.Response('', 200);
    });
    await domain(client).fire(url: 'http://localhost/roll', payloadName: 'generic', context: ctx);
    expect(req!.method, 'POST');
    expect(req!.url.toString(), 'http://localhost/roll');
    expect(req!.headers['Content-Type'], contains('application/json'));
    expect((jsonDecode(body!) as Map)['rule'], 'attackRoll');
  });

  test('GET appends the rendered query to the URL', () async {
    Uri? url;
    final client = MockClient((r) async {
      url = r.url;
      return http.Response('', 200);
    });
    await domain(client).fire(url: 'http://localhost/hook', payloadName: 'generic-get', context: ctx);
    expect(url.toString(), 'http://localhost/hook?rule=attackRoll&aggregate=18');
  });

  test('disabled webhooks → no request', () async {
    var called = false;
    final client = MockClient((r) async {
      called = true;
      return http.Response('', 200);
    });
    final app = FakeAppService()..setWebhooksEnabled(false);
    await domain(client, app: app).fire(url: 'http://x/y', payloadName: 'generic', context: ctx);
    expect(called, isFalse);
  });

  test('unknown payload name → no request (dangling ref)', () async {
    var called = false;
    final client = MockClient((r) async {
      called = true;
      return http.Response('', 200);
    });
    await domain(client).fire(url: 'http://x/y', payloadName: 'does-not-exist', context: ctx);
    expect(called, isFalse);
  });

  test('custom headers from the template are sent', () async {
    http.Request? req;
    final client = MockClient((r) async {
      req = r;
      return http.Response('', 200);
    });
    const p = PayloadTemplate(
      id: 'auth',
      name: 'auth',
      body: '{"ok":true}',
      headers: {'Authorization': 'Bearer tok'},
    );
    await domain(client, user: [p]).fire(url: 'http://x/y', payloadName: 'auth', context: ctx);
    expect(req!.headers['Authorization'], 'Bearer tok');
  });

  test('render error → no request (does not throw)', () async {
    var called = false;
    final client = MockClient((r) async {
      called = true;
      return http.Response('', 200);
    });
    const broken = PayloadTemplate(id: 'b', name: 'b', body: '{{#resultDice}}{"x":1}'); // unclosed loop
    await domain(client, user: [broken]).fire(url: 'http://x/y', payloadName: 'b', context: ctx);
    expect(called, isFalse);
  });

  test('invalid URL is swallowed (does not throw)', () async {
    final client = MockClient((r) async => http.Response('', 200));
    await expectLater(
      domain(client).fire(url: 'not a url ://', payloadName: 'generic', context: ctx),
      completes,
    );
  });
}
