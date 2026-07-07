import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/domains/webhook/webhook_payload_domain.dart';
import 'package:roll_feathers/repositories/webhook/webhook_payload_repository.dart';
import 'package:roll_feathers/ui/webhook/webhook_payload_editor_screen.dart';
import 'package:roll_feathers/ui/webhook/webhook_payload_editor_vm.dart';
import 'package:roll_feathers/ui/webhook/webhook_payloads_screen.dart';
import 'package:roll_feathers/ui/webhook/webhook_payloads_screen_vm.dart';

class _MemRepo implements WebhookPayloadRepository {
  final List<PayloadTemplate> _user = [];
  @override
  List<PayloadTemplate> builtins() => kBuiltinPayloads;
  @override
  Future<List<PayloadTemplate>> loadUserItems() async => List.of(_user);
  @override
  Future<void> upsert(PayloadTemplate item) async => _user.add(item);
  @override
  Future<void> delete(String id) async => _user.removeWhere((p) => p.id == id);
  @override
  Future<PayloadTemplate?> byName(String ref) async => null;
}

void main() {
  testWidgets('payloads screen lists built-ins', (tester) async {
    final domain = WebhookPayloadDomain(_MemRepo());
    await tester.pumpWidget(MaterialApp(
      home: WebhookPayloadsScreen(vm: WebhookPayloadsScreenViewModel(domain), domain: domain),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('Discord (Classic)'), findsOneWidget);
    expect(find.text('Generic JSON'), findsOneWidget);
  });

  testWidgets('editor renders its fields (preview logic is VM-tested)', (tester) async {
    final domain = WebhookPayloadDomain(_MemRepo());
    final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
    await tester.pumpWidget(MaterialApp(home: WebhookPayloadEditorScreen(vm: vm)));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'New Payload'), findsOneWidget); // name field
    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    // The VM has a valid preview for the seeded generic body.
    expect(vm.preview.ok, isTrue);
  });

  testWidgets('editor shows a reserved-name error and disables Save', (tester) async {
    final domain = WebhookPayloadDomain(_MemRepo());
    final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
    await tester.pumpWidget(MaterialApp(home: WebhookPayloadEditorScreen(vm: vm)));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'New Payload').first, 'discord');
    await tester.pumpAndSettle();
    expect(find.text('Reserved name — pick another'), findsOneWidget);
    final save = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
    expect(save.onPressed, isNull);
  });
}
