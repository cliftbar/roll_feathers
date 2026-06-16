import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_lifecycle_observer.dart';
import 'package:roll_feathers/repositories/dddice_repository.dart';
import 'package:roll_feathers/services/dddice/dddice_config_service.dart';

import 'roll_domain.dart';

// ─── activation events ────────────────────────────────────────────────────────

sealed class DddiceActivationEvent {}

class DddiceActivationComplete extends DddiceActivationEvent {
  final DddiceConfig config;
  DddiceActivationComplete(this.config);
}

class DddiceActivationError extends DddiceActivationEvent {
  final String message;
  DddiceActivationError(this.message);
}

// ─── domain ───────────────────────────────────────────────────────────────────

class DddiceDomain extends RollLifecycleObserver {
  static const _guestTheme = 'dddice-bees';

  final DddiceRepository _repository;
  final DddiceConfigService _configService;
  final Duration _activationPollInterval;
  final _log = Logger('DddiceDomain');

  String? _joinedRoomSlug;
  Timer? _activationTimer;
  StreamController<DddiceActivationEvent>? _activationCtrl;

  DddiceDomain(
    this._repository,
    this._configService, {
    @visibleForTesting Duration activationPollInterval = const Duration(seconds: 5),
  }) : _activationPollInterval = activationPollInterval;

  // ─── config ─────────────────────────────────────────────────────────────

  Future<DddiceConfig> getConfig() => _configService.getConfig();

  Future<void> saveConfig(DddiceConfig config) => _configService.setConfig(config);

  Future<void> signOut() async {
    await cancelActivation();
    await _configService.signOut();
  }

  // ─── activation flow ─────────────────────────────────────────────────────

  /// Begins the dddice activation flow. Returns the code to display, or null
  /// on failure. Internally starts polling; callers listen to [activationEvents]
  /// for [DddiceActivationComplete] or [DddiceActivationError].
  Future<DddiceActivationCode?> startActivation() async {
    await cancelActivation();
    final code = await _repository.createActivationCode();
    if (code == null) return null;

    _activationCtrl = StreamController<DddiceActivationEvent>.broadcast();
    _activationTimer = Timer.periodic(_activationPollInterval, (_) async {
      try {
        final token = await _repository.pollActivation(code.code, code.secret);
        if (token != null) {
          final existing = await _configService.getConfig();
          final updated = existing.copyWith(token: token, isGuest: false, needsReauth: false);
          await _configService.setConfig(updated);
          _activationCtrl?.add(DddiceActivationComplete(updated));
          await cancelActivation();
        }
      } catch (e) {
        _activationCtrl?.add(DddiceActivationError('Connection error. Will retry...'));
      }
    });

    return code;
  }

  /// Cancels any in-progress activation poll and closes the event stream.
  Future<void> cancelActivation() async {
    _activationTimer?.cancel();
    _activationTimer = null;
    await _activationCtrl?.close();
    _activationCtrl = null;
  }

  /// Stream of [DddiceActivationEvent]s emitted during [startActivation].
  Stream<DddiceActivationEvent> get activationEvents =>
      _activationCtrl?.stream ?? const Stream.empty();

  // ─── guest sign-in ───────────────────────────────────────────────────────

  /// Creates a guest account and saves the resulting config.
  /// Returns true on success, false if guest creation fails.
  Future<bool> signInAsGuest() async {
    final token = await _repository.createGuestUser();
    if (token == null) return false;
    final room = await _repository.createRoom(token);
    final existing = await _configService.getConfig();
    await _configService.setConfig(existing.copyWith(
      token: token,
      isGuest: true,
      needsReauth: false,
      roomSlug: room?.slug,
      roomName: room?.name,
    ));
    return true;
  }

  // ─── settings API (for UI dropdowns) ────────────────────────────────────

  Future<List<DddiceRoom>> listRooms(String token) => _repository.listRooms(token);

  Future<List<DddiceTheme>> listThemes(String token) => _repository.listThemes(token);

  // ─── roll lifecycle ───────────────────────────────────────────────────────

  @override
  Future<void> onRollComplete(List<GenericDie> dice, RollResult result) async {
    try {
      final config = await _configService.getConfig();
      if (!config.enabled || !config.isAuthenticated || config.needsReauth) return;
      if (config.roomSlug.isEmpty || dice.isEmpty) return;

      if (config.isGuest && config.roomSlug != _joinedRoomSlug) {
        await _repository.joinRoom(config.token, config.roomSlug);
        _joinedRoomSlug = config.roomSlug;
      }

      final theme = config.isGuest ? _guestTheme : config.themeId;
      if (theme.isEmpty) return;

      try {
        await _repository.fireRoll(
          token: config.token,
          roomSlug: config.roomSlug,
          theme: theme,
          dice: dice,
          result: result,
        );
      } on DddiceAuthException {
        if (config.isGuest) {
          _log.warning('dddice 401 for guest: signing out');
          await _configService.signOut();
        } else {
          _log.warning('dddice 401: marking needs-reauth');
          await _configService.setNeedsReauth(true);
        }
      } on DddiceApiException catch (e) {
        _log.warning('dddice roll failed: ${e.statusCode}');
      }
    } catch (e, st) {
      _log.warning('onRollComplete error', e, st);
    }
  }
}
