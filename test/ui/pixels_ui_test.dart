import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels_builtin_profiles.dart';
import 'package:roll_feathers/dice_sdks/pixels_patterns.dart';
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

    testWidgets('Keyframed type shows Pattern picker', (tester) async {
      registerBuiltinPatterns(kBuiltinPatterns);
      final profile = PixelProfile(
        id: 'k1', name: 'K',
        animations: [],
        rules: [],
      );
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile)));

      // Open animation editor
      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit Animation'), findsOneWidget);

      // Change type to Keyframed
      await tester.tap(find.text('Solid Flash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keyframed').last);
      await tester.pumpAndSettle();

      // Pattern picker label should be visible
      expect(find.text('Pattern'), findsOneWidget);
      // Duration field should be visible
      expect(find.text('Duration (ms)'), findsOneWidget);
    });

    testWidgets('Gradient Pattern type shows Pattern picker and Color Gradient', (tester) async {
      registerBuiltinPatterns(kBuiltinPatterns);
      final profile = PixelProfile(
        id: 'gp1', name: 'GP',
        animations: [],
        rules: [],
      );
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile)));

      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit Animation'), findsOneWidget);

      // Change type to Gradient Pattern
      await tester.tap(find.text('Solid Flash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gradient Pattern').last);
      await tester.pumpAndSettle();

      expect(find.text('Pattern'), findsOneWidget);
      expect(find.text('Color Gradient'), findsOneWidget);
    });

    testWidgets('Keyframed anim shows subtitle with pattern name', (tester) async {
      registerBuiltinPatterns(kBuiltinPatterns);
      final profile = PixelProfile(
        id: 'k2', name: 'K',
        animations: [
          PixelAnimationKeyframed(
            durationMs: 1500,
            pattern: kBuiltinPatterns.first,
          ),
        ],
        rules: [],
      );
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile)));
      await tester.pumpAndSettle();

      expect(find.text('Animation 1: Keyframed'), findsOneWidget);
      expect(find.textContaining(kBuiltinPatterns.first.name), findsOneWidget);
    });

    testWidgets('GradientPattern anim shows subtitle with pattern name', (tester) async {
      registerBuiltinPatterns(kBuiltinPatterns);
      final profile = PixelProfile(
        id: 'gp2', name: 'GP',
        animations: [
          PixelAnimationGradientPattern(
            durationMs: 2000,
            pattern: kBuiltinPatterns.first,
          ),
        ],
        rules: [],
      );
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile)));
      await tester.pumpAndSettle();

      expect(find.text('Animation 1: Gradient Pattern'), findsOneWidget);
      expect(find.textContaining(kBuiltinPatterns.first.name), findsOneWidget);
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

      // Built-ins fill the viewport; scroll past them to reach the My Profiles empty state.
      await tester.scrollUntilVisible(find.textContaining('No profiles yet.'), 50.0);
      expect(find.textContaining('No profiles yet.'), findsOneWidget);
    });

    testWidgets('shows profile in list after save', (tester) async {
      await store.upsert(_simpleProfile());
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Scroll past the built-in profiles to reach the My Profiles section.
      await tester.scrollUntilVisible(find.text('Test'), 50.0);
      expect(find.text('Test'), findsOneWidget);
      expect(find.text('1 animation · 1 rule'), findsOneWidget);
    });

    testWidgets('shows "on die" indicator after flash', (tester) async {
      final profile = _simpleProfile();
      await store.upsert(profile);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Scroll until 'Test' card is built, then ensureVisible so the full tile is on screen.
      await tester.scrollUntilVisible(find.text('Test'), 50.0);
      final testCard = find.ancestor(of: find.text('Test'), matching: find.byType(Card)).first;
      final uploadInTestTile = find.descendant(of: testCard, matching: find.byIcon(Icons.upload));
      await tester.ensureVisible(uploadInTestTile);
      await tester.pumpAndSettle();

      // Not yet flashed — no "on die" text
      expect(find.text('on die'), findsNothing);

      await tester.tap(uploadInTestTile);
      await tester.pumpAndSettle();

      // After flash the indicator appears.
      expect(find.text('on die'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows die name in app bar', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Animations — TestDie'), findsOneWidget);
    });

    testWidgets('add button shows preset picker then editor, saves profile', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Tap + → preset picker bottom sheet
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Choose a starting point'), findsOneWidget);

      // Pick "Blank profile" — sheet has its own Scrollable; scroll it specifically.
      final sheetScrollable = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(find.text('Blank profile'), 50.0, scrollable: sheetScrollable);
      await tester.tap(find.text('Blank profile'));
      await tester.pumpAndSettle();

      // Editor screen opens
      expect(find.text('Edit Profile'), findsOneWidget);

      // Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Profile now listed — scroll past built-ins to reach My Profiles.
      await tester.scrollUntilVisible(find.text('New Profile'), 50.0);
      expect(find.text('New Profile'), findsOneWidget);
    });

    testWidgets('add from preset creates profile with preset name', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Choose "High Low" preset — scope to the sheet because the main screen also
      // has a "High Low" built-in tile behind the modal.
      await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('High Low'),
      ));
      await tester.pumpAndSettle();

      // Editor opens with the preset name pre-filled
      expect(find.text('High Low'), findsWidgets); // name field + app bar tile
      expect(find.text('Edit Profile'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('High Low'), findsOneWidget);
    });

    testWidgets('delete profile shows confirmation dialog', (tester) async {
      await store.upsert(_simpleProfile());
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Scroll until the more_vert popup menu in the Test card is fully on screen.
      await tester.scrollUntilVisible(find.text('Test'), 50.0);
      final testCard = find.ancestor(of: find.text('Test'), matching: find.byType(Card)).first;
      final moreVert = find.descendant(of: testCard, matching: find.byIcon(Icons.more_vert));
      await tester.ensureVisible(moreVert);
      await tester.pumpAndSettle();
      await tester.tap(moreVert);
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

      await tester.scrollUntilVisible(find.text('Test'), 50.0);
      final testCard = find.ancestor(of: find.text('Test'), matching: find.byType(Card)).first;
      final moreVert = find.descendant(of: testCard, matching: find.byIcon(Icons.more_vert));
      await tester.ensureVisible(moreVert);
      await tester.pumpAndSettle();
      await tester.tap(moreVert);
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

      await tester.scrollUntilVisible(find.text('Test'), 50.0);
      final testCard = find.ancestor(of: find.text('Test'), matching: find.byType(Card)).first;
      final moreVert = find.descendant(of: testCard, matching: find.byIcon(Icons.more_vert));
      await tester.ensureVisible(moreVert);
      await tester.pumpAndSettle();
      await tester.tap(moreVert);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirm deletion (dialog has two "Delete" texts — the button)
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.textContaining('No profiles yet.'), 50.0);
      expect(find.textContaining('No profiles yet.'), findsOneWidget);
    });

    testWidgets('tapping built-in profile expands to show animation rows', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Tap the first built-in profile's ExpansionTile header to expand it.
      await tester.tap(find.text(kBuiltinProfiles.first.name).first);
      await tester.pumpAndSettle();

      // First rule of Default Profile is HelloGoodbye → "Hello"
      expect(find.text('Hello'), findsOneWidget);
      expect(find.byTooltip('Preview: Hello'), findsOneWidget);
    });

    testWidgets('tapping user profile expands to show animation rows', (tester) async {
      await store.upsert(_simpleProfile());
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Test'), 50.0);
      await tester.ensureVisible(find.text('Test'));
      await tester.pumpAndSettle();
      // Tap the title to expand the tile.
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      // _simpleProfile() has one Rolled rule → label "Rolled · any face"
      expect(find.text('Rolled · any face'), findsOneWidget);
      expect(find.byTooltip('Preview: Rolled · any face'), findsOneWidget);
    });

    testWidgets('collapsing Built-in Profiles section hides profile list', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Built-in profiles are visible initially.
      expect(find.text(kBuiltinProfiles.first.name), findsOneWidget);

      // Tap the section header to collapse.
      await tester.tap(find.text('Built-in Profiles'));
      await tester.pumpAndSettle();

      // Built-in profile tiles should be gone.
      expect(find.text(kBuiltinProfiles.first.name), findsNothing);
    });

    testWidgets('collapsing My Profiles section hides profile list', (tester) async {
      await store.upsert(_simpleProfile());
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Scroll to My Profiles section header and collapse it.
      await tester.scrollUntilVisible(find.text('My Profiles'), 50.0);
      await tester.ensureVisible(find.text('My Profiles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Profiles'));
      await tester.pumpAndSettle();

      // User profile should no longer be in the tree.
      expect(find.text('Test'), findsNothing);
    });

    testWidgets('status banner appears above scroll view, not as a sliver', (tester) async {
      await store.upsert(_simpleProfile());
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Scroll past the built-ins to the user profile.
      await tester.scrollUntilVisible(find.text('Test'), 50.0);
      final testCard = find.ancestor(of: find.text('Test'), matching: find.byType(Card)).first;
      final uploadBtn = find.descendant(of: testCard, matching: find.byIcon(Icons.upload));
      await tester.ensureVisible(uploadBtn);
      await tester.pumpAndSettle();

      // Record scroll position before flashing.
      final scrollBefore = tester
          .firstWidget<CustomScrollView>(find.byType(CustomScrollView))
          .controller
          ?.offset;

      await tester.tap(uploadBtn);
      await tester.pumpAndSettle();

      // Status message should appear.
      expect(find.textContaining('flashed to die'), findsOneWidget);

      // Scroll position must be unchanged (status is outside the scroll view).
      final scrollAfter = tester
          .firstWidget<CustomScrollView>(find.byType(CustomScrollView))
          .controller
          ?.offset;
      expect(scrollAfter, equals(scrollBefore));
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
