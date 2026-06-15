import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/repositories/dddice_repository.dart';
import 'package:roll_feathers/services/dddice/dddice_config_service.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen_vm.dart';

class MockAppSettingsScreenViewModel extends Mock implements AppSettingsScreenViewModel {}

// ─── helpers ──────────────────────────────────────────────────────────────────

const _unauthConfig = DddiceConfig();
const _authenticatedConfig = DddiceConfig(
  enabled: true,
  token: 'tok',
  roomSlug: 'my-room',
  roomName: 'My Room',
  themeId: 'theme-id',
  themeName: 'My Theme',
);

MockAppSettingsScreenViewModel _mockVm(DddiceConfig config) {
  final vm = MockAppSettingsScreenViewModel();
  when(() => vm.getDddiceConfig()).thenReturn(config);
  when(() => vm.saveDddiceConfig(any())).thenAnswer((_) async {});
  when(() => vm.dddiceListRooms()).thenAnswer((_) async => []);
  when(() => vm.dddiceListThemes()).thenAnswer((_) async => []);
  when(() => vm.dddiceSignInAsGuest()).thenAnswer((_) async => false);
  when(() => vm.dddiceStartActivation()).thenAnswer((_) async => null);
  when(() => vm.dddiceCancelActivation()).thenAnswer((_) async {});
  when(() => vm.dddiceSignOut()).thenAnswer((_) async {});
  when(() => vm.activationError).thenReturn(null);
  // ChangeNotifier methods needed by the widget's addListener/removeListener
  when(() => vm.addListener(any())).thenReturn(null);
  when(() => vm.removeListener(any())).thenReturn(null);
  return vm;
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// ─── tests ────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const DddiceConfig());
  });

  // ─── unauthenticated state ───────────────────────────────────────────────

  group('DddiceSettingsContent — unauthenticated', () {
    testWidgets('shows both auth buttons when not signed in', (tester) async {
      await tester.pumpWidget(_wrap(DddiceSettingsContent(vm: _mockVm(_unauthConfig))));
      expect(find.text('Sign in with dddice'), findsOneWidget);
      expect(find.text('Use guest account'), findsOneWidget);
    });

    testWidgets('does not show enable toggle when not signed in', (tester) async {
      await tester.pumpWidget(_wrap(DddiceSettingsContent(vm: _mockVm(_unauthConfig))));
      expect(find.text('Enable dddice'), findsNothing);
    });
  });

  // ─── activating state ────────────────────────────────────────────────────

  group('DddiceSettingsContent — activating', () {
    testWidgets('shows copy button and activation code after sign-in tapped', (tester) async {
      final vm = _mockVm(_unauthConfig);
      when(() => vm.dddiceStartActivation()).thenAnswer(
        (_) async => const DddiceActivationCode(code: 'ABC123', secret: 'sec'),
      );

      await tester.pumpWidget(_wrap(DddiceSettingsContent(vm: vm)));
      await tester.tap(find.text('Sign in with dddice'));
      await tester.pump(); // trigger setState / async

      expect(find.text('ABC123'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.text('Open dddice.com/activate'), findsOneWidget);
    });

    testWidgets('copy button writes code to clipboard', (tester) async {
      final vm = _mockVm(_unauthConfig);
      when(() => vm.dddiceStartActivation()).thenAnswer(
        (_) async => const DddiceActivationCode(code: 'XYZ789', secret: 'sec'),
      );

      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(_wrap(DddiceSettingsContent(vm: vm)));
      await tester.tap(find.text('Sign in with dddice'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      expect(clipboardText, equals('XYZ789'));
    });

    testWidgets('cancel calls dddiceCancelActivation and returns to unauthenticated', (tester) async {
      final vm = _mockVm(_unauthConfig);
      when(() => vm.dddiceStartActivation()).thenAnswer(
        (_) async => const DddiceActivationCode(code: 'ABC123', secret: 'sec'),
      );

      await tester.pumpWidget(_wrap(DddiceSettingsContent(vm: vm)));
      await tester.tap(find.text('Sign in with dddice'));
      await tester.pump();
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      verify(() => vm.dddiceCancelActivation()).called(1);
      expect(find.text('Sign in with dddice'), findsOneWidget);
    });
  });

  // ─── authenticated state ─────────────────────────────────────────────────

  group('DddiceSettingsContent — authenticated', () {
    testWidgets('shows enable toggle and sign-out when signed in', (tester) async {
      await tester.pumpWidget(_wrap(DddiceSettingsContent(vm: _mockVm(_authenticatedConfig))));
      await tester.pump();
      expect(find.text('Enable dddice'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('sign-out calls dddiceSignOut on VM', (tester) async {
      final vm = _mockVm(_authenticatedConfig);
      await tester.pumpWidget(_wrap(DddiceSettingsContent(vm: vm)));
      await tester.pump();
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      verify(() => vm.dddiceSignOut()).called(1);
    });

    testWidgets('room picker selected item shows slug when fetched room has empty name', (tester) async {
      const configWithSlugRoom = DddiceConfig(
        enabled: true, token: 'tok', roomSlug: 'slug-only', roomName: '', themeId: 'th', themeName: 'T',
      );
      final vm = _mockVm(configWithSlugRoom);
      when(() => vm.dddiceListRooms()).thenAnswer(
        (_) async => [const DddiceRoom(slug: 'slug-only', name: '')],
      );

      await tester.pumpWidget(_wrap(DddiceSettingsContent(vm: vm)));
      await tester.pumpAndSettle();

      expect(find.text('slug-only'), findsWidgets);
    });

    testWidgets('room picker selected item shows name when room has a name', (tester) async {
      const configWithNamedRoom = DddiceConfig(
        enabled: true, token: 'tok', roomSlug: 'the-arena', roomName: 'The Arena', themeId: 'th', themeName: 'T',
      );
      final vm = _mockVm(configWithNamedRoom);
      when(() => vm.dddiceListRooms()).thenAnswer(
        (_) async => [const DddiceRoom(slug: 'the-arena', name: 'The Arena')],
      );

      await tester.pumpWidget(_wrap(DddiceSettingsContent(vm: vm)));
      await tester.pumpAndSettle();

      expect(find.text('The Arena'), findsWidgets);
    });
  });
}
