import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/domains/roll_lifecycle_observer.dart';
import 'package:roll_feathers/services/dddice/dddice_config_service.dart';

/// In-memory DddiceConfigService — no SharedPreferences; safe for unit tests.
class FakeDddiceConfigService extends DddiceConfigService {
  DddiceConfig _config;
  bool needsReauthCalled = false;
  bool? lastNeedsReauthValue;
  bool signOutCalled = false;

  FakeDddiceConfigService([this._config = const DddiceConfig()]);

  void setStoredConfig(DddiceConfig config) => _config = config;
  DddiceConfig get storedConfig => _config;

  @override
  Future<DddiceConfig> getConfig() async => _config;

  @override
  Future<void> setConfig(DddiceConfig config) async => _config = config;

  @override
  Future<void> setNeedsReauth(bool value) async {
    needsReauthCalled = true;
    lastNeedsReauthValue = value;
    _config = _config.copyWith(needsReauth: value);
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    _config = const DddiceConfig();
  }
}

/// Observer that records every lifecycle call, with optional throw injection.
class RecordingObserver extends RollLifecycleObserver {
  final List<GenericDie> rollingDice = [];
  final List<({List<GenericDie> dice, RollResult result})> completedRolls = [];
  bool shouldThrowOnComplete = false;
  bool shouldThrowOnRolling = false;

  @override
  Future<void> onDieRolling(GenericDie die) async {
    if (shouldThrowOnRolling) throw Exception('observer rolling error');
    rollingDice.add(die);
  }

  @override
  Future<void> onRollComplete(List<GenericDie> dice, RollResult result) async {
    if (shouldThrowOnComplete) throw Exception('observer complete error');
    completedRolls.add((dice: dice, result: result));
  }
}
