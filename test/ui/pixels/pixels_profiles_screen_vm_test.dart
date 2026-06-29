import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/domains/pixel_profile_domain.dart';
import 'package:roll_feathers/repositories/pixels/pixel_profile_repository.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/testing/pixels_die_simulator.dart';
import 'package:roll_feathers/ui/pixels/pixels_profiles_screen_vm.dart';

class _FakeRepo implements PixelProfileRepository {
  final List<PixelProfile> items = [];
  @override
  Future<List<PixelProfile>> loadAll() async => List.of(items);
  @override
  Future<void> saveAll(List<PixelProfile> profiles) async => items
    ..clear()
    ..addAll(profiles);
  @override
  Future<void> upsert(PixelProfile p) async {
    final i = items.indexWhere((e) => e.id == p.id);
    i >= 0 ? items[i] = p : items.add(p);
  }
  @override
  Future<void> delete(String id) async => items.removeWhere((e) => e.id == id);
  @override
  List<BuiltinProfile> builtins() => kBuiltinProfiles;
}

PixelProfile _profile({String id = 'p1', String name = 'Test'}) => PixelProfile(
  id: id,
  name: name,
  animations: [PixelAnimationSimple(durationMs: 500, color: const PixelColor(255, 0, 0))],
  rules: [PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)])],
);

void main() {
  late _FakeRepo repo;
  late PixelsDieSimulator sim;
  late PixelDieService svc;
  late PixelProfileDomain domain;
  late PixelsProfilesScreenViewModel vm;

  setUp(() {
    repo = _FakeRepo();
    sim = PixelsDieSimulator(name: 'Sim');
    svc = PixelDieService(sim);
    domain = PixelProfileDomain(repo);
    vm = PixelsProfilesScreenViewModel(domain, svc, 'Sim');
  });

  tearDown(() => sim.dispose());

  // saveEdited/deleteProfile await an internal reload, so the list is
  // deterministic afterward (no dependence on the constructor's auto-load).
  test('saveEdited persists and reloads; deleteProfile removes', () async {
    await vm.saveEdited.execute(_profile());
    expect(vm.profiles.map((p) => p.name), ['Test']);
    await vm.deleteProfile.execute(_profile());
    expect(vm.profiles, isEmpty);
  });

  test('flashProfile marks it on-die and sets a success status', () async {
    await vm.saveEdited.execute(_profile());
    expect(vm.isProfileOnDie(_profile()), isFalse);
    await vm.flashProfile.execute(vm.profiles.single);
    expect(vm.statusMessage, contains('flashed'));
    expect(vm.isProfileOnDie(vm.profiles.single), isTrue);
    expect(vm.transferringId, isNull); // cleared when done
  });

  test('flashBuiltin marks the built-in on-die', () async {
    final preset = kBuiltinProfiles.first;
    await vm.flashBuiltin.execute(preset);
    expect(vm.isBuiltinOnDie(preset), isTrue);
  });

  test('previewAnimation completes and reports status', () async {
    await vm.saveEdited.execute(_profile());
    await vm.previewAnimation.execute(vm.profiles.single, 'p1', 0);
    expect(vm.statusMessage, 'Preview sent');
    expect(vm.transferringId, isNull);
  });

  test('duplicate / newFromTemplate produce fresh ids', () {
    final dup = vm.duplicate(_profile(name: 'Orig'));
    expect(dup.name, 'Orig (copy)');
    expect(dup.id, isNot('p1'));
    final created = vm.newFromTemplate(_profile(id: '', name: 'Fire'));
    expect(created.id, isNotEmpty);
    expect(created.name, 'Fire');
  });
}
