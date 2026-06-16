// Drives the real (non-guest) dddice sign-in flow against a local
// DddiceMockServer instead of the live dddice.com API or a real account.
//
// Unlike the rest of the suite, the app's dddice base URL must be redirected
// to the mock *before* the binary is built, since DDDICE_BASE_URL is read as
// a compile-time dart-define (see lib/di/di.dart). Run this file on its own:
//
//   flutter test -d <device> --dart-define=INTEGRATION_TEST=true \
//       --dart-define=DDDICE_BASE_URL=http://127.0.0.1:18765/api/1.0 \
//       integration_test/dddice_real_auth_test.dart
//
// Not run on web: DddiceMockServer binds a dart:io socket, which web builds
// cannot do.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:roll_feathers/testing/dddice_mock_server.dart';

import 'helpers.dart';

const _mockPort = 18765;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('dddice real (non-guest) sign-in via local mock', () {
    late DddiceMockServer mock;

    setUpAll(() async {
      mock = DddiceMockServer();
      await mock.start(port: _mockPort);
    });

    tearDownAll(() => mock.close());

    testWidgets(
      'Sign in with dddice shows a code, then transitions to authenticated once completed',
      (tester) async {
        await startApp(tester);
        await openDddiceSettings(tester);

        expect(find.text('Sign in with dddice'), findsOneWidget);
        await tester.tap(find.text('Sign in with dddice'));
        // Plain bounded pump()s rather than pumpAndSettle(): if the macOS test
        // window loses focus, the engine throttles frame production and
        // pumpAndSettle's "wait until no frames are scheduled" loop can run
        // past its default 10-minute timeout instead of just running slower.
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 500));

        final codeFinder = find.byType(SelectableText);
        expect(codeFinder, findsOneWidget);
        final code = tester.widget<SelectableText>(codeFinder).data;
        expect(code, isNotEmpty);

        mock.completeActivation(code!, token: 'integration-test-token');

        // DddiceDomain polls every 5s by default; give it a couple of cycles.
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Sign in with dddice'), findsNothing);
        expect(find.text('Sign out'), findsOneWidget);
      },
      skip: kIsWeb,
    );
  });
}
