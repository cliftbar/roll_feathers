import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_parser/parser.dart';
import 'package:roll_feathers/domains/sound/sound_clip_player.dart';
import 'package:roll_feathers/domains/sound/sound_clip_repository.dart';
import 'package:roll_feathers/services/app_service.dart';

class RollResult {
  final RollType rollType;
  final int rollResult;
  final Map<String, int> rolls;
  late final DateTime _rollTime;
  final String? ruleName;

  RollResult({required this.rollType, required this.rollResult, required this.rolls, this.ruleName}) {
    _rollTime = DateTime.now();
  }

  DateTime get rollTime => _rollTime;

  Map<String, dynamic> toJson() {
    return {
      'rollType': rollType.name,
      'rollResult': rollResult,
      'rolls': rolls,
      'rollTime': rollTime.toIso8601String(),
    };
  }
}

enum RollType { sum, max, min, rule, normal }

enum RollStatus { rollStarted, rolling, rollEnded }

class RollDomain {
  final StreamController<List<RollResult>> _rollResultStream = StreamController<List<RollResult>>.broadcast();
  final StreamController<RollStatus> _rollStatusStream = StreamController<RollStatus>.broadcast();

  final List<RollResult> _rollHistory = [];

  List<RollResult> get rollHistory => _rollHistory;
  bool _isRolling = false;
  final Map<String, GenericDie> _rolledDie = {};
  RollType rollType = RollType.sum;
  bool autoRollVirtualDice = true;

  final DieDomain _diceDomain;
  // ignore: unused_field
  late StreamSubscription<Map<String, GenericDie>> _deviceStreamListener; // used for notifications, better way?

  Timer? _rollUpdateTimer;

  late final RuleParser ruleParser;
  late final AppService appService;
  bool useAsyncEvaluator = false; // gated via AppService pref

  final SoundClipRepository? _soundRepo;
  final SoundClipPlayer? _soundPlayer;

  RollDomain._(
    this._diceDomain,
    this.appService, {
    http.Client? httpClient,
    SoundClipRepository? soundRepo,
    SoundClipPlayer? soundPlayer,
  })  : _soundRepo = soundRepo,
        _soundPlayer = soundPlayer {
    _deviceStreamListener = _diceDomain.getDiceStream().listen(rollStreamListener);
    ruleParser = RuleParser(_diceDomain, this, appService, httpClient: httpClient);
  }

  Future<void> init() async {
    await ruleParser.init();
    // Load evaluator preference (default false to avoid changing runtime behavior)
    try {
      useAsyncEvaluator = await appService.getUseAsyncEvaluator();
    } catch (_) {
      useAsyncEvaluator = false;
    }
  }

  Stream<List<RollResult>> subscribeRollResults() => _rollResultStream.stream;

  Stream<RollStatus> subscribeRollStatus() => _rollStatusStream.stream;

  static Future<RollDomain> create(
    DieDomain dieDomain,
    AppService appService, {
    http.Client? httpClient,
    SoundClipRepository? soundRepo,
    SoundClipPlayer? soundPlayer,
  }) async {
    var rollDomain = RollDomain._(
      dieDomain,
      appService,
      httpClient: httpClient,
      soundRepo: soundRepo,
      soundPlayer: soundPlayer,
    );
    rollDomain.init();
    return rollDomain;
  }

  /// Called by the DSL evaluator when a soundclip target fires.
  Future<void> enqueueSound(String clipName) async {
    await _soundPlayer?.enqueueByName(clipName);
  }

  bool areDieRolling(List<GenericDie> allDie) {
    return allDie.every(
      (d) => d.state.rollState == DiceRollState.rolled.index || d.state.rollState == DiceRollState.onFace.index,
    );
  }

  Future<void> _startRolling({GenericDie? triggeringDie}) async {
    _rolledDie.clear();
    _rollUpdateTimer?.cancel();

    _isRolling = true;
    _rollStatusStream.add(RollStatus.rollStarted);

    _rollUpdateTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _rollStatusStream.add(RollStatus.rolling);
    });

    await _fireGlobalRollingSound(triggeringDie);
  }

  Future<void> _fireGlobalRollingSound(GenericDie? die) async {
    final soundRepo = _soundRepo;
    final soundPlayer = _soundPlayer;
    if (soundRepo == null || soundPlayer == null) return;

    final settings = await soundRepo.getSettings();
    if (settings.hardMute || !settings.rollingEnabled || settings.rollingClipId == null) return;

    // Check per-die opt-out: if triggering die has useGlobalSounds = false, suppress.
    if (die != null && !die.useGlobalSounds) return;

    await soundPlayer.enqueueById(settings.rollingClipId!);
  }

  void _stopRolling() {
    _rollUpdateTimer?.cancel();
    _isRolling = false;
    _rollStatusStream.add(RollStatus.rollEnded);
  }

  Future<int> _stopRollWithResult({RollType rollType = RollType.normal}) async {
    ParseResult? ruleResult;
    bool ruleFiredSoundclip = false;

    for (var r in ruleParser.getRules(enabledOnly: true)) {
      ruleResult = await ruleParser.runRuleAsync(r.script, _rolledDie.values.toList());
      if (ruleResult.ruleReturn) {
        rollType = RollType.rule;
        ruleFiredSoundclip = ruleResult.hadSoundclip;
        break;
      }
    }

    late Map<String, int> resultRolls;
    late int resultValue;
    String? ruleName;
    if (ruleResult != null && ruleResult.ruleReturn) {
      resultRolls = ruleResult.allRolled;
      resultValue = ruleResult.result;
      ruleName = ruleResult.ruleName;
    } else {
      resultRolls = Map.fromEntries(_rolledDie.entries.map((e) => MapEntry(e.key, e.value.getFaceValueOrElse())));
      resultValue = resultRolls.values.sum;
    }

    var result = RollResult(rollType: rollType, rolls: resultRolls, rollResult: resultValue, ruleName: ruleName);
    _rollHistory.insert(0, result);
    _rollStatusStream.add(RollStatus.rollEnded);
    _rollResultStream.add(_rollHistory);

    if (!ruleFiredSoundclip) {
      await _fireGlobalRolledSound();
    }

    return result.rollResult;
  }

  Future<void> _fireGlobalRolledSound() async {
    final soundRepo = _soundRepo;
    final soundPlayer = _soundPlayer;
    if (soundRepo == null || soundPlayer == null) return;

    final settings = await soundRepo.getSettings();
    if (settings.hardMute || !settings.rolledEnabled || settings.rolledClipId == null) return;

    // Normal dice win: fire unless ALL dice in this roll have opted out.
    bool anyDieWantsSound = false;
    for (final die in _rolledDie.values) {
      if (die.useGlobalSounds) {
        anyDieWantsSound = true;
        break;
      }
    }
    // If no dice are in the roll (virtual-only edge case), default to fire.
    if (_rolledDie.isEmpty) anyDieWantsSound = true;
    if (!anyDieWantsSound) return;

    await soundPlayer.enqueueById(settings.rolledClipId!);
  }

  void _rollStartVirtualDice({bool force = false}) {
    if (!autoRollVirtualDice && !force) {
      return;
    }
    _diceDomain.getVirtualDice().forEach((vd) => vd.setRollState(DiceRollState.rolling));
  }

  void _rollEndVirtualDie({bool force = false}) {
    if (!autoRollVirtualDice && !force) {
      return;
    }

    _diceDomain.getVirtualDice().forEach((vd) {
      vd.setRollState(DiceRollState.rolled);
      _rolledDie[vd.dieId] = vd;
    });
  }

  // attach listeners to die
  void rollStreamListener(Map<String, GenericDie> data) {
    for (var die in data.values.where((d) => d.type != GenericDieType.virtual)) {
      // Per-die flag: prevents re-sending blinkRolling if rolling fires multiple
      // times for the same die during a single roll session.
      bool dieBlinking = false;

      die.addRollCallback(DiceRollState.rolling, "$hashCode.rolling", (DiceRollState rollState) async {
        if (!_isRolling) {
          _rollStartVirtualDice();
          await _startRolling(triggeringDie: die);
        }
        if (!dieBlinking) {
          dieBlinking = true;
          _diceDomain.blinkRolling(die);
        }
      });

      die.addRollCallback(DiceRollState.rolled, "$hashCode.rolled", (DiceRollState rollState) async {
        dieBlinking = false;
        await _diceDomain.stopAnimations(die);
        bool allDiceRolled = areDieRolling(data.values.where((d) => d.type != GenericDieType.virtual).toList());
        _rolledDie[die.dieId] = die;
        _rollEndVirtualDie();

        if (allDiceRolled && _isRolling) {
          // roll is active but all dice are done rolling
          _stopRolling();
          await _stopRollWithResult();
        }
      });

      die.addRollCallback(DiceRollState.crooked, "$hashCode.crooked", (DiceRollState rollState) async {
        dieBlinking = false;
        await _diceDomain.stopAnimations(die);
      });
    }
  }

  void clearRollResults() {
    _rollHistory.clear();
    _rollResultStream.add(_rollHistory);
  }

  void rollAllVirtualDice({bool force = false}) {
    if (_diceDomain.dieCount == 0) {
      return;
    }
    // Start the rolling process (no triggering die for virtual rolls)
    unawaited(_startRolling());
    _rollStartVirtualDice(force: force);

    // Use a timer to simulate the rolling animation
    Timer(const Duration(milliseconds: 500), () {
      _rollEndVirtualDie(force: force);
      _stopRolling();
      _stopRollWithResult(rollType: rollType);
    });
  }
}
