import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_patterns.dart';
import 'package:roll_feathers/domains/pixel_profile_domain.dart';
import 'package:roll_feathers/repositories/pixels/pixel_profile_repository.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/testing/pixels_die_simulator.dart';
import 'package:roll_feathers/ui/pixels/pixels_profile_editor_screen.dart';
import 'package:roll_feathers/ui/pixels/pixels_profiles_screen.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: child);

PixelProfile _simpleProfile({String id = 'p1', String name = 'Test'}) => PixelProfile(
  id: id,
  name: name,
  brightness: 200,
  animations: [PixelAnimationSimple(durationMs: 500, color: const PixelColor(255, 0, 0))],
  rules: [PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)])],
);

/// In-memory [PixelProfileRepository] so widget tests need no real storage.
class _FakeProfileRepo implements PixelProfileRepository {
  final List<PixelProfile> items = [];
  @override
  Future<List<PixelProfile>> loadAll() async => List.of(items);
  @override
  Future<void> saveAll(List<PixelProfile> profiles) async => items
    ..clear()
    ..addAll(profiles);
  @override
  Future<void> upsert(PixelProfile profile) async {
    final i = items.indexWhere((e) => e.id == profile.id);
    if (i >= 0) {
      items[i] = profile;
    } else {
      items.add(profile);
    }
  }
  @override
  Future<void> delete(String id) async => items.removeWhere((e) => e.id == id);
}

PixelProfileDomain _domain([PixelProfileRepository? repo]) =>
    PixelProfileDomain(repo ?? _FakeProfileRepo());

// ─── PixelsProfileEditorScreen ────────────────────────────────────────────────

void main() {
  group('PixelsProfileEditorScreen', () {
    testWidgets('renders profile name field', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain())));
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget); // name field
    });

    testWidgets('shows animations section with existing animation', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain())));
      expect(find.text('Animations'), findsOneWidget);
      expect(find.text('Animation 1: Solid Flash'), findsOneWidget);
    });

    testWidgets('shows rules section with existing rule', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain())));
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
                  builder: (_) => PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain()),
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
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain())));
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
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain())));
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
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile, domain: _domain())));

      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();

      expect(find.text('Edit Animation'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Animation 1: Solid Flash'), findsOneWidget);
    });

    testWidgets('delete animation removes it from list', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain())));

      expect(find.text('Animation 1: Solid Flash'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Animation 1: Solid Flash'), findsNothing);
      expect(find.text('No animations yet.'), findsOneWidget);
    });

    testWidgets('Import opens built-in animation picker and adds the chosen one', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain())));

      // Starts with the single seed animation only.
      expect(find.text('Animation 1: Solid Flash'), findsOneWidget);
      expect(find.textContaining('Animation 2:'), findsNothing);

      // Open the import sheet.
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.text('Import an animation'), findsOneWidget);
      expect(find.text('Default Profile'), findsOneWidget);

      // Expand the Rainbow built-in (3 Rainbow animations) and import one.
      await tester.tap(find.text('Rainbow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rainbow').last);
      await tester.pumpAndSettle();

      // Sheet closes; a second animation now exists in the editor.
      expect(find.text('Import an animation'), findsNothing);
      expect(find.text('Animation 2: Rainbow'), findsOneWidget);
      // Original seed animation is untouched.
      expect(find.text('Animation 1: Solid Flash'), findsOneWidget);
    });

    testWidgets('editing a Color Cycle preserves its custom gradient and animFlags', (tester) async {
      final purple = PixelGradient(const [
        (0, PixelColor(0, 0, 255)),
        (400, PixelColor(229, 168, 245)),
        (500, PixelColor(94, 48, 151)),
        (700, PixelColor(159, 99, 169)),
        (1000, PixelColor(0, 0, 255)),
      ]);
      final cycle = PixelAnimationCycle(
        animFlags: 2,
        durationMs: 3000,
        count: 5,
        fade: 127,
        intensity: 255,
        cyclesTimes10: 50,
        gradient: purple,
      );
      final profile = PixelProfile(
        id: 'c',
        name: 'cyc',
        animations: [cycle],
        rules: [PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)])],
      );

      PixelProfile? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              saved = await Navigator.of(ctx).push<PixelProfile>(
                MaterialPageRoute(builder: (_) => PixelsProfileEditorScreen(profile: profile, domain: _domain())),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Open the animation editor: the bespoke gradient must show as Custom,
      // not snap to Rainbow (the reported bug).
      await tester.tap(find.byIcon(Icons.edit).first);
      await tester.pumpAndSettle();
      expect(find.text('Custom (from source)'), findsOneWidget);
      expect(find.text('Rainbow'), findsNothing);

      // OK without changes, then Save, and inspect the popped profile.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final result = saved!.animations.single as PixelAnimationCycle;
      expect(result.animFlags, 2, reason: 'animFlags must survive the round-trip');
      expect(result.gradient.keyframes, purple.keyframes, reason: 'custom gradient must survive');
    });

    testWidgets('no preview button when no die is connected', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain())));
      expect(find.byIcon(Icons.play_circle_outline), findsNothing);
    });

    testWidgets('preview button appears with a die and sends a preview', (tester) async {
      final sim = PixelsDieSimulator(name: 'TestDie');
      addTearDown(sim.dispose);
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain(), dieService: PixelDieService(sim))));

      // One preview button for the single animation card.
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('Preview sent'), findsOneWidget);
    });

    testWidgets('animation dialog shows a Preview action when a die is connected', (tester) async {
      final sim = PixelsDieSimulator(name: 'TestDie');
      addTearDown(sim.dispose);
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain(), dieService: PixelDieService(sim))));

      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Preview'), findsOneWidget);
    });

    testWidgets('Keyframed type shows Pattern picker', (tester) async {
      registerBuiltinPatterns(kBuiltinPatterns);
      final profile = PixelProfile(
        id: 'k1', name: 'K',
        animations: [],
        rules: [],
      );
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile, domain: _domain())));

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

    testWidgets('Blink ID type shows its fields', (tester) async {
      final profile = PixelProfile(id: 'b1', name: 'B', animations: [], rules: []);
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile, domain: _domain())));

      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solid Flash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blink ID').last);
      await tester.pumpAndSettle();

      expect(find.text('Frames per blink'), findsOneWidget);
    });

    testWidgets('rule editor offers battery/idle/crooked/connection conditions', (tester) async {
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: _simpleProfile(), domain: _domain())));

      await tester.tap(find.text('Add').last); // rules section add
      await tester.pumpAndSettle();
      expect(find.text('Edit Rule'), findsOneWidget);

      // Open the condition dropdown.
      await tester.tap(find.text('Rolled (face landed)'));
      await tester.pumpAndSettle();
      expect(find.text('Battery state'), findsWidgets);
      expect(find.text('Idle (resting)'), findsWidgets);
      expect(find.text('Crooked (landed askew)'), findsWidgets);
      expect(find.text('Connection (BLE)'), findsWidgets);

      // Selecting Battery reveals its flag checkboxes.
      await tester.tap(find.text('Battery state').last);
      await tester.pumpAndSettle();
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Charging'), findsOneWidget);
    });

    testWidgets('editing a rule with no animations does not crash and disables OK', (tester) async {
      final profile = PixelProfile(
        id: 'r0', name: 'NoAnims',
        animations: [],
        rules: [
          PixelRule(
            condition: PixelConditionRolled(),
            actions: [PixelActionPlayAnimation(animIndex: 0)],
          ),
        ],
      );
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile, domain: _domain())));

      // With no animations there's only the rule's edit icon; opening it used to
      // throw (clamp(0, -1)).
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(find.text('Edit Rule'), findsOneWidget);

      // OK is disabled because a rule needs an animation to play.
      final ok = tester.widget<TextButton>(find.widgetWithText(TextButton, 'OK'));
      expect(ok.onPressed, isNull);
    });

    testWidgets('Gradient Pattern type shows Pattern picker and Color Gradient', (tester) async {
      registerBuiltinPatterns(kBuiltinPatterns);
      final profile = PixelProfile(
        id: 'gp1', name: 'GP',
        animations: [],
        rules: [],
      );
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile, domain: _domain())));

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
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile, domain: _domain())));
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
      await tester.pumpWidget(_wrap(PixelsProfileEditorScreen(profile: profile, domain: _domain())));
      await tester.pumpAndSettle();

      expect(find.text('Animation 1: Gradient Pattern'), findsOneWidget);
      expect(find.textContaining(kBuiltinPatterns.first.name), findsOneWidget);
    });
  });

  // ─── PixelsProfilesScreen ──────────────────────────────────────────────────

  group('PixelsProfilesScreen', () {
    late PixelsDieSimulator sim;
    late _FakeProfileRepo store;
    late PixelProfileDomain domain;

    setUp(() async {
      sim = PixelsDieSimulator(name: 'TestDie');
      store = _FakeProfileRepo();
      domain = PixelProfileDomain(store);
    });

    tearDown(() => sim.dispose());

    Widget _buildScreen() => _wrap(PixelsProfilesScreen(
      domain: domain,
      dieService: PixelDieService(sim),
      dieName: 'TestDie',
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

    testWidgets('duplicate opens editor on a "(copy)" clone and saves it alongside the original', (tester) async {
      await store.upsert(_simpleProfile(name: 'Test'));
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Test'), 50.0);
      final testCard = find.ancestor(of: find.text('Test'), matching: find.byType(Card)).first;
      final moreVert = find.descendant(of: testCard, matching: find.byIcon(Icons.more_vert));
      await tester.ensureVisible(moreVert);
      await tester.pumpAndSettle();
      await tester.tap(moreVert);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      // Editor opens on the clone, pre-named "Test (copy)".
      expect(find.text('Test (copy)'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Both the original and the copy now persist.
      final names = (await store.loadAll()).map((p) => p.name).toList();
      expect(names, containsAll(['Test', 'Test (copy)']));
      // ...with distinct ids.
      final ids = (await store.loadAll()).map((p) => p.id).toSet();
      expect(ids, hasLength(2));
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
}
