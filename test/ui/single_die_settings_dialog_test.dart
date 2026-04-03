import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/ui/die_screen/single_die_settings_dialog.dart';

// ── Factories ─────────────────────────────────────────────────────────────────

VirtualDie _virtualDie({Color? color, String name = 'TestDie', String dType = 'd6'}) {
  final die = VirtualDie(dType: GenericDTypeFactory.getKnownChecked(dType), name: name);
  die.blinkColor = color;
  return die;
}

// ── Test pump helper ──────────────────────────────────────────────────────────

/// Pumps a host widget that opens SingleDieSettingsDialog as a real dialog
/// (via showDialog) so AlertDialog has a proper overlay context.
///
/// Returns immediately after pumping the host; call [_openDialog] to open it.
Future<void> _pumpHost(
  WidgetTester tester, {
  required GenericDie die,
  bool haEnabled = false,
  void Function(Color, GenericDie, String?)? onBlink,
  void Function(String)? onDisconnect,
  void Function(GenericDie, Color, String, GenericDType)? onSave,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (ctx) {
      return Scaffold(
        body: TextButton(
          child: const Text('Open'),
          onPressed: () => showDialog(
            context: ctx,
            builder: (_) => SingleDieSettingsDialog(
              die: die,
              haEnabled: haEnabled,
              onBlink: (c, d, e) async => onBlink?.call(c, d, e),
              onDisconnect: (id) async => onDisconnect?.call(id),
              onSave: (d, c, e, t) async => onSave?.call(d, c, e, t),
            ),
          ),
        ),
      );
    }),
  ));
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Pump + open in one call.
Future<void> _pumpDialog(
  WidgetTester tester, {
  GenericDie? die,
  bool haEnabled = false,
  void Function(Color, GenericDie, String?)? onBlink,
  void Function(String)? onDisconnect,
  void Function(GenericDie, Color, String, GenericDType)? onSave,
}) async {
  await _pumpHost(
    tester,
    die: die ?? _virtualDie(),
    haEnabled: haEnabled,
    onBlink: onBlink,
    onDisconnect: onDisconnect,
    onSave: onSave,
  );
  await _openDialog(tester);
}

// ── Color mode helpers ────────────────────────────────────────────────────────

/// Tap the DropdownMenu for color mode. byWidgetPredicate matches any
/// DropdownMenu<T> regardless of type parameter (runtime type erasure).
Finder _colorModeDropdown() =>
    find.byWidgetPredicate((w) => w is DropdownMenu).first;

Future<void> _selectColorMode(WidgetTester tester, String label) async {
  final dropdown = _colorModeDropdown();
  // Scroll the dropdown into view before tapping (content may have scrolled
  // after a text-field interaction).
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  // After opening, the label appears in the field AND the menu. Use .last to
  // hit the menu item.
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SingleDieSettingsDialog', () {
    // ── Rendering ─────────────────────────────────────────────────────────────

    testWidgets('renders with die name in title', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(name: 'My D6'));
      expect(find.text('My D6 Settings'), findsOneWidget);
    });

    testWidgets('shows all action buttons', (tester) async {
      await _pumpDialog(tester);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Blink'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('HA entity field disabled when haEnabled=false', (tester) async {
      await _pumpDialog(tester, haEnabled: false);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      final haField = fields.firstWhere(
        (f) => f.decoration?.labelText == 'Home Assistant Entity',
      );
      expect(haField.enabled, isFalse);
    });

    testWidgets('HA entity field enabled when haEnabled=true', (tester) async {
      await _pumpDialog(tester, haEnabled: true);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      final haField = fields.firstWhere(
        (f) => f.decoration?.labelText == 'Home Assistant Entity',
      );
      expect(haField.enabled, isTrue);
    });

    testWidgets('initial color pre-populated in hex field', (tester) async {
      // colorToHex defaults to uppercase
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFFFF0000)));
      expect(find.text('FF0000'), findsOneWidget);
    });

    // ── Color mode switching (the mouse-tracker crash scenario) ───────────────

    testWidgets('switches to ARGB / Sliders without crashing', (tester) async {
      await _pumpDialog(tester);
      await _selectColorMode(tester, 'ARGB / Sliders');
      expect(find.text('R'), findsOneWidget);
      expect(find.text('G'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('switches to HSV / Square without crashing', (tester) async {
      await _pumpDialog(tester);
      await _selectColorMode(tester, 'HSV / Square');
      expect(find.text('H'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('V'), findsOneWidget);
    });

    testWidgets('switches to HSL / Square without crashing', (tester) async {
      await _pumpDialog(tester);
      await _selectColorMode(tester, 'HSL / Square');
      expect(find.text('H'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
    });

    testWidgets('cycles through all modes without crashing', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: Colors.blue));
      await _selectColorMode(tester, 'ARGB / Sliders');
      await _selectColorMode(tester, 'HSV / Square');
      await _selectColorMode(tester, 'HSL / Square');
      await _selectColorMode(tester, 'Hex / Wheel');
      expect(find.byType(SingleDieSettingsDialog), findsOneWidget);
    });

    // ── Color sync across modes ───────────────────────────────────────────────

    testWidgets('RGB fields populate from initial color', (tester) async {
      // Color(0xFFFF8000) ≈ R=255, G=128, B=0, A=255
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFFFF8000)));
      await _selectColorMode(tester, 'ARGB / Sliders');
      // R=255 and A=255 both exist, so at least 2 matches
      expect(find.text('255'), findsAtLeastNWidgets(2));
      expect(find.text('128'), findsOneWidget);
    });

    testWidgets('HSV fields populate from pure red', (tester) async {
      // Pure red: H≈0, S=100, V=100
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFFFF0000)));
      await _selectColorMode(tester, 'HSV / Square');
      expect(find.text('100'), findsAtLeastNWidgets(1)); // S and V both 100
    });

    testWidgets('HSL fields populate from initial color', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFF0000FF)));
      await _selectColorMode(tester, 'HSL / Square');
      // Blue in HSL: H=240, S=100, L=50
      expect(find.text('240'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('editing R field does not corrupt G and B', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFF000000)));
      await _selectColorMode(tester, 'ARGB / Sliders');
      // R, G, B all start at '0'; enter directly into the R field's EditableText
      await tester.enterText(find.text('0').first, '200');
      await tester.pump();
      // G and B still show 0
      expect(find.text('0'), findsAtLeastNWidgets(2));
    });

    testWidgets('editing hex field changes displayed color', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: Colors.white));
      // Enter directly into the EditableText that shows 'FFFFFF'
      await tester.enterText(find.text('FFFFFF'), 'FF0000');
      await tester.pump();
      // Switch to RGB — R=255 and A=255 both present
      await _selectColorMode(tester, 'ARGB / Sliders');
      expect(find.text('255'), findsAtLeastNWidgets(1));
    });

    // ── Face selector ─────────────────────────────────────────────────────────

    testWidgets('virtual die shows face count pre-populated', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(dType: 'd20'));
      expect(find.widgetWithText(TextFormField, '20'), findsOneWidget);
    });

    // ── Callbacks ─────────────────────────────────────────────────────────────

    testWidgets('Cancel closes dialog', (tester) async {
      await _pumpDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(SingleDieSettingsDialog), findsNothing);
    });

    testWidgets('Save calls onSave and closes dialog', (tester) async {
      GenericDie? savedDie;
      Color? savedColor;
      await _pumpDialog(
        tester,
        die: _virtualDie(color: Colors.green),
        onSave: (d, c, e, t) {
          savedDie = d;
          savedColor = c;
        },
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(savedDie, isNotNull);
      expect(savedColor, isNotNull);
      expect(find.byType(SingleDieSettingsDialog), findsNothing);
    });

    testWidgets('Blink calls onBlink with current color', (tester) async {
      Color? blinkColor;
      await _pumpDialog(
        tester,
        die: _virtualDie(color: Colors.purple),
        onBlink: (c, _, __) => blinkColor = c,
      );
      await tester.tap(find.text('Blink'));
      await tester.pump();
      expect(blinkColor, isNotNull);
    });

    testWidgets('Disconnect calls onDisconnect with die id and closes', (tester) async {
      String? disconnectedId;
      final die = _virtualDie();
      await _pumpDialog(
        tester,
        die: die,
        onDisconnect: (id) => disconnectedId = id,
      );
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(disconnectedId, equals(die.dieId));
      expect(find.byType(SingleDieSettingsDialog), findsNothing);
    });
  });
}
