import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:roll_feathers/services/dddice/dddice_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  // ─── DddiceConfig model ────────────────────────────────────────────────────

  group('DddiceConfig — defaults', () {
    test('enabled is false', () => expect(const DddiceConfig().enabled, isFalse));
    test('token is empty', () => expect(const DddiceConfig().token, isEmpty));
    test('isGuest is false', () => expect(const DddiceConfig().isGuest, isFalse));
    test('needsReauth is false', () => expect(const DddiceConfig().needsReauth, isFalse));
    test('roomSlug is empty', () => expect(const DddiceConfig().roomSlug, isEmpty));
    test('roomName is empty', () => expect(const DddiceConfig().roomName, isEmpty));
    test('themeId is empty', () => expect(const DddiceConfig().themeId, isEmpty));
    test('themeName is empty', () => expect(const DddiceConfig().themeName, isEmpty));
  });

  group('DddiceConfig — isAuthenticated', () {
    test('false when token is empty string', () {
      expect(const DddiceConfig(token: '').isAuthenticated, isFalse);
    });

    test('true when token is non-empty', () {
      expect(const DddiceConfig(token: 'abc').isAuthenticated, isTrue);
    });

    test('false by default (no token)', () {
      expect(const DddiceConfig().isAuthenticated, isFalse);
    });
  });

  group('DddiceConfig — copyWith', () {
    test('overrides only specified fields, leaves others unchanged', () {
      const original = DddiceConfig(
        enabled: true,
        token: 'tok',
        isGuest: true,
        needsReauth: false,
        roomSlug: 'slug',
        roomName: 'Room',
        themeId: 'tid',
        themeName: 'TName',
      );
      final copy = original.copyWith(enabled: false, roomName: 'New');
      expect(copy.enabled, isFalse);
      expect(copy.token, equals('tok'));
      expect(copy.isGuest, isTrue);
      expect(copy.needsReauth, isFalse);
      expect(copy.roomSlug, equals('slug'));
      expect(copy.roomName, equals('New'));
      expect(copy.themeId, equals('tid'));
      expect(copy.themeName, equals('TName'));
    });

    test('no-arg copyWith preserves every field', () {
      const original = DddiceConfig(enabled: true, token: 'tok', isGuest: true, needsReauth: true);
      final copy = original.copyWith();
      expect(copy.enabled, isTrue);
      expect(copy.token, equals('tok'));
      expect(copy.isGuest, isTrue);
      expect(copy.needsReauth, isTrue);
    });

    test('can explicitly set needsReauth to false', () {
      const original = DddiceConfig(needsReauth: true);
      expect(original.copyWith(needsReauth: false).needsReauth, isFalse);
    });

    test('can explicitly clear token to empty string', () {
      const original = DddiceConfig(token: 'tok');
      final copy = original.copyWith(token: '');
      expect(copy.isAuthenticated, isFalse);
    });
  });

  // ─── DddiceConfigService ──────────────────────────────────────────────────

  group('DddiceConfigService — getConfig', () {
    test('returns all-defaults when nothing stored', () async {
      final cfg = await DddiceConfigService().getConfig();
      expect(cfg.enabled, isFalse);
      expect(cfg.token, isEmpty);
      expect(cfg.isGuest, isFalse);
      expect(cfg.needsReauth, isFalse);
      expect(cfg.roomSlug, isEmpty);
      expect(cfg.roomName, isEmpty);
      expect(cfg.themeId, isEmpty);
      expect(cfg.themeName, isEmpty);
    });
  });

  group('DddiceConfigService — setConfig round-trip', () {
    test('all 8 fields survive a write-read cycle', () async {
      final service = DddiceConfigService();
      const saved = DddiceConfig(
        enabled: true,
        token: 'my-token',
        isGuest: true,
        needsReauth: true,
        roomSlug: 'room-slug',
        roomName: 'My Room',
        themeId: 'theme-abc',
        themeName: 'My Theme',
      );
      await service.setConfig(saved);
      final loaded = await service.getConfig();

      expect(loaded.enabled, isTrue);
      expect(loaded.token, equals('my-token'));
      expect(loaded.isGuest, isTrue);
      expect(loaded.needsReauth, isTrue);
      expect(loaded.roomSlug, equals('room-slug'));
      expect(loaded.roomName, equals('My Room'));
      expect(loaded.themeId, equals('theme-abc'));
      expect(loaded.themeName, equals('My Theme'));
    });

    test('overwriting enabled=true with enabled=false persists false', () async {
      final service = DddiceConfigService();
      await service.setConfig(const DddiceConfig(enabled: true));
      await service.setConfig(const DddiceConfig(enabled: false));
      final cfg = await service.getConfig();
      expect(cfg.enabled, isFalse);
    });

    test('second DddiceConfigService instance reads data written by first', () async {
      await DddiceConfigService().setConfig(const DddiceConfig(token: 'shared-tok'));
      final loaded = await DddiceConfigService().getConfig();
      expect(loaded.token, equals('shared-tok'));
    });
  });

  group('DddiceConfigService — setNeedsReauth', () {
    test('setNeedsReauth(true) sets needsReauth and preserves other fields', () async {
      final service = DddiceConfigService();
      await service.setConfig(const DddiceConfig(
        enabled: true,
        token: 'tok',
        roomSlug: 'slug',
        themeId: 'tid',
        isGuest: false,
      ));
      await service.setNeedsReauth(true);
      final cfg = await service.getConfig();
      expect(cfg.needsReauth, isTrue);
      expect(cfg.enabled, isTrue);
      expect(cfg.token, equals('tok'));
      expect(cfg.roomSlug, equals('slug'));
      expect(cfg.themeId, equals('tid'));
    });

    test('setNeedsReauth(false) clears a previously set true', () async {
      final service = DddiceConfigService();
      await service.setConfig(const DddiceConfig(needsReauth: true));
      await service.setNeedsReauth(false);
      expect((await service.getConfig()).needsReauth, isFalse);
    });

    test('setNeedsReauth does NOT touch the other 7 fields via SharedPrefs', () async {
      // Verify by checking that fields NOT touched by setNeedsReauth retain defaults.
      final service = DddiceConfigService();
      // Start with nothing stored (setUp cleared prefs).
      await service.setNeedsReauth(true);
      final cfg = await service.getConfig();
      // Only needsReauth changed; token, roomSlug etc. should still be defaults.
      expect(cfg.token, isEmpty);
      expect(cfg.roomSlug, isEmpty);
      expect(cfg.enabled, isFalse);
    });
  });

  group('DddiceConfigService — signOut', () {
    test('signOut resets all fields to defaults', () async {
      final service = DddiceConfigService();
      await service.setConfig(const DddiceConfig(
        enabled: true,
        token: 'tok',
        isGuest: true,
        roomSlug: 'my-room',
        roomName: 'My Room',
        themeId: 'th',
        themeName: 'Theme',
      ));
      await service.signOut();
      final cfg = await service.getConfig();
      expect(cfg.enabled, isFalse);
      expect(cfg.token, isEmpty);
      expect(cfg.isGuest, isFalse);
      expect(cfg.roomSlug, isEmpty);
      expect(cfg.needsReauth, isFalse);
    });
  });
}
