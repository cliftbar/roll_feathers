import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels_profile_transfer.dart';
import 'package:roll_feathers/services/pixels/pixel_profile_store.dart';
import 'package:roll_feathers/testing/pixels_die_simulator.dart';
import 'package:roll_feathers/ui/pixels/pixels_profile_editor_screen.dart';
import 'package:roll_feathers/ui/pixels/pixels_profiles_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: child);

PixelProfile _simpleProfile({String id = 'p1', String name = 'Test'}) => PixelProfile(
  id: id,
  name: name,
  brightness: 200,
  animations: [PixelAnimationSimple(durationMs: 500, color: const PixelColor(255, 0, 0))],
  rules: [PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)])],
);

// ─── PixelsProfileEditorScreen ────────────────────────────────────────────────

void main() {
  group('PixelsProfileEditorScreen', () {
    testWidgets('renders profile name field', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile())));
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget); // name field
    });

    testWidgets('shows animations section with existing animation', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile())));
      expect(find.text('Animations'), findsOneWidget);
      expect(find.text('Animation 1: Solid Flash'), findsOneWidget);
    });

    testWidgets('shows rules section with existing rule', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile())));
      expect(find.text('Rules'), findsOneWidget);
      expect(find.text('When: Rolled'), findsOneWidget);
    });

    testWidgets('Save button pops with updated profile', (tester) async {
      PixelProfile? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(ctx).push<PixelProfile>(
                MaterialPageRoute(
                  builder: (_) => PixelsProfileEditorScreen(profile: _simpleProfile()),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.name, 'Test');
    });

    testWidgets('add animation dialog opens and cancels', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile())));
      // Find and tap the Add button next to Animations
      final addButtons = find.text('Add');
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Edit Animation'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Back on editor screen, still 1 animation
      expect(find.text('Animation 1: Solid Flash'), findsOneWidget);
    });

    testWidgets('add rule dialog opens and cancels', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile())));
      final addButtons = find.text('Add');
      await tester.tap(addButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('Edit Rule'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Rules'), findsOneWidget);
    });

    testWidgets('animation editor OK adds animation', (tester) async {
      final profile = PixelProfile(
        id: 'p2',
        name: 'Empty',
        animations: [],
        rules: [],
      );
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile)));

      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();

      expect(find.text('Edit Animation'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Animation 1: Solid Flash'), findsOneWidget);
    });

    testWidgets('delete animation removes it from list', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile())));

      expect(find.text('Animation 1: Solid Flash'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Animation 1: Solid Flash'), findsNothing);
      expect(find.text('No animations yet.'), findsOneWidget);
    });
  });

  // ─── PixelsProfilesScreen ──────────────────────────────────────────────────

  group('PixelsProfilesScreen', () {
    late PixelsDieSimulator sim;
    late PixelProfileStore store;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      sim = PixelsDieSimulator(name: 'TestDie');
      store = PixelProfileStore();
    });

    tearDown(() => sim.dispose());

    Widget _buildScreen() => _wrap(PixelsProfilesScreen(
      die: sim,
      dieName: 'TestDie',
      store: store,
    ));

    testWidgets('shows empty state when no profiles', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('No profiles yet.'), findsOneWidget);
    });

    testWidgets('shows profile in list after save', (tester) async {
      await store.upsert(_simpleProfile());
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Test'), findsOneWidget);
      expect(find.text('1 animation · 1 rule'), findsOneWidget);
    });

    testWidgets('shows die name in app bar', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Animations — TestDie'), findsOneWidget);
    });

    testWidgets('add button navigates to editor and returns profile', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Editor screen should be open
      expect(find.text('Edit Profile'), findsOneWidget);

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Profile should now appear
      expect(find.text('New Profile'), findsOneWidget);
    });

    testWidgets('delete profile shows confirmation dialog', (tester) async {
      await store.upsert(_simpleProfile());
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Open popup menu
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Profile'), findsOneWidget);
      expect(find.text('Delete "Test"?'), findsOneWidget);
    });

    testWidgets('cancel delete keeps profile', (tester) async {
      await store.upsert(_simpleProfile());
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Test'), findsOneWidget);
    });

    testWidgets('confirm delete removes profile', (tester) async {
      await store.upsert(_simpleProfile());
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirm deletion (dialog has two "Delete" texts — the button)
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('No profiles yet.'), findsOneWidget);
    });
  });

  // ─── PixelProfileStore ────────────────────────────────────────────────────

  group('PixelProfileStore', () {
    late PixelProfileStore store;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      store = PixelProfileStore();
    });

    test('loadAll returns empty list initially', () async {
      expect(await store.loadAll(), isEmpty);
    });

    test('upsert inserts new profile', () async {
      await store.upsert(_simpleProfile());
      final all = await store.loadAll();
      expect(all.length, 1);
      expect(all.first.name, 'Test');
    });

    test('upsert updates existing profile by id', () async {
      await store.upsert(_simpleProfile(name: 'Original'));
      final updated = PixelProfile(
        id: 'p1',
        name: 'Updated',
        animations: [],
        rules: [],
      );
      await store.upsert(updated);
      final all = await store.loadAll();
      expect(all.length, 1);
      expect(all.first.name, 'Updated');
    });

    test('delete removes profile by id', () async {
      await store.upsert(_simpleProfile());
      await store.delete('p1');
      expect(await store.loadAll(), isEmpty);
    });

    test('saveAll round-trips multiple profiles', () async {
      final p1 = _simpleProfile(id: 'a', name: 'Alpha');
      final p2 = _simpleProfile(id: 'b', name: 'Beta');
      await store.saveAll([p1, p2]);
      final all = await store.loadAll();
      expect(all.length, 2);
      expect(all.map((p) => p.name), containsAll(['Alpha', 'Beta']));
    });
  });
}
