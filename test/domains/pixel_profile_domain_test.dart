import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/domains/pixel_profile_domain.dart';
import 'package:roll_feathers/repositories/pixels/pixel_profile_repository.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/testing/pixels_die_simulator.dart';

class _FakeRepo implements PixelProfileRepository {
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

PixelProfile _profile({String id = 'p1', String name = 'Test'}) => PixelProfile(
  id: id,
  name: name,
  animations: [PixelAnimationSimple(durationMs: 500, color: const PixelColor(255, 0, 0))],
  rules: [PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)])],
);

void main() {
  late _FakeRepo repo;
  late PixelProfileDomain domain;

  setUp(() {
    repo = _FakeRepo();
    domain = PixelProfileDomain(repo);
  });

  group('CRUD via repository', () {
    test('save then loadProfiles returns it', () async {
      await domain.save(_profile());
      final all = await domain.loadProfiles();
      expect(all.single.name, 'Test');
    });

    test('delete removes by id', () async {
      await domain.save(_profile());
      await domain.delete('p1');
      expect(await domain.loadProfiles(), isEmpty);
    });
  });

  group('pure logic', () {
    test('duplicate gives a fresh id, "(copy)" name, and is independent', () {
      final original = _profile(name: 'Orig');
      final copy = domain.duplicate(original);
      expect(copy.name, 'Orig (copy)');
      expect(copy.id, isNot(original.id));
      expect(copy.id, isNotEmpty);
    });

    test('newFromTemplate stamps a fresh id, keeping name/animations', () {
      final tmpl = _profile(id: '', name: 'Fire');
      final created = domain.newFromTemplate(tmpl);
      expect(created.id, isNotEmpty);
      expect(created.name, 'Fire');
      expect(created.animations.length, tmpl.animations.length);
    });

    test('importAnimation delegates to the import resolver', () {
      final source = [
        PixelAnimationSimple(durationMs: 100, color: const PixelColor(0, 0, 255)),
        PixelAnimationSequence(durationMs: 300, entries: [(0, 0)]),
      ];
      // Importing the Sequence (idx 1) into a 2-animation profile pulls in its
      // referenced sibling and remaps the index.
      final imported = domain.importAnimation(source, 1, 2);
      expect(imported, hasLength(2));
      expect((imported[1] as PixelAnimationSequence).entries, [(2, 0)]);
    });
  });

  group('die-bound operations (via simulator service)', () {
    late PixelsDieSimulator sim;
    late PixelDieService service;

    setUp(() {
      sim = PixelsDieSimulator(name: 'Sim');
      service = PixelDieService(sim);
    });

    tearDown(() => sim.dispose());

    test('flash makes the profile report as on-die', () async {
      final profile = _profile();
      expect(domain.isOnDie(profile, service), isFalse);
      await domain.flash(service, profile);
      expect(domain.isOnDie(profile, service), isTrue);
    });

    test('preview completes without throwing', () async {
      await expectLater(domain.preview(service, _profile(), 0), completes);
    });
  });
}
