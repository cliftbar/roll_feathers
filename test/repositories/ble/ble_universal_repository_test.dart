import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:universal_ble/universal_ble.dart';

import 'package:roll_feathers/repositories/ble/ble_universal_repository.dart';

import '../../test_util.dart';

/// Test subclass that overrides _doConnect to always throw, simulating a
/// platform-level connection failure (e.g. GATT error 133, CBError).
/// Requires Fix 3's @protected _doConnect() extraction to compile.
class _FailingConnectRepo extends BleUniversalRepository {
  @override
  Future<void> _doConnect(String deviceId) =>
      Future.error(Exception('GATT 133 — simulated connect failure'));
}

void main() {
  setupLogger(Level.FINE);

  group('BleUniversalRepository', () {
    // Test B — _connectDevice re-adds device to _pendingConnect on failure
    //
    // Expected to FAIL before Fix 3 (re-add to _pendingConnect on catch),
    // passes after.
    test('B: failed _connectDevice re-adds device to _pendingConnect for retry', () async {
      final repo = _FailingConnectRepo();

      final fakeBleDevice = BleDevice(deviceId: 'fake-die-id', name: 'Fake GoDice');

      // Calling connectDeviceForTesting directly simulates what happens when
      // the scan timer fires and calls _connectDevice for a pending device.
      await repo.connectDeviceForTesting(fakeBleDevice);

      expect(
        repo.pendingConnectForTesting.any((d) => d.deviceId == 'fake-die-id'),
        isTrue,
        reason: '_connectDevice should re-add device to _pendingConnect on failure '
            'so _stopScanAndConnect() can retry it at end of scan window',
      );
    });
  });
}
