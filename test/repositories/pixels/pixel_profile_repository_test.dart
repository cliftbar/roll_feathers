import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/repositories/pixels/pixel_profile_repository.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

PixelProfile _simpleProfile({String id = 'p1', String name = 'Test'}) => PixelProfile(
  id: id,
  name: name,
  brightness: 200,
  animations: [PixelAnimationSimple(durationMs: 500, color: const PixelColor(255, 0, 0))],
  rules: [PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)])],
);

void main() {
  group('SharedPrefsPixelProfileRepository', () {
    late SharedPrefsPixelProfileRepository store;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      store = SharedPrefsPixelProfileRepository();
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
