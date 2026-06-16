import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:roll_feathers/domains/dddice_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/repositories/dddice_repository.dart';
import 'package:roll_feathers/testing/dddice_mock_server.dart';

import '../helpers/dddice_helpers.dart';
import '../helpers/fakes.dart';

// Exercises the real (non-guest) dddice auth flow end-to-end over a real
// HTTP client against an in-process DddiceMockServer, instead of MockClient
// stubs. This is the "static" counterpart to the live UI-driven test in
// integration_test/dddice_real_auth_test.dart — same DddiceMockServer, same
// DddiceRepository wiring, no real dddice account or network access needed.
void main() {
  late DddiceMockServer mock;
  late DddiceRepository repo;

  setUp(() async {
    mock = DddiceMockServer();
    await mock.start();
    repo = DddiceRepository(http.Client(), baseUrl: mock.baseUrl);
  });

  tearDown(() => mock.close());

  group('activation flow', () {
    test('createActivationCode returns a non-empty code and secret', () async {
      final code = await repo.createActivationCode();
      expect(code?.code, isNotEmpty);
      expect(code?.secret, isNotEmpty);
    });

    test('pollActivation returns null while pending', () async {
      final code = await repo.createActivationCode();
      expect(await repo.pollActivation(code!.code, code.secret), isNull);
    });

    test('pollActivation returns the token after completeActivation', () async {
      final code = await repo.createActivationCode();
      mock.completeActivation(code!.code, token: 'real-flow-token');
      expect(await repo.pollActivation(code.code, code.secret), equals('real-flow-token'));
    });

    test('pollActivation returns null with a mismatched secret', () async {
      final code = await repo.createActivationCode();
      mock.completeActivation(code!.code, token: 'tok');
      expect(await repo.pollActivation(code.code, 'wrong-secret'), isNull);
    });

    test('completeActivation throws for an unknown code', () {
      expect(() => mock.completeActivation('NOPE'), throwsArgumentError);
    });
  });

  group('DddiceDomain — startActivation against the mock', () {
    test('emits DddiceActivationComplete once the mock completes the code', () async {
      final domain = DddiceDomain(repo, FakeDddiceConfigService(),
          activationPollInterval: const Duration(milliseconds: 20));

      final code = await domain.startActivation();
      expect(code, isNotNull);

      DddiceActivationEvent? received;
      domain.activationEvents.listen((e) => received = e);

      mock.completeActivation(code!.code, token: 'domain-flow-token');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isA<DddiceActivationComplete>());
      expect((received as DddiceActivationComplete).config.token, equals('domain-flow-token'));
      expect((received as DddiceActivationComplete).config.isGuest, isFalse);

      await domain.cancelActivation();
    });
  });

  group('other endpoints round-trip without throwing', () {
    test('createRoom, listRooms, listThemes, joinRoom, fireRoll', () async {
      const token = 'whatever-token';
      final room = await repo.createRoom(token);
      expect(room?.slug, isNotEmpty);

      final rooms = await repo.listRooms(token);
      expect(rooms, isNotEmpty);

      final themes = await repo.listThemes(token);
      expect(themes, isNotEmpty);

      await repo.joinRoom(token, room!.slug);

      await repo.fireRoll(
        token: token,
        roomSlug: room.slug,
        theme: themes.first.id,
        dice: [FakeDie('d1', 'd1', 5)],
        result: RollResult(rollType: RollType.sum, rollResult: 5, rolls: {'d1': 5}),
      );
    });
  });
}
