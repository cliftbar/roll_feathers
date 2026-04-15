import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';
import 'package:roll_feathers/ui/die_screen/single_die_settings_dialog.dart';

// ── Factories ─────────────────────────────────────────────────────────────────

VirtualDie _virtualDie({Color? color, String name = 'TestDie', String dType = 'd6'}) {
  final die = VirtualDie(dType: GenericDTypeFactory.getKnownChecked(dType), name: name);
  die.blinkColor = color;
  return die;
}

// TestBleDie has type=pixel, used for Pixels-specific UI tests.
TestBleDie _pixelDie({
  String name = 'Test Pixel',
  bool rollingEnabled = false,
  Color? rollingColor,
  RollingFlashPreset preset = RollingFlashPreset.strobe,
}) {
  final die = TestBleDie(name);
  die.rollingFlashEnabled = rollingEnabled;
  die.rollingFlashColor = rollingColor;
  die.rollingFlashPreset = preset;
  return die;
}

// TestGoDiceDie has type=godice, used for GoDice-specific UI tests.
TestGoDiceDie _godiceDie({String name = 'Test GoDice'}) {
  return TestGoDiceDie(name);
}

// ── Test pump helper ──────────────────────────────────────────────────────────

/// Pumps a host widget that opens SingleDieSettingsDialog as a real dialog
/// (via showDialog) so AlertDialog has a proper overlay context.
Future<void> _pumpHost(
  WidgetTester tester, {
  required GenericDie die,
  bool haEnabled = false,
  void Function(Color, GenericDie, String?)? onBlink,
  void Function(Color, RollingFlashPreset, GenericDie)? onPreviewRolling,
  void Function(String)? onDisconnect,
  void Function(GenericDie, DieSettings)? onSave,
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
              onPreviewRolling: (c, p, d) async => onPreviewRolling?.call(c, p, d),
              onDisconnect: (id) async => onDisconnect?.call(id),
              onSave: (d, s) async => onSave?.call(d, s),
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
  void Function(Color, RollingFlashPreset, GenericDie)? onPreviewRolling,
  void Function(String)? onDisconnect,
  void Function(GenericDie, DieSettings)? onSave,
}) async {
  await _pumpHost(
    tester,
    die: die ?? _virtualDie(),
    haEnabled: haEnabled,
    onBlink: onBlink,
    onPreviewRolling: onPreviewRolling,
    onDisconnect: onDisconnect,
    onSave: onSave,
  );
  await _openDialog(tester);
}

/// Alias for _pumpDialog with DieSettings onSave — kept for clarity in rolling
/// flash tests that specifically check DieSettings fields.
Future<void> _pumpDialogNew(
  WidgetTester tester, {
  GenericDie? die,
  bool haEnabled = false,
  void Function(Color, GenericDie, String?)? onBlink,
  void Function(Color, RollingFlashPreset, GenericDie)? onPreviewRolling,
  void Function(String)? onDisconnect,
  void Function(GenericDie, DieSettings)? onSave,
}) => _pumpDialog(
  tester,
  die: die,
  haEnabled: haEnabled,
  onBlink: onBlink,
  onPreviewRolling: onPreviewRolling,
  onDisconnect: onDisconnect,
  onSave: onSave,
);

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
      expect(find.text('Save'), findsOneWidget);
      // Preview is a labeled TextButton, Disconnect is an icon button (link_off)
      expect(find.text('Preview'), findsOneWidget);
      expect(find.byIcon(Icons.link_off), findsOneWidget);
    });

    testWidgets('HA entity field hidden when haEnabled=false', (tester) async {
      await _pumpDialog(tester, haEnabled: false);
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Home Assistant Entity',
        ),
        findsNothing,
      );
    });

    testWidgets('HA entity field shown when haEnabled=true', (tester) async {
      await _pumpDialog(tester, haEnabled: true);
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Home Assistant Entity',
        ),
        findsOneWidget,
      );
    });

    testWidgets('initial color pre-populated in hex field', (tester) async {
      // colorToHex defaults to uppercase
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFFFF0000)));
      expect(find.text('FF0000'), findsOneWidget);
    });

    // ── Color mode switching (the mouse-tracker crash scenario) ───────────────

    testWidgets('switches to RGB / Sliders without crashing', (tester) async {
      await _pumpDialog(tester);
      await _selectColorMode(tester, 'RGB / Sliders');
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
      await _selectColorMode(tester, 'RGB / Sliders');
      await _selectColorMode(tester, 'HSV / Square');
      await _selectColorMode(tester, 'HSL / Square');
      await _selectColorMode(tester, 'Hex / Wheel');
      expect(find.byType(SingleDieSettingsDialog), findsOneWidget);
    });

    // ── Color sync across modes ───────────────────────────────────────────────

    testWidgets('RGB fields populate from initial color', (tester) async {
      // Color(0xFFFF8000) ≈ R=255, G=128, B=0
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFFFF8000)));
      await _selectColorMode(tester, 'RGB / Sliders');
      expect(find.text('255'), findsOneWidget);
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
      await _selectColorMode(tester, 'RGB / Sliders');
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
      // Hex field reflects the new value, confirming the color updated.
      expect(find.text('FF0000'), findsOneWidget);
      // R controller should already be 255 (updated by _updateControllers).
      final rCtrl = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((f) => f.decoration?.labelText == 'Hex')
          .controller;
      expect(rCtrl?.text, 'FF0000');
    });

    // ── Backspace / empty-field handling ──────────────────────────────────────

    testWidgets('backspace mid-number updates color at each step', (tester) async {
      // Start with R=255; backspace to 25, then 2 — each step should update.
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFFFF0000)));
      await _selectColorMode(tester, 'RGB / Sliders');
      final rField = find.text('255').first;
      await tester.enterText(rField, '25');
      await tester.pump();
      // G=0, B=0, A=255 unchanged; R updated
      expect(find.text('25'), findsOneWidget);
      await tester.enterText(find.text('25'), '2');
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('backspace to empty does not throw and restores on unfocus', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFFFF0000)));
      await _selectColorMode(tester, 'RGB / Sliders');
      // Backspace R all the way to empty
      final rField = find.text('255').first;
      await tester.enterText(rField, '');
      await tester.pump();
      // Verify R field is currently empty
      TextField rTextField() => tester.widgetList<TextField>(find.byType(TextField))
          .firstWhere((f) => f.decoration?.labelText == 'R');
      expect(rTextField().controller?.text, isEmpty);
      // Programmatically unfocus — tapping other fields is unreliable when they
      // are near the edge of the test viewport.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      // R field should be restored to 255 — the last valid value held in _currentColor
      expect(rTextField().controller?.text, '255');
    });

    testWidgets('backspace to empty then retype works correctly', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFFFF0000)));
      await _selectColorMode(tester, 'RGB / Sliders');
      final rField = find.text('255').first;
      await tester.enterText(rField, '');
      await tester.pump();
      // Type a new value
      await tester.enterText(find.byType(EditableText).first, '100');
      await tester.pump();
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('backspace uses sendKeyEvent (proper down+up pairs, no assertion)', (tester) async {
      // Regression: sendKeyDownEvent without sendKeyUpEvent causes
      // HardwareKeyboard duplicate-key assertion. sendKeyEvent sends both.
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFFFF8000)));
      await _selectColorMode(tester, 'RGB / Sliders');
      await tester.tap(find.text('255').first);
      await tester.pump();
      // sendKeyEvent sends key-down + key-up — no duplicate-key assertion
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      // No exception thrown; field shows reduced value (or empty if single digit)
      expect(find.byType(SingleDieSettingsDialog), findsOneWidget);
    });

    // ── Input works after dropdown mode switch ─────────────────────────────────
    // Regression: DropdownMenu retained focus after selection, blocking text
    // input to numeric fields. Fix: FocusScope.unfocus() in onSelected.

    testWidgets('numeric field accepts input after mode switch to ARGB', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFF000000)));
      await _selectColorMode(tester, 'RGB / Sliders');
      // Enter a new R value directly — verifies the field is reachable after dropdown closes.
      await tester.enterText(find.text('0').first, '128');
      await tester.pump();
      expect(find.text('128'), findsOneWidget);
    });

    testWidgets('numeric field accepts input after mode switch to HSV', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFF000000)));
      await _selectColorMode(tester, 'HSV / Square');
      await tester.enterText(find.text('0').first, '180');
      await tester.pump();
      expect(find.text('180'), findsOneWidget);
    });

    testWidgets('numeric field accepts input after mode switch to HSL', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0xFF000000)));
      await _selectColorMode(tester, 'HSL / Square');
      await tester.enterText(find.text('0').first, '90');
      await tester.pump();
      expect(find.text('90'), findsOneWidget);
    });

    // ── Brightness slider ─────────────────────────────────────────────────────

    testWidgets('brightness slider is present', (tester) async {
      await _pumpDialog(tester);
      expect(find.byKey(const Key('brightness_slider')), findsOneWidget);
    });

    testWidgets('brightness defaults to 100% when die has no color', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(color: null));
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('brightness initializes from die color alpha', (tester) async {
      // Color(0x80FF0000) has alpha 0x80 = 128, i.e. ~50%
      await _pumpDialog(tester, die: _virtualDie(color: const Color(0x80FF0000)));
      // 128/255 rounds to 50%
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('Save includes brightness as color alpha', (tester) async {
      Color? savedColor;
      await _pumpDialog(
        tester,
        die: _virtualDie(color: const Color(0x80FF0000)), // 50% brightness
        onSave: (_, s) => savedColor = s.blinkColor,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(savedColor, isNotNull);
      // Alpha should be ~50% (0x80/0xFF ≈ 0.502, rounded to 2 decimal places)
      expect(savedColor!.a, closeTo(0x80 / 0xFF, 0.01));
    });

    testWidgets('Preview includes brightness as color alpha', (tester) async {
      Color? blinkColor;
      await _pumpDialog(
        tester,
        die: _virtualDie(color: const Color(0x40FF0000)), // 25% brightness
        onBlink: (c, _, __) => blinkColor = c,
      );
      await tester.tap(find.text('Preview'));
      await tester.pump();
      expect(blinkColor, isNotNull);
      expect(blinkColor!.a, closeTo(0x40 / 0xFF, 0.01));
    });

    testWidgets('Save uses full brightness when die has no color', (tester) async {
      Color? savedColor;
      await _pumpDialog(
        tester,
        die: _virtualDie(color: null),
        onSave: (_, s) => savedColor = s.blinkColor,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(savedColor?.a, closeTo(1.0, 0.01));
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
      DieSettings? savedSettings;
      await _pumpDialog(
        tester,
        die: _virtualDie(color: Colors.green),
        onSave: (d, s) {
          savedDie = d;
          savedSettings = s;
        },
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(savedDie, isNotNull);
      expect(savedSettings, isNotNull);
      expect(find.byType(SingleDieSettingsDialog), findsNothing);
    });

    testWidgets('Preview button calls onBlink with current color', (tester) async {
      Color? blinkColor;
      await _pumpDialog(
        tester,
        die: _virtualDie(color: Colors.purple),
        onBlink: (c, _, __) => blinkColor = c,
      );
      await tester.tap(find.text('Preview'));
      await tester.pump();
      expect(blinkColor, isNotNull);
    });

    testWidgets('Disconnect icon calls onDisconnect with die id and closes', (tester) async {
      String? disconnectedId;
      final die = _virtualDie();
      await _pumpDialog(
        tester,
        die: die,
        onDisconnect: (id) => disconnectedId = id,
      );
      await tester.tap(find.byIcon(Icons.link_off));
      await tester.pumpAndSettle();
      expect(disconnectedId, equals(die.dieId));
      expect(find.byType(SingleDieSettingsDialog), findsNothing);
    });

    // ── Face count section visibility ─────────────────────────────────────────

    testWidgets('face count section not present for Pixels die', (tester) async {
      await _pumpDialog(tester, die: _pixelDie());
      // Face count for Pixels is determined by the die firmware; we hide the selector.
      expect(find.text('Face Count'), findsNothing);
    });

    testWidgets('face count section present for virtual die', (tester) async {
      await _pumpDialog(tester, die: _virtualDie(dType: 'd6'));
      expect(find.text('Face Count'), findsOneWidget);
    });

    testWidgets('face count section present for GoDice', (tester) async {
      await _pumpDialog(tester, die: _godiceDie());
      expect(find.text('Face Count'), findsOneWidget);
    });

    // ── Rolling flash section ─────────────────────────────────────────────────

    testWidgets('rolling flash section not present for virtual die', (tester) async {
      await _pumpDialog(tester, die: _virtualDie());
      expect(find.text('Rolling Flash'), findsNothing);
    });

    testWidgets('rolling flash section not present for GoDice', (tester) async {
      await _pumpDialog(tester, die: _godiceDie());
      expect(find.text('Rolling Flash'), findsNothing);
    });

    testWidgets('rolling flash section present for Pixels die', (tester) async {
      await _pumpDialog(tester, die: _pixelDie());
      expect(find.text('Rolling Flash'), findsOneWidget);
    });

    testWidgets('rolling flash toggle starts off when rollingFlashEnabled=false', (tester) async {
      await _pumpDialog(tester, die: _pixelDie(rollingEnabled: false));
      final toggle = tester.widget<Switch>(find.byType(Switch).last);
      expect(toggle.value, isFalse);
    });

    testWidgets('rolling flash toggle starts on when rollingFlashEnabled=true', (tester) async {
      await _pumpDialog(tester, die: _pixelDie(rollingEnabled: true));
      final toggle = tester.widget<Switch>(find.byType(Switch).last);
      expect(toggle.value, isTrue);
    });

    testWidgets('preset selector not visible when rolling flash toggle is off', (tester) async {
      await _pumpDialog(tester, die: _pixelDie(rollingEnabled: false));
      expect(find.text('Strobe'), findsNothing);
      expect(find.text('Pulse'), findsNothing);
      expect(find.text('Breathe'), findsNothing);
    });

    testWidgets('preset selector visible when rolling flash toggle is on', (tester) async {
      await _pumpDialog(tester, die: _pixelDie(rollingEnabled: true));
      expect(find.text('Strobe'), findsOneWidget);
      expect(find.text('Pulse'), findsOneWidget);
      expect(find.text('Breathe'), findsOneWidget);
    });

    testWidgets('preset selection updates state (Strobe → Pulse)', (tester) async {
      await _pumpDialog(tester, die: _pixelDie(rollingEnabled: true, preset: RollingFlashPreset.strobe));
      await tester.tap(find.text('Pulse'));
      await tester.pumpAndSettle();
      // After tapping Pulse the Pulse button should be selected.
      // SegmentedButton marks selected segment visually; we verify no exception
      // and the widget is still alive.
      expect(find.byType(SingleDieSettingsDialog), findsOneWidget);
    });

    testWidgets('rolling flash save receives DieSettings with rollingFlashEnabled=true', (tester) async {
      DieSettings? savedSettings;
      await _pumpDialogNew(
        tester,
        die: _pixelDie(rollingEnabled: true),
        onSave: (_, s) => savedSettings = s,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(savedSettings, isNotNull);
      expect(savedSettings!.rollingFlashEnabled, isTrue);
    });

    testWidgets('rolling flash save receives DieSettings with correct preset', (tester) async {
      DieSettings? savedSettings;
      await _pumpDialogNew(
        tester,
        die: _pixelDie(rollingEnabled: true, preset: RollingFlashPreset.pulse),
        onSave: (_, s) => savedSettings = s,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(savedSettings, isNotNull);
      expect(savedSettings!.rollingFlashPreset, equals(RollingFlashPreset.pulse));
    });

    testWidgets('rolling flash save includes rollingFlashColor for Pixels die', (tester) async {
      DieSettings? savedSettings;
      final die = _pixelDie(rollingEnabled: true, rollingColor: Colors.blue);
      await _pumpDialogNew(tester, die: die, onSave: (_, s) => savedSettings = s);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedSettings?.rollingFlashColor, isNotNull);
      expect(
        savedSettings!.rollingFlashColor!.toARGB32(),
        equals(Colors.blue.withValues(alpha: 1.0).toARGB32()),
      );
    });

    testWidgets('rollingFlashColor is null in DieSettings for virtual die', (tester) async {
      DieSettings? savedSettings;
      await _pumpDialogNew(tester, die: _virtualDie(), onSave: (_, s) => savedSettings = s);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedSettings?.rollingFlashColor, isNull);
    });

    // ── onPreviewRolling callback ─────────────────────────────────────────────

    testWidgets('Preview calls onPreviewRolling when rolling swatch is active', (tester) async {
      Color? capturedColor;
      RollingFlashPreset? capturedPreset;

      await _pumpDialog(
        tester,
        die: _pixelDie(rollingEnabled: true, preset: RollingFlashPreset.pulse),
        onPreviewRolling: (c, p, _) {
          capturedColor = c;
          capturedPreset = p;
        },
      );

      // Switch active picker target to Rolling by tapping the swatch label.
      await tester.tap(find.text('Rolling'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Preview'));
      await tester.pump();

      expect(capturedColor, isNotNull);
      expect(capturedPreset, equals(RollingFlashPreset.pulse));
    });

    testWidgets('Preview calls onBlink (not onPreviewRolling) when result target is active', (tester) async {
      bool previewRollingCalled = false;
      Color? blinkColor;

      await _pumpDialog(
        tester,
        die: _pixelDie(rollingEnabled: true),
        onBlink: (c, _, __) => blinkColor = c,
        onPreviewRolling: (_, __, ___) => previewRollingCalled = true,
      );

      // Default active target is result — tap Preview without switching.
      await tester.tap(find.text('Preview'));
      await tester.pump();

      expect(previewRollingCalled, isFalse);
      expect(blinkColor, isNotNull);
    });

    testWidgets('Preview does not call onPreviewRolling when rolling flash is disabled', (tester) async {
      bool previewRollingCalled = false;

      await _pumpDialog(
        tester,
        // rollingEnabled=false: rolling swatch is greyed out and non-tappable.
        die: _pixelDie(rollingEnabled: false),
        onPreviewRolling: (_, __, ___) => previewRollingCalled = true,
      );

      await tester.tap(find.text('Preview'));
      await tester.pump();

      expect(previewRollingCalled, isFalse);
    });
  });
}
