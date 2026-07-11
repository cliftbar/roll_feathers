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
    expect(find.byKey(const Key('payload-name-field')), findsOneWidget); // name field
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
    await tester.enterText(find.byKey(const Key('payload-name-field')), 'discord');
    await tester.pumpAndSettle();
    expect(find.text('Reserved name — pick another'), findsOneWidget);
    final save = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
    expect(save.onPressed, isNull);
  });

  testWidgets('wide layout shows editor and live preview side by side (no tabs)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final domain = WebhookPayloadDomain(_MemRepo());
    final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
    await tester.pumpWidget(MaterialApp(home: WebhookPayloadEditorScreen(vm: vm)));
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsNothing);
    // Body editor and the live preview are visible at the same time.
    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Preview (sample roll)'), findsOneWidget);
  });

  testWidgets('narrow layout splits into Edit / Preview tabs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final domain = WebhookPayloadDomain(_MemRepo());
    final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
    await tester.pumpWidget(MaterialApp(home: WebhookPayloadEditorScreen(vm: vm)));
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Edit'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Preview'), findsOneWidget);
    // Edit tab is active first: body visible, preview off-screen.
    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Preview (sample roll)'), findsNothing);
    // Tapping Preview reveals it.
    await tester.tap(find.widgetWithText(Tab, 'Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Preview (sample roll)'), findsOneWidget);
  });

  testWidgets('narrow Preview tab surfaces an error badge when the template is broken', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final domain = WebhookPayloadDomain(_MemRepo());
    final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
    await tester.pumpWidget(MaterialApp(home: WebhookPayloadEditorScreen(vm: vm)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsNothing);
    vm.setBody('{{#resultDice}}oops'); // unbalanced → preview error
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('tapping a variable chip inserts its token into the body', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 2000)); // tall: palette fully rendered
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final domain = WebhookPayloadDomain(_MemRepo());
    final vm = WebhookPayloadEditorViewModel(domain, domain.newBlank());
    await tester.pumpWidget(MaterialApp(home: WebhookPayloadEditorScreen(vm: vm)));
    await tester.pumpAndSettle();
    expect(vm.body.contains('{{blink.color}}'), isFalse); // not in the seeded generic body
    await tester.tap(find.widgetWithText(ActionChip, '{{blink.color}}'));
    await tester.pumpAndSettle();
    expect(vm.body.contains('{{blink.color}}'), isTrue);
  });

  testWidgets('deleting a user payload asks for confirmation then removes it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400)); // tall: user row on screen
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _MemRepo();
    await repo.upsert(const PayloadTemplate(id: 'u1', name: 'Mine', body: '{}'));
    final domain = WebhookPayloadDomain(repo);
    final vm = WebhookPayloadsScreenViewModel(domain);
    await tester.pumpWidget(MaterialApp(home: WebhookPayloadsScreen(vm: vm, domain: domain)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Mine"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(vm.userPayloads.map((p) => p.name), isNot(contains('Mine')));
  });

  testWidgets('tapping a built-in opens a read-only editor (banner, no Save)', (tester) async {
    final domain = WebhookPayloadDomain(_MemRepo());
    final vm = WebhookPayloadsScreenViewModel(domain);
    await tester.pumpWidget(MaterialApp(home: WebhookPayloadsScreen(vm: vm, domain: domain)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generic JSON'));
    await tester.pumpAndSettle();
    expect(find.textContaining('(built-in)'), findsOneWidget);
    expect(find.textContaining('Duplicate it to make an editable copy'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Save'), findsNothing);
  });
}
