import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Minimal fake VM ───────────────────────────────────────────────────────────

/// Stand-in for AppSettingsScreenViewModel, exposing only the fields the scan
/// button cares about. Using a simple ChangeNotifier avoids the full DI stack.
class _FakeScanVm extends ChangeNotifier {
  bool _bleEnabled = true;
  bool _scanning = false;

  bool bleIsEnabled() => _bleEnabled;
  bool get isScanning => _scanning;

  void startScan() {
    if (_scanning) return;
    _scanning = true;
    notifyListeners();
  }

  void endScan() {
    _scanning = false;
    notifyListeners();
  }

  void setBleEnabled(bool v) {
    _bleEnabled = v;
    notifyListeners();
  }
}

// ── Widget under test ─────────────────────────────────────────────────────────

/// Mirrors the exact scan button logic from DiceScreenWidget._DiceScreenWidgetState.
/// Keeping it in the test avoids pulling in the full DiceScreenWidget DI stack.
Widget _scanButtonWidget(_FakeScanVm vm) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            final bleOn = vm.bleIsEnabled();
            final scanning = vm.isScanning;
            return TextButton.icon(
              onPressed: bleOn && !scanning ? () => vm.startScan() : null,
              label: bleOn ? const Text('Scan') : const Text('BLE Disabled'),
              icon: scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : bleOn
                      ? const Icon(Icons.bluetooth_searching)
                      : const Icon(Icons.bluetooth_disabled),
            );
          },
        ),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Scan button idle state', () {
    testWidgets('shows bluetooth icon and Scan label when idle', (tester) async {
      final vm = _FakeScanVm();
      await tester.pumpWidget(_scanButtonWidget(vm));
      expect(find.byIcon(Icons.bluetooth_searching), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows BLE Disabled label and icon when BLE off', (tester) async {
      final vm = _FakeScanVm()..setBleEnabled(false);
      await tester.pumpWidget(_scanButtonWidget(vm));
      expect(find.text('BLE Disabled'), findsOneWidget);
      expect(find.byIcon(Icons.bluetooth_disabled), findsOneWidget);
    });

    testWidgets('button is enabled when BLE on and not scanning', (tester) async {
      final vm = _FakeScanVm();
      await tester.pumpWidget(_scanButtonWidget(vm));
      final btn = tester.widget<TextButton>(find.byType(TextButton));
      expect(btn.onPressed, isNotNull);
    });
  });

  group('Scan button active state', () {
    testWidgets('shows spinner immediately after scan starts (one pump)', (tester) async {
      final vm = _FakeScanVm();
      await tester.pumpWidget(_scanButtonWidget(vm));

      vm.startScan();
      await tester.pump(); // exactly one frame — do NOT pumpAndSettle

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.bluetooth_searching), findsNothing);
    });

    testWidgets('button is disabled while scanning', (tester) async {
      final vm = _FakeScanVm();
      await tester.pumpWidget(_scanButtonWidget(vm));

      vm.startScan();
      await tester.pump();

      final btn = tester.widget<TextButton>(find.byType(TextButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('spinner persists across multiple frames until scan ends', (tester) async {
      final vm = _FakeScanVm();
      await tester.pumpWidget(_scanButtonWidget(vm));

      vm.startScan();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // scan has not ended — spinner should still be showing
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Scan button race condition', () {
    testWidgets(
        'BUG REPRO: spinner never shown when startScan+endScan fire before a frame',
        (tester) async {
      // This test reproduces the real-world bug:
      //   bleRepository.scan() returns immediately (it just starts a background timer),
      //   so _scanInProgress flips true→false before Flutter renders any frame.
      //   Both notifyListeners() calls are batched into one rebuild showing isScanning=false.
      final vm = _FakeScanVm();
      await tester.pumpWidget(_scanButtonWidget(vm));

      // Simulate: notifyListeners(true) then notifyListeners(false) with no pump between
      vm.startScan(); // isScanning = true  → setState scheduled
      vm.endScan(); //   isScanning = false → setState scheduled (overwrites above)
      await tester.pump(); // only one frame built, with isScanning=false

      // The spinner was never visibly rendered — this documents the bug.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.bluetooth_searching), findsOneWidget);
    });

    testWidgets('FIX: spinner is shown when endScan is deferred (timer-based reset)',
        (tester) async {
      // After the fix, _scanInProgress is reset by a Timer (not in the finally block),
      // so the spinner appears on the first frame after startScan() and remains visible
      // until the timer fires. This test verifies the correct behavior.
      final vm = _FakeScanVm();
      await tester.pumpWidget(_scanButtonWidget(vm));

      vm.startScan(); // isScanning = true
      // Do NOT call vm.endScan() immediately — the timer fires later
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Now the scan period ends
      vm.endScan();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.bluetooth_searching), findsOneWidget);
    });
  });

  group('Scan button end state', () {
    testWidgets('spinner disappears and button re-enables after scan ends', (tester) async {
      final vm = _FakeScanVm();
      await tester.pumpWidget(_scanButtonWidget(vm));

      vm.startScan();
      await tester.pump();
      vm.endScan();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.bluetooth_searching), findsOneWidget);
      final btn = tester.widget<TextButton>(find.byType(TextButton));
      expect(btn.onPressed, isNotNull);
    });
  });
}
