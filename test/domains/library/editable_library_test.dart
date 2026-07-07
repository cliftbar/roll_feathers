import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/library/editable_library.dart';
import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/repositories/webhook/webhook_payload_repository.dart';

// The shared library contract is implemented by the webhook payload feature.
void main() {
  test('PayloadTemplate is an EditableLibraryItem', () {
    final EditableLibraryItem item = kBuiltinPayloads.first;
    expect(item.id, isNotEmpty);
    expect(item.name, isNotEmpty);
    expect(item.isBuiltin, isTrue);
  });

  test('WebhookPayloadRepository is a LibraryRepository<PayloadTemplate>', () {
    final LibraryRepository<PayloadTemplate> repo = SharedPrefsWebhookPayloadRepository();
    expect(repo.builtins(), isNotEmpty);
    expect(repo.builtins().every((p) => p.isBuiltin), isTrue);
  });
}
