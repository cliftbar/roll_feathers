import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/repositories/dddice_repository.dart';

import '../helpers/fakes.dart';

// ─── DddiceRoom.displayName ───────────────────────────────────────────────────

void _roomDisplayNameTests() {
  group('DddiceRoom — displayName', () {
    test('returns name when name is non-empty', () {
      expect(const DddiceRoom(slug: 'my-slug', name: 'My Room').displayName, equals('My Room'));
    });

    test('returns slug when name is empty', () {
      expect(const DddiceRoom(slug: 'my-slug', name: '').displayName, equals('my-slug'));
    });

    test('slug-only constructor: name defaults to empty so displayName returns slug', () {
      const r = DddiceRoom(slug: 'only-slug', name: '');
      expect(r.displayName, equals('only-slug'));
    });
  });
}

// ─── helpers ──────────────────────────────────────────────────────────────────

const _testToken = 'test-token';
const _testRoom = 'test-room';
const _testTheme = 'my-theme';

DddiceRepository _repo(http.Client client) => DddiceRepository(client);

/// Captures the last HTTP request; returns 200 by default.
http.Client _capture({
  required void Function(http.Request) onRequest,
  int status = 200,
  String body = '{}',
}) =>
    MockClient((req) async {
      onRequest(req);
      return http.Response(body, status);
    });

/// Captures and decodes the JSON body of the last POST request.
Map<String, dynamic>? _captureBody(http.Request req) =>
    req.body.isNotEmpty ? jsonDecode(req.body) as Map<String, dynamic> : null;

// Creates a RollResult with sane defaults for tests that don't care about type.
RollResult _roll({
  RollType type = RollType.sum,
  int result = 7,
  Map<String, int>? rolls,
  String? ruleName,
}) =>
    RollResult(
      rollType: type,
      rollResult: result,
      rolls: rolls ?? {'d1': result},
      ruleName: ruleName,
    );

// ─── tests ────────────────────────────────────────────────────────────────────

void main() {
  _roomDisplayNameTests();

  // ─── fireRoll — HTTP request structure ────────────────────────────────────

  group('fireRoll — HTTP request structure', () {
    test('POSTs to /roll endpoint', () async {
      Uri? captured;
      final repo = _repo(_capture(onRequest: (r) => captured = r.url));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
      );
      expect(captured?.path, endsWith('/roll'));
    });

    test('sends Bearer token in Authorization header', () async {
      String? auth;
      final repo = _repo(_capture(onRequest: (r) => auth = r.headers['authorization']));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
      );
      expect(auth, equals('Bearer $_testToken'));
    });

    test('sends Content-Type: application/json', () async {
      String? ct;
      final repo = _repo(_capture(onRequest: (r) => ct = r.headers['content-type']));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
      );
      expect(ct, equals('application/json'));
    });

    test('body includes room slug', () async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
      );
      expect(body?['room'], equals(_testRoom));
    });

    test('body includes external_id as string timestamp', () async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
      );
      final extId = body?['external_id'];
      expect(extId, isA<String>());
      expect(int.tryParse(extId as String), isNotNull,
          reason: 'external_id should be a numeric timestamp string');
    });

    test('each die entry has type, theme, and value fields', () async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 9)], result: _roll(result: 9),
      );
      final dice = body?['dice'] as List<dynamic>;
      expect(dice, hasLength(1));
      final die = dice.first as Map<String, dynamic>;
      expect(die.containsKey('type'), isTrue);
      expect(die.containsKey('theme'), isTrue);
      expect(die.containsKey('value'), isTrue);
    });

    test('die value matches die face value', () async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      final die = FakeDie('d1', 'd1', 13);
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [die], result: _roll(result: 13),
      );
      final dice = body?['dice'] as List<dynamic>;
      expect((dice.first as Map<String, dynamic>)['value'], equals(13));
    });

    test('die theme matches the theme parameter', () async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: 'cool-theme',
        dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
      );
      final dice = body?['dice'] as List<dynamic>;
      expect((dice.first as Map<String, dynamic>)['theme'], equals('cool-theme'));
    });

    test('multiple dice all appear in body', () async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 3), FakeDie('d2', 'd2', 5)],
        result: _roll(result: 8, rolls: {'d1': 3, 'd2': 5}),
      );
      expect((body?['dice'] as List<dynamic>), hasLength(2));
    });
  });

  // ─── fireRoll — die type mapping ──────────────────────────────────────────

  group('fireRoll — die type mapping', () {
    Future<String> _mappedType(String dName) async {
      String? mappedType;
      final repo = _repo(_capture(
        onRequest: (r) {
          final body = _captureBody(r)!;
          final dice = body['dice'] as List<dynamic>;
          mappedType = (dice.first as Map<String, dynamic>)['type'] as String?;
        },
      ));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d', 'd', 1, dName: dName)], result: _roll(result: 1),
      );
      return mappedType!;
    }

    test('d4 → d4', () async => expect(await _mappedType('d4'), equals('d4')));
    test('d6 → d6', () async => expect(await _mappedType('d6'), equals('d6')));
    test('d8 → d8', () async => expect(await _mappedType('d8'), equals('d8')));
    test('d10 → d10', () async => expect(await _mappedType('d10'), equals('d10')));
    test('d00 → d10x', () async => expect(await _mappedType('d00'), equals('d10x')));
    test('d12 → d12', () async => expect(await _mappedType('d12'), equals('d12')));
    test('d20 → d20', () async => expect(await _mappedType('d20'), equals('d20')));
    test('unknown die type → mod', () async {
      // 'unknown' is a valid GenericDTypeFactory key that maps to a die with name 'unknown'
      expect(await _mappedType('unknown'), equals('mod'));
    });
  });

  // ─── fireRoll — operator ─────────────────────────────────────────────────

  group('fireRoll — operator field', () {
    Future<Map<String, dynamic>?> _rollBody(RollType type) async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 5)], result: _roll(type: type),
      );
      return body;
    }

    test('max roll sends operator k with string key "1"', () async {
      final body = await _rollBody(RollType.max);
      final op = body?['operator'] as Map<String, dynamic>?;
      expect(op, isNotNull);
      expect(op!.containsKey('k'), isTrue);
      final inner = op['k'] as Map<String, dynamic>;
      expect(inner.containsKey('1'), isTrue);
      expect(inner['1'], equals([]));
    });

    test('min roll sends operator d with string key "1"', () async {
      final body = await _rollBody(RollType.min);
      final op = body?['operator'] as Map<String, dynamic>?;
      expect(op, isNotNull);
      expect(op!.containsKey('d'), isTrue);
      final inner = op['d'] as Map<String, dynamic>;
      expect(inner.containsKey('1'), isTrue);
    });

    test('sum roll does NOT send operator', () async {
      final body = await _rollBody(RollType.sum);
      expect(body?.containsKey('operator'), isFalse);
    });

    test('normal roll does NOT send operator', () async {
      final body = await _rollBody(RollType.normal);
      expect(body?.containsKey('operator'), isFalse);
    });

    test('rule roll does NOT send operator', () async {
      final body = await _rollBody(RollType.rule);
      expect(body?.containsKey('operator'), isFalse);
    });
  });

  // ─── fireRoll — label ─────────────────────────────────────────────────────

  group('fireRoll — label field', () {
    test('sends label when ruleName is non-empty', () async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 5)],
        result: _roll(type: RollType.rule, ruleName: 'Crit Check'),
      );
      expect(body?['label'], equals('Crit Check'));
    });

    test('does NOT send label when ruleName is null', () async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 5)], result: _roll(ruleName: null),
      );
      expect(body?.containsKey('label'), isFalse);
    });

    test('does NOT send label when ruleName is empty string', () async {
      Map<String, dynamic>? body;
      final repo = _repo(_capture(onRequest: (r) => body = _captureBody(r)));
      await repo.fireRoll(
        token: _testToken, roomSlug: _testRoom, theme: _testTheme,
        dice: [FakeDie('d1', 'd1', 5)], result: _roll(ruleName: ''),
      );
      expect(body?.containsKey('label'), isFalse);
    });
  });

  // ─── fireRoll — error handling ────────────────────────────────────────────

  group('fireRoll — error handling', () {
    test('throws DddiceAuthException on 401', () async {
      final repo = _repo(MockClient((_) async => http.Response('{}', 401)));
      await expectLater(
        repo.fireRoll(
          token: _testToken, roomSlug: _testRoom, theme: _testTheme,
          dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
        ),
        throwsA(isA<DddiceAuthException>()),
      );
    });

    test('throws DddiceApiException on 4xx (non-401)', () async {
      final repo = _repo(MockClient((_) async => http.Response('{}', 422)));
      await expectLater(
        repo.fireRoll(
          token: _testToken, roomSlug: _testRoom, theme: _testTheme,
          dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
        ),
        throwsA(isA<DddiceApiException>()),
      );
    });

    test('DddiceApiException carries the status code', () async {
      final repo = _repo(MockClient((_) async => http.Response('{}', 422)));
      DddiceApiException? caught;
      try {
        await repo.fireRoll(
          token: _testToken, roomSlug: _testRoom, theme: _testTheme,
          dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
        );
      } on DddiceApiException catch (e) {
        caught = e;
      }
      expect(caught?.statusCode, equals(422));
    });

    test('throws DddiceApiException on 5xx', () async {
      final repo = _repo(MockClient((_) async => http.Response('Server Error', 500)));
      await expectLater(
        repo.fireRoll(
          token: _testToken, roomSlug: _testRoom, theme: _testTheme,
          dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
        ),
        throwsA(isA<DddiceApiException>()),
      );
    });

    test('completes normally on 200', () async {
      final repo = _repo(MockClient((_) async => http.Response('{}', 200)));
      await expectLater(
        repo.fireRoll(
          token: _testToken, roomSlug: _testRoom, theme: _testTheme,
          dice: [FakeDie('d1', 'd1', 5)], result: _roll(),
        ),
        completes,
      );
    });
  });

  // ─── listRooms ────────────────────────────────────────────────────────────

  group('listRooms', () {
    DddiceRepository _roomRepo(http.Client client) => _repo(client);

    test('sends GET to /room endpoint', () async {
      Uri? captured;
      final repo = _roomRepo(_capture(
        onRequest: (r) => captured = r.url,
        body: '{"data":[]}',
      ));
      await repo.listRooms('tok');
      expect(captured?.path, endsWith('/room'));
    });

    test('sends Bearer token in Authorization header', () async {
      String? auth;
      final repo = _roomRepo(_capture(
        onRequest: (r) => auth = r.headers['authorization'],
        body: '{"data":[]}',
      ));
      await repo.listRooms('my-token');
      expect(auth, equals('Bearer my-token'));
    });

    test('returns empty list when data array is empty', () async {
      final repo = _roomRepo(
        MockClient((_) async => http.Response('{"data":[]}', 200)),
      );
      expect(await repo.listRooms('tok'), isEmpty);
    });

    test('parses name and slug from data array', () async {
      final repo = _roomRepo(MockClient((_) async => http.Response(
            jsonEncode({
              'data': [
                {'name': 'Alpha Room', 'slug': 'alpha'},
                {'name': 'Beta Room', 'slug': 'beta'},
              ]
            }),
            200,
          )));
      final rooms = await repo.listRooms('tok');
      expect(rooms, hasLength(2));
      expect(rooms[0].name, equals('Alpha Room'));
      expect(rooms[0].slug, equals('alpha'));
      expect(rooms[1].slug, equals('beta'));
    });

    test('uses custom_slug when slug field is absent', () async {
      final repo = _roomRepo(MockClient((_) async => http.Response(
            jsonEncode({
              'data': [
                {'name': 'Custom Room', 'custom_slug': 'cust-slug'}
              ]
            }),
            200,
          )));
      final rooms = await repo.listRooms('tok');
      expect(rooms, hasLength(1));
      expect(rooms[0].slug, equals('cust-slug'));
    });

    test('uses slug over custom_slug when both present', () async {
      final repo = _roomRepo(MockClient((_) async => http.Response(
            jsonEncode({
              'data': [
                {'name': 'Room', 'slug': 'real-slug', 'custom_slug': 'old-slug'}
              ]
            }),
            200,
          )));
      final rooms = await repo.listRooms('tok');
      expect(rooms[0].slug, equals('real-slug'));
    });

    test('filters out rooms with no usable slug', () async {
      final repo = _roomRepo(MockClient((_) async => http.Response(
            jsonEncode({
              'data': [
                {'name': 'No Slug Room'},
                {'name': 'Good Room', 'slug': 'good'},
              ]
            }),
            200,
          )));
      final rooms = await repo.listRooms('tok');
      expect(rooms, hasLength(1));
      expect(rooms[0].slug, equals('good'));
    });

    test('throws on non-200 status', () async {
      final repo = _roomRepo(MockClient((_) async => http.Response('{}', 401)));
      await expectLater(repo.listRooms('tok'), throwsException);
    });
  });

  // ─── listThemes ───────────────────────────────────────────────────────────

  group('listThemes', () {
    DddiceRepository _themeRepo(http.Client client) => _repo(client);

    test('sends GET to /dice-box endpoint (NOT /theme)', () async {
      Uri? captured;
      final repo = _themeRepo(_capture(
        onRequest: (r) => captured = r.url,
        body: '{"data":[]}',
      ));
      await repo.listThemes('tok');
      expect(captured?.path, endsWith('/dice-box'));
    });

    test('sends Bearer token in Authorization header', () async {
      String? auth;
      final repo = _themeRepo(_capture(
        onRequest: (r) => auth = r.headers['authorization'],
        body: '{"data":[]}',
      ));
      await repo.listThemes('my-token');
      expect(auth, equals('Bearer my-token'));
    });

    test('returns empty list when data array is empty', () async {
      final repo = _themeRepo(
        MockClient((_) async => http.Response('{"data":[]}', 200)),
      );
      expect(await repo.listThemes('tok'), isEmpty);
    });

    test('parses id and name from data array', () async {
      final repo = _themeRepo(MockClient((_) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 'theme-abc', 'name': 'Cool Theme'},
                {'id': 'theme-xyz', 'name': 'Other Theme'},
              ]
            }),
            200,
          )));
      final themes = await repo.listThemes('tok');
      expect(themes, hasLength(2));
      expect(themes[0].id, equals('theme-abc'));
      expect(themes[0].name, equals('Cool Theme'));
    });

    test('filters out themes with empty id', () async {
      final repo = _themeRepo(MockClient((_) async => http.Response(
            jsonEncode({
              'data': [
                {'id': '', 'name': 'Bad Theme'},
                {'id': 'good-id', 'name': 'Good Theme'},
              ]
            }),
            200,
          )));
      final themes = await repo.listThemes('tok');
      expect(themes, hasLength(1));
      expect(themes[0].id, equals('good-id'));
    });

    test('throws on non-200 status', () async {
      final repo = _themeRepo(MockClient((_) async => http.Response('{}', 403)));
      await expectLater(repo.listThemes('tok'), throwsException);
    });
  });

  // ─── createGuestUser ──────────────────────────────────────────────────────

  group('createGuestUser', () {
    DddiceRepository _guestRepo(http.Client client) => _repo(client);

    test('sends POST to /user endpoint', () async {
      Uri? captured;
      final repo = _guestRepo(_capture(
        onRequest: (r) => captured = r.url,
        status: 201,
        body: '{"token":"t"}',
      ));
      await repo.createGuestUser();
      expect(captured?.path, endsWith('/user'));
    });

    test('does NOT send Authorization header', () async {
      String? auth;
      final repo = _guestRepo(_capture(
        onRequest: (r) => auth = r.headers['authorization'],
        status: 201,
        body: '{"token":"t"}',
      ));
      await repo.createGuestUser();
      expect(auth, isNull);
    });

    test('returns token from top-level response field', () async {
      final repo = _guestRepo(
        MockClient((_) async => http.Response('{"token":"top-level-tok"}', 201)),
      );
      expect(await repo.createGuestUser(), equals('top-level-tok'));
    });

    test('returns token from data as bare string (actual API response format)', () async {
      final repo = _guestRepo(MockClient((_) async => http.Response(
            jsonEncode({'type': 'token', 'data': 'bare-string-tok'}),
            201,
          )));
      expect(await repo.createGuestUser(), equals('bare-string-tok'));
    });

    test('returns token from data.token fallback when data is a map', () async {
      final repo = _guestRepo(MockClient((_) async => http.Response(
            jsonEncode({'data': {'token': 'nested-tok'}}),
            201,
          )));
      expect(await repo.createGuestUser(), equals('nested-tok'));
    });

    test('returns token from 200 response (not just 201)', () async {
      final repo = _guestRepo(
        MockClient((_) async => http.Response('{"token":"tok-200"}', 200)),
      );
      expect(await repo.createGuestUser(), equals('tok-200'));
    });

    test('returns null when neither token field exists', () async {
      final repo = _guestRepo(
        MockClient((_) async => http.Response('{"user":{"name":"guest"}}', 201)),
      );
      expect(await repo.createGuestUser(), isNull);
    });

    test('returns null on 4xx response', () async {
      final repo = _guestRepo(
        MockClient((_) async => http.Response('{}', 429)),
      );
      expect(await repo.createGuestUser(), isNull);
    });

    test('returns null without throwing on network error', () async {
      final repo = _guestRepo(
        MockClient((_) async => throw Exception('network down')),
      );
      await expectLater(repo.createGuestUser(), completion(isNull));
    });
  });

  // ─── createActivationCode ─────────────────────────────────────────────────

  group('createActivationCode', () {
    DddiceRepository _activateRepo(http.Client client) => _repo(client);

    test('sends POST to /activate endpoint', () async {
      Uri? captured;
      final repo = _activateRepo(_capture(
        onRequest: (r) => captured = r.url,
        status: 201,
        body: jsonEncode({'data': {'code': 'ABCD', 'secret': 'shhh'}}),
      ));
      await repo.createActivationCode();
      expect(captured?.path, endsWith('/activate'));
    });

    test('does NOT send Authorization header', () async {
      String? auth;
      final repo = _activateRepo(_capture(
        onRequest: (r) => auth = r.headers['authorization'],
        status: 201,
        body: jsonEncode({'data': {'code': 'ABCD', 'secret': 'shhh'}}),
      ));
      await repo.createActivationCode();
      expect(auth, isNull);
    });

    test('returns code and secret from response.data', () async {
      final repo = _activateRepo(MockClient((_) async => http.Response(
            jsonEncode({'data': {'code': 'CODE1', 'secret': 'SEC1'}}),
            201,
          )));
      final result = await repo.createActivationCode();
      expect(result?.code, equals('CODE1'));
      expect(result?.secret, equals('SEC1'));
    });

    test('returns code and secret from top-level response when no data wrapper', () async {
      final repo = _activateRepo(MockClient((_) async => http.Response(
            jsonEncode({'code': 'CODE2', 'secret': 'SEC2'}),
            201,
          )));
      final result = await repo.createActivationCode();
      expect(result?.code, equals('CODE2'));
      expect(result?.secret, equals('SEC2'));
    });

    test('returns null when code field is missing', () async {
      final repo = _activateRepo(MockClient((_) async => http.Response(
            jsonEncode({'secret': 'SEC'}),
            201,
          )));
      expect(await repo.createActivationCode(), isNull);
    });

    test('returns null when secret field is missing', () async {
      final repo = _activateRepo(MockClient((_) async => http.Response(
            jsonEncode({'code': 'CODE'}),
            201,
          )));
      expect(await repo.createActivationCode(), isNull);
    });

    test('returns null on 4xx response', () async {
      final repo = _activateRepo(
        MockClient((_) async => http.Response('{}', 400)),
      );
      expect(await repo.createActivationCode(), isNull);
    });

    test('returns null without throwing on network error', () async {
      final repo = _activateRepo(
        MockClient((_) async => throw Exception('network down')),
      );
      await expectLater(repo.createActivationCode(), completion(isNull));
    });
  });

  // ─── pollActivation ───────────────────────────────────────────────────────

  group('pollActivation', () {
    DddiceRepository _pollRepo(http.Client client) => _repo(client);

    test('sends GET to /activate/{code}', () async {
      Uri? captured;
      final repo = _pollRepo(_capture(
        onRequest: (r) => captured = r.url,
        body: jsonEncode({'data': {'token': 'tok'}}),
      ));
      await repo.pollActivation('MY-CODE', 'my-secret');
      expect(captured?.path, endsWith('/activate/MY-CODE'));
    });

    test('sends Authorization: Secret <secret> header', () async {
      String? auth;
      final repo = _pollRepo(_capture(
        onRequest: (r) => auth = r.headers['authorization'],
        body: jsonEncode({'data': {'token': 'tok'}}),
      ));
      await repo.pollActivation('CODE', 'my-secret');
      expect(auth, equals('Secret my-secret'));
    });

    test('does NOT send Bearer token', () async {
      String? auth;
      final repo = _pollRepo(_capture(
        onRequest: (r) => auth = r.headers['authorization'],
        body: jsonEncode({'data': {'token': 'tok'}}),
      ));
      await repo.pollActivation('CODE', 'my-secret');
      expect(auth, isNot(startsWith('Bearer')));
    });

    test('returns token from data.token when activation complete', () async {
      final repo = _pollRepo(MockClient((_) async => http.Response(
            jsonEncode({'data': {'token': 'final-tok'}}),
            200,
          )));
      expect(await repo.pollActivation('CODE', 'secret'), equals('final-tok'));
    });

    test('returns token from top-level when no data wrapper', () async {
      final repo = _pollRepo(MockClient((_) async => http.Response(
            jsonEncode({'token': 'top-tok'}),
            200,
          )));
      expect(await repo.pollActivation('CODE', 'secret'), equals('top-tok'));
    });

    test('returns null on non-200 status (activation pending)', () async {
      final repo = _pollRepo(MockClient((_) async => http.Response('{}', 202)));
      expect(await repo.pollActivation('CODE', 'secret'), isNull);
    });

    test('returns null when data has no token field', () async {
      final repo = _pollRepo(MockClient((_) async => http.Response(
            jsonEncode({'data': {'status': 'pending'}}),
            200,
          )));
      expect(await repo.pollActivation('CODE', 'secret'), isNull);
    });

    test('throws on network error so caller can distinguish failure from pending', () async {
      final repo = _pollRepo(
        MockClient((_) async => throw Exception('network down')),
      );
      await expectLater(repo.pollActivation('CODE', 'secret'), throwsException);
    });
  });

  // ─── joinRoom ─────────────────────────────────────────────────────────────

  group('joinRoom', () {
    DddiceRepository _joinRepo(http.Client client) => _repo(client);

    test('sends POST to /room/{slug}/participant', () async {
      Uri? captured;
      final repo = _joinRepo(_capture(onRequest: (r) => captured = r.url));
      await repo.joinRoom('tok', 'my-room');
      expect(captured?.path, endsWith('/room/my-room/participant'));
    });

    test('sends Bearer token in Authorization header', () async {
      String? auth;
      final repo = _joinRepo(
          _capture(onRequest: (r) => auth = r.headers['authorization']));
      await repo.joinRoom('my-tok', 'room');
      expect(auth, equals('Bearer my-tok'));
    });

    test('completes normally on 200', () async {
      final repo = _joinRepo(MockClient((_) async => http.Response('{}', 200)));
      await expectLater(repo.joinRoom('tok', 'room'), completes);
    });

    test('completes normally on 409 (already a participant)', () async {
      final repo = _joinRepo(MockClient(
          (_) async => http.Response('{"data":{"message":"Room participant already exists"}}', 409)));
      await expectLater(repo.joinRoom('tok', 'room'), completes);
    });

    test('throws on 403', () async {
      final repo = _joinRepo(MockClient(
          (_) async => http.Response('{"data":{"message":"Forbidden"}}', 403)));
      await expectLater(repo.joinRoom('tok', 'room'), throwsException);
    });

    test('throws on other 4xx', () async {
      final repo = _joinRepo(MockClient((_) async => http.Response('{}', 400)));
      await expectLater(repo.joinRoom('tok', 'room'), throwsException);
    });
  });
}
