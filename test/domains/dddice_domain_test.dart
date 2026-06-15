import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/dddice_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/repositories/dddice_repository.dart';
import 'package:roll_feathers/services/dddice/dddice_config_service.dart';

import '../helpers/dddice_helpers.dart';
import '../helpers/fakes.dart';

// ─── mocks ────────────────────────────────────────────────────────────────────

class MockDddiceRepository extends Mock implements DddiceRepository {}

// ─── helpers ──────────────────────────────────────────────────────────────────

const _readyConfig = DddiceConfig(
  enabled: true,
  token: 'tok',
  roomSlug: 'room',
  themeId: 'theme',
  needsReauth: false,
);

const _guestConfig = DddiceConfig(
  enabled: true,
  token: 'guest-tok',
  roomSlug: 'my-room',
  isGuest: true,
);

RollResult _roll({RollType type = RollType.sum}) =>
    RollResult(rollType: type, rollResult: 5, rolls: {'d1': 5});

List<GenericDie> _dice() => [FakeDie('d1', 'd1', 5)];

// ─── stub/verify helpers ─────────────────────────────────────────────────────

/// Stubs fireRoll on [mock] to complete normally (or throw [throws]).
void _stubFireRoll(MockDddiceRepository mock, {Exception? throws}) {
  final stub = when(() => mock.fireRoll(
        token: any(named: 'token'),
        roomSlug: any(named: 'roomSlug'),
        theme: any(named: 'theme'),
        dice: any(named: 'dice'),
        result: any(named: 'result'),
      ));
  if (throws != null) {
    stub.thenThrow(throws);
  } else {
    stub.thenAnswer((_) async {});
  }
}

/// Verifies fireRoll was called [called] times with any args.
void _verifyFireRoll(MockDddiceRepository mock, {int called = 1}) =>
    verify(() => mock.fireRoll(
          token: any(named: 'token'),
          roomSlug: any(named: 'roomSlug'),
          theme: any(named: 'theme'),
          dice: any(named: 'dice'),
          result: any(named: 'result'),
        )).called(called);

/// Verifies fireRoll was never called.
void _verifyNeverFireRoll(MockDddiceRepository mock) =>
    verifyNever(() => mock.fireRoll(
          token: any(named: 'token'),
          roomSlug: any(named: 'roomSlug'),
          theme: any(named: 'theme'),
          dice: any(named: 'dice'),
          result: any(named: 'result'),
        ));

// ─── tests ────────────────────────────────────────────────────────────────────

void main() {
  _activationTests();
  _signInAsGuestTests();
  _signOutCancelsActivationTests();

  setUpAll(() {
    registerFallbackValue(<GenericDie>[]);
    registerFallbackValue(_roll());
  });

  late MockDddiceRepository mockRepo;

  setUp(() {
    mockRepo = MockDddiceRepository();
    _stubFireRoll(mockRepo);
    when(() => mockRepo.joinRoom(any(), any())).thenAnswer((_) async {});
  });

  DddiceDomain _domain(DddiceConfig config) =>
      DddiceDomain(mockRepo, FakeDddiceConfigService(config));

  // ─── guard: enabled ───────────────────────────────────────────────────────

  group('onRollComplete — guard: enabled', () {
    test('does NOT call fireRoll when enabled is false', () async {
      await _domain(_readyConfig.copyWith(enabled: false)).onRollComplete(_dice(), _roll());
      _verifyNeverFireRoll(mockRepo);
    });

    test('calls fireRoll when enabled is true', () async {
      await _domain(_readyConfig).onRollComplete(_dice(), _roll());
      _verifyFireRoll(mockRepo);
    });
  });

  // ─── guard: token ─────────────────────────────────────────────────────────

  group('onRollComplete — guard: isAuthenticated (token)', () {
    test('does NOT call fireRoll when token is empty', () async {
      await _domain(_readyConfig.copyWith(token: '')).onRollComplete(_dice(), _roll());
      _verifyNeverFireRoll(mockRepo);
    });

    test('calls fireRoll when token is non-empty', () async {
      await _domain(_readyConfig).onRollComplete(_dice(), _roll());
      _verifyFireRoll(mockRepo);
    });
  });

  // ─── guard: needsReauth ───────────────────────────────────────────────────

  group('onRollComplete — guard: needsReauth', () {
    test('does NOT call fireRoll when needsReauth is true', () async {
      await _domain(_readyConfig.copyWith(needsReauth: true)).onRollComplete(_dice(), _roll());
      _verifyNeverFireRoll(mockRepo);
    });

    test('calls fireRoll when needsReauth is false', () async {
      await _domain(_readyConfig.copyWith(needsReauth: false)).onRollComplete(_dice(), _roll());
      _verifyFireRoll(mockRepo);
    });
  });

  // ─── guard: roomSlug ──────────────────────────────────────────────────────

  group('onRollComplete — guard: roomSlug', () {
    test('does NOT call fireRoll when roomSlug is empty', () async {
      await _domain(_readyConfig.copyWith(roomSlug: '')).onRollComplete(_dice(), _roll());
      _verifyNeverFireRoll(mockRepo);
    });

    test('calls fireRoll when roomSlug is non-empty', () async {
      await _domain(_readyConfig).onRollComplete(_dice(), _roll());
      _verifyFireRoll(mockRepo);
    });
  });

  // ─── guard: dice list ─────────────────────────────────────────────────────

  group('onRollComplete — guard: dice list', () {
    test('does NOT call fireRoll when dice list is empty', () async {
      await _domain(_readyConfig).onRollComplete([], _roll());
      _verifyNeverFireRoll(mockRepo);
    });

    test('calls fireRoll when dice list has at least one die', () async {
      await _domain(_readyConfig).onRollComplete(_dice(), _roll());
      _verifyFireRoll(mockRepo);
    });
  });

  // ─── theme resolution ─────────────────────────────────────────────────────

  group('onRollComplete — theme resolution', () {
    test('non-guest: passes config.themeId to fireRoll', () async {
      await _domain(_readyConfig.copyWith(themeId: 'cool-theme'))
          .onRollComplete(_dice(), _roll());
      verify(() => mockRepo.fireRoll(
            token: any(named: 'token'),
            roomSlug: any(named: 'roomSlug'),
            theme: 'cool-theme',
            dice: any(named: 'dice'),
            result: any(named: 'result'),
          )).called(1);
    });

    test('guest: passes dddice-bees regardless of themeId', () async {
      await _domain(_guestConfig.copyWith(themeId: 'should-be-ignored'))
          .onRollComplete(_dice(), _roll());
      verify(() => mockRepo.fireRoll(
            token: any(named: 'token'),
            roomSlug: any(named: 'roomSlug'),
            theme: 'dddice-bees',
            dice: any(named: 'dice'),
            result: any(named: 'result'),
          )).called(1);
    });

    test('non-guest with empty themeId does NOT call fireRoll', () async {
      await _domain(_readyConfig.copyWith(themeId: ''))
          .onRollComplete(_dice(), _roll());
      _verifyNeverFireRoll(mockRepo);
    });

    test('guest with empty themeId still calls fireRoll (uses dddice-bees)', () async {
      await _domain(_guestConfig.copyWith(themeId: ''))
          .onRollComplete(_dice(), _roll());
      _verifyFireRoll(mockRepo);
    });
  });

  // ─── 401 handling ─────────────────────────────────────────────────────────

  group('onRollComplete — 401 handling', () {
    test('non-guest 401 calls setNeedsReauth(true)', () async {
      _stubFireRoll(mockRepo, throws: const DddiceAuthException());
      final cs = FakeDddiceConfigService(_readyConfig);
      await DddiceDomain(mockRepo, cs).onRollComplete(_dice(), _roll());
      expect(cs.needsReauthCalled, isTrue);
      expect(cs.lastNeedsReauthValue, isTrue);
      expect(cs.signOutCalled, isFalse);
    });

    test('guest 401 calls signOut instead of setNeedsReauth', () async {
      _stubFireRoll(mockRepo, throws: const DddiceAuthException());
      final cs = FakeDddiceConfigService(_guestConfig);
      await DddiceDomain(mockRepo, cs).onRollComplete(_dice(), _roll());
      expect(cs.signOutCalled, isTrue);
      expect(cs.needsReauthCalled, isFalse);
    });

    test('DddiceApiException is swallowed without reauth or signOut', () async {
      _stubFireRoll(mockRepo, throws: const DddiceApiException(422));
      final cs = FakeDddiceConfigService(_readyConfig);
      await expectLater(
          DddiceDomain(mockRepo, cs).onRollComplete(_dice(), _roll()), completes);
      expect(cs.needsReauthCalled, isFalse);
      expect(cs.signOutCalled, isFalse);
    });

    test('onRollComplete does not throw on DddiceAuthException', () async {
      _stubFireRoll(mockRepo, throws: const DddiceAuthException());
      await expectLater(
          _domain(_readyConfig).onRollComplete(_dice(), _roll()), completes);
    });

    test('onRollComplete does not throw on DddiceApiException', () async {
      _stubFireRoll(mockRepo, throws: const DddiceApiException(500));
      await expectLater(
          _domain(_readyConfig).onRollComplete(_dice(), _roll()), completes);
    });
  });

  // ─── guest join ───────────────────────────────────────────────────────────

  group('onRollComplete — guest join', () {
    test('joins room before first roll for guest', () async {
      await _domain(_guestConfig).onRollComplete(_dice(), _roll());
      verify(() => mockRepo.joinRoom('guest-tok', 'my-room')).called(1);
    });

    test('does not join again for the same room on second roll', () async {
      final domain = _domain(_guestConfig);
      await domain.onRollComplete(_dice(), _roll());
      await domain.onRollComplete(_dice(), _roll());
      verify(() => mockRepo.joinRoom(any(), any())).called(1);
    });

    test('joins again when room slug changes between rolls', () async {
      final cs = FakeDddiceConfigService(_guestConfig);
      final domain = DddiceDomain(mockRepo, cs);
      await domain.onRollComplete(_dice(), _roll());
      cs.setStoredConfig(_guestConfig.copyWith(roomSlug: 'other-room'));
      await domain.onRollComplete(_dice(), _roll());
      verify(() => mockRepo.joinRoom(any(), any())).called(2);
    });

    test('does NOT join room for non-guest', () async {
      await _domain(_readyConfig).onRollComplete(_dice(), _roll());
      verifyNever(() => mockRepo.joinRoom(any(), any()));
    });

    test('join failure aborts roll (fireRoll not called)', () async {
      when(() => mockRepo.joinRoom(any(), any()))
          .thenThrow(Exception('join failed'));
      await _domain(_guestConfig).onRollComplete(_dice(), _roll());
      _verifyNeverFireRoll(mockRepo);
    });

    test('join failure does not throw (swallowed by outer catch)', () async {
      when(() => mockRepo.joinRoom(any(), any()))
          .thenThrow(Exception('join failed'));
      await expectLater(
          _domain(_guestConfig).onRollComplete(_dice(), _roll()), completes);
    });
  });

  // ─── error handling ───────────────────────────────────────────────────────

  group('onRollComplete — error handling', () {
    test('does not throw when repository.fireRoll throws an unexpected error', () async {
      _stubFireRoll(mockRepo, throws: Exception('API down'));
      await expectLater(_domain(_readyConfig).onRollComplete(_dice(), _roll()), completes);
    });

    test('does not throw when configService.getConfig throws', () async {
      final domain = DddiceDomain(mockRepo, _ThrowingConfigService());
      await expectLater(domain.onRollComplete(_dice(), _roll()), completes);
      _verifyNeverFireRoll(mockRepo);
    });
  });

  // ─── combined guards ──────────────────────────────────────────────────────

  group('onRollComplete — any single failed guard blocks fireRoll', () {
    final cases = [
      (label: 'enabled=false', config: _readyConfig.copyWith(enabled: false)),
      (label: 'token empty', config: _readyConfig.copyWith(token: '')),
      (label: 'needsReauth=true', config: _readyConfig.copyWith(needsReauth: true)),
      (label: 'roomSlug empty', config: _readyConfig.copyWith(roomSlug: '')),
    ];

    for (final c in cases) {
      test('blocked when ${c.label}', () async {
        final m = MockDddiceRepository();
        _stubFireRoll(m);
        when(() => m.joinRoom(any(), any())).thenAnswer((_) async {});
        final domain = DddiceDomain(m, FakeDddiceConfigService(c.config));
        await domain.onRollComplete(_dice(), _roll());
        _verifyNeverFireRoll(m);
      });
    }
  });
}

/// Config service that always throws — tests domain resilience.
class _ThrowingConfigService extends DddiceConfigService {
  @override
  Future<DddiceConfig> getConfig() async => throw Exception('config service down');
}

// ─── startActivation / cancelActivation ──────────────────────────────────────

void _activationTests() {
  late MockDddiceRepository repo;

  setUp(() {
    repo = MockDddiceRepository();
    when(() => repo.createActivationCode()).thenAnswer(
        (_) async => const DddiceActivationCode(code: 'ABC', secret: 'sec'));
    when(() => repo.pollActivation(any(), any())).thenAnswer((_) async => null);
  });

  group('startActivation', () {
    test('returns null when createActivationCode fails', () async {
      when(() => repo.createActivationCode()).thenAnswer((_) async => null);
      final domain = DddiceDomain(repo, FakeDddiceConfigService());
      expect(await domain.startActivation(), isNull);
    });

    test('returns the activation code on success', () async {
      final domain = DddiceDomain(repo, FakeDddiceConfigService());
      final code = await domain.startActivation();
      expect(code?.code, equals('ABC'));
      expect(code?.secret, equals('sec'));
      await domain.cancelActivation();
    });

    test('activationEvents stream is available after startActivation', () async {
      final domain = DddiceDomain(repo, FakeDddiceConfigService());
      await domain.startActivation();
      expect(domain.activationEvents, isNotNull);
      await domain.cancelActivation();
    });

    test('polling saves config and emits DddiceActivationComplete on token', () async {
      when(() => repo.pollActivation(any(), any())).thenAnswer((_) async => 'new-tok');
      final cs = FakeDddiceConfigService(const DddiceConfig());
      final domain = DddiceDomain(repo, cs,
          activationPollInterval: const Duration(milliseconds: 10));

      // Subscribe AFTER startActivation creates the stream controller.
      await domain.startActivation();
      DddiceActivationEvent? received;
      domain.activationEvents.listen((e) => received = e);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isA<DddiceActivationComplete>());
      expect((received as DddiceActivationComplete).config.token, equals('new-tok'));
      expect((received as DddiceActivationComplete).config.isGuest, isFalse);
      expect(cs.storedConfig.token, equals('new-tok'));
    });

    test('polling emits DddiceActivationError on exception', () async {
      when(() => repo.pollActivation(any(), any()))
          .thenThrow(Exception('network down'));
      final domain = DddiceDomain(repo, FakeDddiceConfigService(),
          activationPollInterval: const Duration(milliseconds: 10));

      await domain.startActivation();
      DddiceActivationEvent? received;
      domain.activationEvents.listen((e) => received = e);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isA<DddiceActivationError>());
      await domain.cancelActivation();
    });

    test('calling startActivation again cancels the previous poll', () async {
      final domain = DddiceDomain(repo, FakeDddiceConfigService(),
          activationPollInterval: const Duration(seconds: 60));
      await domain.startActivation();
      final stream1 = domain.activationEvents;
      await domain.startActivation(); // second call should cancel the first
      // If stream1 is the same as the current one, the first was replaced
      expect(domain.activationEvents, isNot(same(stream1)));
      await domain.cancelActivation();
    });
  });

  group('cancelActivation', () {
    test('completes normally when no activation is in progress', () async {
      final domain = DddiceDomain(repo, FakeDddiceConfigService());
      await expectLater(domain.cancelActivation(), completes);
    });

    test('closes the activationEvents stream', () async {
      final domain = DddiceDomain(repo, FakeDddiceConfigService());
      await domain.startActivation();
      bool closed = false;
      domain.activationEvents.listen(null, onDone: () => closed = true);
      await domain.cancelActivation();
      await Future.delayed(Duration.zero);
      expect(closed, isTrue);
    });
  });
}

// ─── signInAsGuest ────────────────────────────────────────────────────────────

void _signInAsGuestTests() {
  late MockDddiceRepository repo;

  setUp(() {
    repo = MockDddiceRepository();
    when(() => repo.createGuestUser()).thenAnswer((_) async => 'guest-tok');
  });

  group('signInAsGuest', () {
    test('returns false when createGuestUser fails', () async {
      when(() => repo.createGuestUser()).thenAnswer((_) async => null);
      final domain = DddiceDomain(repo, FakeDddiceConfigService());
      expect(await domain.signInAsGuest(), isFalse);
    });

    test('saves config with guest token and isGuest=true', () async {
      final cs = FakeDddiceConfigService(const DddiceConfig());
      final domain = DddiceDomain(repo, cs);
      await domain.signInAsGuest();
      expect(cs.storedConfig.token, equals('guest-tok'));
      expect(cs.storedConfig.isGuest, isTrue);
      expect(cs.storedConfig.needsReauth, isFalse);
    });

    test('returns true on success', () async {
      final domain = DddiceDomain(repo, FakeDddiceConfigService());
      expect(await domain.signInAsGuest(), isTrue);
    });
  });
}

// ─── signOut cancels activation ───────────────────────────────────────────────

void _signOutCancelsActivationTests() {
  group('signOut cancels in-progress activation', () {
    test('signOut cancels polling timer and closes stream', () async {
      final repo = MockDddiceRepository();
      when(() => repo.createActivationCode()).thenAnswer(
          (_) async => const DddiceActivationCode(code: 'X', secret: 'Y'));
      when(() => repo.pollActivation(any(), any())).thenAnswer((_) async => null);

      final cs = FakeDddiceConfigService(const DddiceConfig());
      final domain = DddiceDomain(repo, cs,
          activationPollInterval: const Duration(seconds: 60));
      await domain.startActivation();
      bool streamClosed = false;
      domain.activationEvents.listen(null, onDone: () => streamClosed = true);

      await domain.signOut();
      await Future.delayed(Duration.zero);

      expect(streamClosed, isTrue);
      expect(cs.signOutCalled, isTrue);
    });
  });
}
