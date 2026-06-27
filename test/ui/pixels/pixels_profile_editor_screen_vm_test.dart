import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/domains/pixel_profile_domain.dart';
import 'package:roll_feathers/repositories/pixels/pixel_profile_repository.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/testing/pixels_die_simulator.dart';
import 'package:roll_feathers/ui/pixels/pixels_profile_editor_screen_vm.dart';

class _FakeRepo implements PixelProfileRepository {
  @override
  Future<List<PixelProfile>> loadAll() async => [];
  @override
  Future<void> saveAll(List<PixelProfile> profiles) async {}
  @override
  Future<void> upsert(PixelProfile p) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  List<BuiltinProfile> builtins() => kBuiltinProfiles;
}

PixelAnimationSimple _simple(int r) => PixelAnimationSimple(durationMs: 100, color: PixelColor(r, 0, 0));

void main() {
  late PixelProfileDomain domain;
  setUp(() => domain = PixelProfileDomain(_FakeRepo()));

  PixelsProfileEditorViewModel vmFor(PixelProfile p, {PixelDieService? die}) =>
      PixelsProfileEditorViewModel(domain, die, p);

  PixelProfile _profile(List<PixelAnimation> anims, List<PixelRule> rules) =>
      PixelProfile(id: 'e1', name: 'Edit', animations: anims, rules: rules);

  test('add / replace animation', () {
    final vm = vmFor(_profile([_simple(1)], const []));
    vm.addAnimation(_simple(2));
    expect(vm.animations, hasLength(2));
    vm.replaceAnimation(0, _simple(9));
    expect((vm.animations[0] as PixelAnimationSimple).color.r, 9);
  });

  test('deleteAnimation clamps rule indices that fall out of range', () {
    final vm = vmFor(
      _profile(
        [_simple(1), _simple(2)],
        [PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 1)])],
      ),
    );
    vm.deleteAnimation(0); // now only 1 animation; the rule referenced index 1
    expect(vm.animations, hasLength(1));
    expect((vm.rules.single.actions.single as PixelActionPlayAnimation).animIndex, 0);
  });

  test('importAnimation appends resolved clones and returns the count', () {
    final vm = vmFor(_profile([_simple(1)], const []));
    final source = [
      _simple(5),
      PixelAnimationSequence(durationMs: 300, entries: [(0, 0)]),
    ];
    final count = vm.importAnimation(source, 1); // Sequence + its referenced sibling
    expect(count, 2);
    expect(vm.animations, hasLength(3));
    // The imported Sequence's index was remapped past the existing animation.
    expect((vm.animations.last as PixelAnimationSequence).entries, [(1, 0)]);
  });

  test('rule mutations', () {
    final vm = vmFor(_profile([_simple(1)], const []));
    vm.addRule(PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)]));
    expect(vm.rules, hasLength(1));
    vm.deleteRule(0);
    expect(vm.rules, isEmpty);
  });

  test('buildProfile uses the given name and current lists; preview hidden without a die', () {
    final vm = vmFor(_profile([_simple(1)], const []));
    expect(vm.canPreview, isFalse);
    final built = vm.buildProfile('  My Name  ');
    expect(built.name, 'My Name');
    expect(built.id, 'e1');
    expect(built.animations, hasLength(1));
  });

  test('preview against a die reports status', () async {
    final sim = PixelsDieSimulator(name: 'Sim');
    addTearDown(sim.dispose);
    final vm = vmFor(_profile([_simple(1)], const []), die: PixelDieService(sim));
    expect(vm.canPreview, isTrue);
    await vm.preview.execute(vm.animations, 0);
    expect(vm.statusMessage, 'Preview sent');
  });
}
