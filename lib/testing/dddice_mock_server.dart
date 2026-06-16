import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// In-process mock of the subset of the dddice API
/// (https://docs.dddice.com/api/) that [DddiceRepository] talks to.
///
/// Lets tests drive the full activation/guest/roll flow deterministically,
/// without a real dddice account or live network access. Works as a plain
/// Dart VM fixture in `test/`, and equally inside an `integration_test`
/// binary running on-device (Android/iOS/macOS) — the app under test reaches
/// it over loopback since both share the same process.
///
/// The activation flow is stateful (pending -> complete): rather than an
/// HTTP admin endpoint, [completeActivation] is a plain method call, since
/// the test, the mock server, and (for integration tests) the app under
/// test all run in the same Dart isolate.
///
/// Usage:
/// ```dart
/// final mock = DddiceMockServer();
/// await mock.start();
/// final repo = DddiceRepository(http.Client(), baseUrl: mock.baseUrl);
/// final code = await repo.createActivationCode();
/// mock.completeActivation(code!.code, token: 'fake-token');
/// final token = await repo.pollActivation(code.code, code.secret);
/// await mock.close();
/// ```
class DddiceMockServer {
  static const _jsonHeaders = {'content-type': 'application/json'};

  HttpServer? _server;
  final _random = Random();

  final Map<String, _PendingActivation> _activations = {};
  final List<Map<String, String>> _rooms = [];
  final List<Map<String, String>> _themes = [
    {'id': 'theme-mock-1', 'name': 'Mock Theme'},
  ];
  int _roomSeq = 0;

  /// Base URL to hand to `DddiceRepository(client, baseUrl: ...)`.
  /// Only valid after [start] completes.
  String get baseUrl {
    final server = _server;
    if (server == null) throw StateError('DddiceMockServer has not been started');
    return 'http://127.0.0.1:${server.port}/api/1.0';
  }

  /// Starts the server. Pass a fixed [port] when the app's base URL must be
  /// known before the app is launched (e.g. baked into a --dart-define for
  /// a live integration test); omit it (or pass 0) for an ephemeral port,
  /// which is all a unit test needs since it wires the repository directly.
  Future<void> start({int port = 0}) async {
    final router = Router()
      ..post('/api/1.0/activate', (Request r) async => _createActivation())
      ..get('/api/1.0/activate/<code>', (Request r, String code) async => _pollActivation(code, r))
      ..post('/api/1.0/user', (Request r) async => _createGuestUser())
      ..post('/api/1.0/room', (Request r) async => _createRoom())
      ..get('/api/1.0/room', (Request r) async => _listRooms())
      ..post('/api/1.0/room/<slug>/participant', (Request r, String slug) async => _joinRoom(slug))
      ..get('/api/1.0/dice-box', (Request r) async => _listThemes())
      ..post('/api/1.0/roll', (Request r) async => _fireRoll());

    _server = await shelf_io.serve(router.call, InternetAddress.loopbackIPv4, port);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ─── test control ─────────────────────────────────────────────────────────

  /// Completes a pending activation [code], so the next `pollActivation`
  /// call returns [token]. Throws [ArgumentError] if [code] is unknown.
  void completeActivation(String code, {String token = 'mock-dddice-token'}) {
    final activation = _activations[code];
    if (activation == null) throw ArgumentError('Unknown activation code: $code');
    activation.token = token;
  }

  // ─── route handlers ───────────────────────────────────────────────────────

  Response _createActivation() {
    final code = _uniqueActivationCode();
    final secret = _randomHex(32);
    _activations[code] = _PendingActivation(secret);
    return Response(201,
        body: jsonEncode({
          'data': {'code': code, 'secret': secret}
        }),
        headers: _jsonHeaders);
  }

  Response _pollActivation(String code, Request request) {
    final activation = _activations[code];
    if (activation == null) {
      return Response.notFound(jsonEncode({'data': 'unknown code'}), headers: _jsonHeaders);
    }
    if (request.headers['authorization'] != 'Secret ${activation.secret}') {
      return Response(401, body: jsonEncode({'data': 'invalid secret'}), headers: _jsonHeaders);
    }
    final token = activation.token;
    if (token == null) {
      return Response(202, body: jsonEncode({'data': 'pending'}), headers: _jsonHeaders);
    }
    return Response.ok(
      jsonEncode({
        'data': {'token': token}
      }),
      headers: _jsonHeaders,
    );
  }

  Response _createGuestUser() {
    final token = 'mock-guest-${_randomHex(8)}';
    // Real API shape: {"type":"token","data":"<token>"} — data is a bare string.
    return Response(201, body: jsonEncode({'type': 'token', 'data': token}), headers: _jsonHeaders);
  }

  Response _createRoom() {
    final room = {'slug': 'mock-room-${++_roomSeq}', 'name': 'Mock Room $_roomSeq'};
    _rooms.add(room);
    return Response(201, body: jsonEncode({'data': room}), headers: _jsonHeaders);
  }

  Response _listRooms() =>
      Response.ok(jsonEncode({'data': _rooms}), headers: _jsonHeaders);

  Response _listThemes() =>
      Response.ok(jsonEncode({'data': _themes}), headers: _jsonHeaders);

  Response _joinRoom(String slug) => Response.ok('{}', headers: _jsonHeaders);

  Response _fireRoll() => Response.ok('{}', headers: _jsonHeaders);

  // ─── helpers ──────────────────────────────────────────────────────────────

  String _uniqueActivationCode() {
    String code;
    do {
      code = _randomCode();
    } while (_activations.containsKey(code));
    return code;
  }

  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String _randomCode({int length = 6}) =>
      List.generate(length, (_) => _codeChars[_random.nextInt(_codeChars.length)]).join();

  String _randomHex(int length) =>
      List.generate(length, (_) => _random.nextInt(16).toRadixString(16)).join();
}

class _PendingActivation {
  final String secret;
  String? token;
  _PendingActivation(this.secret);
}
