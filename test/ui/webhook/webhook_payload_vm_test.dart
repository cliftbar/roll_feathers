import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/domains/webhook/webhook_payload_domain.dart';
import 'package:roll_feathers/repositories/webhook/webhook_payload_repository.dart';
import 'package:roll_feathers/ui/webhook/webhook_payload_editor_vm.dart';
import 'package:roll_feathers/ui/webhook/webhook_payloads_screen_vm.dart';

class _MemRepo implements WebhookPayloadRepository {
  final List<PayloadTemplate> _user = [];
  @override
  List<PayloadTemplate> builtins() => kBuiltinPayloads;
  @override
  Future<List<PayloadTemplate>> loadUserItems() async => List.of(_user);
  @override
  Future<void> upsert(PayloadTemplate item) async {
    final i = _user.indexWhere((p) => p.id == item.id);
    if (i >= 0) {
      _user[i] = item;
    } else {
      _user.add(item);
    }
  }

  @override
  Future<void> delete(String id) async => _user.removeWhere((p) => p.id == id);
  @override
  Future<PayloadTemplate?> byName(String ref) async {
    for (final p in [...kBuiltinPayloads, ..._user]) {
      if (p.id == ref || p.name == ref) return p;
    }
    return null;
  }
}

/// Repo whose async operations always throw — for exercising VM error paths.
class _ThrowingRepo implements WebhookPayloadRepository {
  @override
  List<PayloadTemplate> builtins() => kBuiltinPayloads;
  @override
  Future<List<PayloadTemplate>> loadUserItems() async => throw Exception('load boom');
  @override
  Future<void> upsert(PayloadTemplate item) async => throw Exception('save boom');
  @override
  Future<void> delete(String id) async => throw Exception('delete boom');
  @override
  Future<PayloadTemplate?> byName(String ref) async => null;
}

void main() {
  group('editor VM', () {
    late WebhookPayloadDomain domain;
    setUp(() => domain = WebhookPayloadDomain(_MemRepo()));

    test('new payload previews ok and is saveable', () {
      final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      expect(vm.preview.ok, isTrue);
      expect(vm.nameError, isNull);
      expect(vm.canSave, isTrue);
    });

    test('reserved name blocks save', () {
      final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      vm.setName('discord');
      expect(vm.nameError, isNotNull);
      expect(vm.canSave, isFalse);
    });

    test('broken body → preview error, not saveable', () {
      final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      vm.setName('mine');
      vm.setBody('{{#resultDice}}oops'); // unbalanced
      expect(vm.preview.ok, isFalse);
      expect(vm.canSave, isFalse);
    });

    test('choosing GET switches format to form', () {
      final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      vm.setMethod('GET');
      expect(vm.format, PayloadFormat.form);
    });

    test('built-in is read-only', () {
      final vm = WebhookPayloadEditorViewModel(domain, domain.builtins().first);
      expect(vm.canSave, isFalse);
    });

    test('save persists a valid payload', () async {
      final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      vm.setName('My Slack');
      vm.setBody('{"text":"{{die.name}}"}');
      await vm.save.execute();
      final users = await domain.loadUserPayloads();
      expect(users.any((p) => p.name == 'My Slack'), isTrue);
    });

    test('variable palette is non-empty and grouped', () {
      final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      expect(vm.variablePalette.keys, contains('Die (single / in loop)'));
      expect(vm.variablePalette.values.expand((e) => e), contains('{{die.name}}'));
    });

    test('testSend renders the draft and POSTs, reporting the status', () async {
      http.Request? captured;
      final client = MockClient((r) async {
        captured = r;
        return http.Response('', 204);
      });
      final d = WebhookPayloadDomain(_MemRepo(), client: client);
      final res = await d.testSend(const PayloadTemplate(id: 'x', name: 'x', body: '{"a":1}'), 'http://x/y');
      expect(res, contains('204'));
      expect(captured!.method, 'POST');
    });

    test('testSend with an empty URL prompts instead of sending', () async {
      final d = WebhookPayloadDomain(_MemRepo());
      expect(await d.testSend(const PayloadTemplate(id: 'x', name: 'x', body: '{}'), ''), contains('URL'));
    });

    test('a duplicate name is blocked on save (async uniqueness check)', () async {
      final repo = _MemRepo();
      await repo.upsert(const PayloadTemplate(id: 'a', name: 'Foo', body: '{}'));
      final d = WebhookPayloadDomain(repo);
      final vm = WebhookPayloadEditorViewModel(d, d.newBlank());
      vm.setName('Foo');
      vm.setBody('{"a":1}');
      await vm.save.execute();
      expect(vm.nameError, 'Name already used');
      expect((await d.loadUserPayloads()).where((p) => p.name == 'Foo'), hasLength(1)); // not persisted
    });

    test('editing an existing payload without renaming still saves (excludeId)', () async {
      final repo = _MemRepo();
      await repo.upsert(const PayloadTemplate(id: 'a', name: 'Foo', body: '{}'));
      final d = WebhookPayloadDomain(repo);
      final existing = (await d.loadUserPayloads()).first;
      final vm = WebhookPayloadEditorViewModel(d, existing);
      vm.setBody('{"changed":true}');
      await vm.save.execute();
      expect(vm.nameError, isNull);
      expect((await d.loadUserPayloads()).single.body, '{"changed":true}');
    });

    test('choosing POST after GET restores JSON; POST while JSON keeps JSON', () {
      final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      vm.setMethod('GET');
      expect(vm.format, PayloadFormat.form);
      vm.setMethod('POST');
      expect(vm.format, PayloadFormat.json);
      vm.setMethod('POST');
      expect(vm.format, PayloadFormat.json);
    });

    test('changing format re-runs the preview', () {
      final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      vm.setBody('{{die.name}}'); // bare value: invalid JSON, valid text
      expect(vm.preview.ok, isFalse);
      vm.setFormat(PayloadFormat.text);
      expect(vm.preview.ok, isTrue);
      expect(vm.preview.output, 'Gandalf');
    });

    test('editing marks dirty and clears a stale test-send result', () async {
      final client = MockClient((r) async => http.Response('', 200));
      final d = WebhookPayloadDomain(_MemRepo(), client: client);
      final vm = WebhookPayloadEditorViewModel(d, d.newBlank());
      vm.setName('mine');
      vm.setTestUrl('http://x/y');
      await vm.testSend.execute();
      expect(vm.testResult, isNotNull);
      vm.setBody('{"changed":1}');
      expect(vm.dirty, isTrue);
      expect(vm.testResult, isNull);
    });

    test('testSend GET appends the rendered body as a query string', () async {
      Uri? captured;
      final client = MockClient((r) async {
        captured = r.url;
        return http.Response('', 200);
      });
      final d = WebhookPayloadDomain(_MemRepo(), client: client);
      const t = PayloadTemplate(id: 'g', name: 'g', method: 'GET', format: PayloadFormat.form, body: 'a={{aggregate}}');
      final res = await d.testSend(t, 'http://x/y');
      expect(res, contains('200'));
      expect(captured!.query, 'a=18');
    });

    test('testSend rejects a non-http(s) URL without sending', () async {
      var called = false;
      final client = MockClient((r) async {
        called = true;
        return http.Response('', 200);
      });
      final d = WebhookPayloadDomain(_MemRepo(), client: client);
      final res = await d.testSend(const PayloadTemplate(id: 'x', name: 'x', body: '{}'), 'ftp://x/y');
      expect(res, contains('http'));
      expect(called, isFalse);
    });

    test('testSend surfaces a network error without leaking the URL', () async {
      final client = MockClient((r) async => throw http.ClientException('boom', r.url));
      final d = WebhookPayloadDomain(_MemRepo(), client: client);
      final res = await d.testSend(const PayloadTemplate(id: 'x', name: 'x', body: '{}'), 'http://secret.example/tok');
      expect(res, contains('Send failed'));
      expect(res, contains('boom'));
      expect(res, isNot(contains('secret.example'))); // URL not exposed in the UI string
    });

    test('newBlank seeds the generic body and is editable', () {
      final t = domain.newBlank();
      expect(t.isBuiltin, isFalse);
      expect(t.body, contains('{{rule.name}}'));
    });

    test('reference is the id for built-ins and the name for user payloads', () {
      final b = WebhookPayloadEditorViewModel(domain, domain.builtins().firstWhere((p) => p.id == 'generic'));
      expect(b.reference, 'generic');
      expect(b.ruleFragment, 'with generic');
      final u = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      u.setName('My Hook');
      expect(u.reference, 'My Hook');
      expect(u.ruleFragment, 'with My Hook');
    });

    test('a duplicate name is flagged live while typing (before Save)', () async {
      final repo = _MemRepo();
      await repo.upsert(const PayloadTemplate(id: 'a', name: 'Foo', body: '{}'));
      final d = WebhookPayloadDomain(repo);
      final vm = WebhookPayloadEditorViewModel(d, d.newBlank());
      vm.setName('Foo');
      await Future<void>.delayed(Duration.zero); // let the async check resolve
      expect(vm.nameError, 'Name already used');
      expect(vm.canSave, isFalse);
      // Typing a free name clears it.
      vm.setName('Bar');
      await Future<void>.delayed(Duration.zero);
      expect(vm.nameError, isNull);
    });

    test('variable palette has 24 well-formed tokens', () {
      final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
      final tokens = vm.variablePalette.values.expand((e) => e).toList();
      expect(tokens, hasLength(24));
      for (final tok in tokens) {
        expect(tok.startsWith('{{'), isTrue, reason: tok);
        expect(tok.contains('}}'), isTrue, reason: tok);
      }
    });
  });

  group('list VM', () {
    test('loads builtins + user payloads', () async {
      final repo = _MemRepo();
      await repo.upsert(const PayloadTemplate(id: 'u1', name: 'Mine', body: '{}'));
      final vm = WebhookPayloadsScreenViewModel(WebhookPayloadDomain(repo));
      await vm.load.execute();
      expect(vm.builtins, isNotEmpty);
      expect(vm.userPayloads.map((p) => p.name), contains('Mine'));
      expect(vm.loading, isFalse);
    });

    test('duplicate → new id, (copy) name, editable', () {
      final vm = WebhookPayloadsScreenViewModel(WebhookPayloadDomain(_MemRepo()));
      final b = vm.builtins.first;
      final d = vm.duplicate(b);
      expect(d.id, isNot(b.id));
      expect(d.name, '${b.name} (copy)');
      expect(d.isBuiltin, isFalse);
    });

    test('delete removes a user payload', () async {
      final repo = _MemRepo();
      await repo.upsert(const PayloadTemplate(id: 'u1', name: 'Mine', body: '{}'));
      final vm = WebhookPayloadsScreenViewModel(WebhookPayloadDomain(repo));
      await vm.load.execute();
      await vm.deletePayload.execute(vm.userPayloads.first);
      expect(vm.userPayloads, isEmpty);
    });

    test('a load failure clears the spinner and leaves the list empty (no throw)', () async {
      final vm = WebhookPayloadsScreenViewModel(WebhookPayloadDomain(_ThrowingRepo()));
      await vm.load.execute();
      expect(vm.loading, isFalse);
      expect(vm.userPayloads, isEmpty);
    });

    test('a delete failure is contained (no throw)', () async {
      final vm = WebhookPayloadsScreenViewModel(WebhookPayloadDomain(_ThrowingRepo()));
      await vm.load.execute();
      // Should complete without throwing even though delete() throws.
      await vm.deletePayload.execute(const PayloadTemplate(id: 'x', name: 'x', body: '{}'));
      expect(vm.loading, isFalse);
    });
  });

  group('PayloadTemplate serialization', () {
    test('toJson → fromJson round-trips fields (and forces a user item)', () {
      const t = PayloadTemplate(
        id: 'id1',
        name: 'My Hook',
        category: 'custom',
        method: 'GET',
        format: PayloadFormat.form,
        contentType: 'application/xml',
        headers: {'Authorization': 'Bearer x', 'X-Test': 'y'},
        body: 'a={{aggregate}}',
      );
      final back = PayloadTemplate.fromJson(t.toJson());
      expect(back.id, t.id);
      expect(back.name, t.name);
      expect(back.method, t.method);
      expect(back.format, t.format);
      expect(back.contentType, t.contentType);
      expect(back.headers, t.headers);
      expect(back.body, t.body);
      expect(back.isBuiltin, isFalse);
    });
  });
}
