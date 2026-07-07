import 'package:flutter_test/flutter_test.dart';
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
  });
}
