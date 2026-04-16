import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/roll_domain.dart';

import '../../helpers/fakes.dart';
import '../../helpers/sound_fakes.dart';

String _script({String name = 'scTest', String range = '[*:*]', String clipName = 'victory'}) => '''
define $name for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result $range soundclip $clipName
''';

String _actionScript({String name = 'blinkTest'}) => '''
define $name for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink blue
''';

void main() {
  group('Soundclip evaluator dispatch', () {
    late FakeDieDomain dd;
    late FakeAppService app;
    late FakeSoundClipPlayer soundPlayer;

    setUp(() async {
      dd = FakeDieDomain();
      app = FakeAppService();
      soundPlayer = FakeSoundClipPlayer();
    });

    Future<dynamic> _parser() async {
      final rd = await RollDomain.create(dd, app, soundPlayer: soundPlayer);
      return rd.ruleParser;
    }

    test('5.1 soundclip calls enqueueByName when range matches', () async {
      final parser = await _parser();
      await parser.runRuleAsync(_script(), [FakeDie('a', 'A', 5)]);
      expect(soundPlayer.enqueuedByName, equals(['victory']));
    });

    test('5.2 soundclip does not fire when range does not match', () async {
      final parser = await _parser();
      await parser.runRuleAsync(_script(range: '[10:20]'), [FakeDie('a', 'A', 5)]);
      expect(soundPlayer.enqueuedByName, isEmpty);
    });

    test('5.3 hadSoundclip is true when soundclip fired (async path)', () async {
      final parser = await _parser();
      final result = await parser.runRuleAsync(_script(), [FakeDie('a', 'A', 5)]);
      expect(result.hadSoundclip, isTrue);
    });

    test('5.4 hadSoundclip is false when range does not match', () async {
      final parser = await _parser();
      final result = await parser.runRuleAsync(_script(range: '[10:20]'), [FakeDie('a', 'A', 5)]);
      expect(result.hadSoundclip, isFalse);
    });

    test('5.5 hadSoundclip is false for action-only script', () async {
      final parser = await _parser();
      final result = await parser.runRuleAsync(_actionScript(), [FakeDie('a', 'A', 5)]);
      expect(result.hadSoundclip, isFalse);
    });

    test('5.6 soundclip completes without error when enqueue is no-op', () async {
      // FakeSoundClipPlayer.enqueueByName does nothing — simulates clip not found
      final parser = await _parser();
      await expectLater(
        parser.runRuleAsync(_script(clipName: 'missing'), [FakeDie('a', 'A', 5)]),
        completes,
      );
    });

    test('5.7 multiple soundclip targets in same block all fire', () async {
      const script = '''
define multi for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] soundclip clip1
    on result [*:*] soundclip clip2
''';
      final parser = await _parser();
      await parser.runRuleAsync(script, [FakeDie('a', 'A', 3)]);
      expect(soundPlayer.enqueuedByName, equals(['clip1', 'clip2']));
    });
  });
}
