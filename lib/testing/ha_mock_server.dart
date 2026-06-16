import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// In-process mock of the subset of the Home Assistant REST API
/// (`/api/states/<entityId>`, `/api/services/<domain>/<service>`) that
/// [HaApiService] talks to.
///
/// Point `HaConfigService.setConfig(HaConfig(url: mock.baseUrl, ...))` at
/// [baseUrl] instead of a real Home Assistant instance. Entity state is
/// in-memory and stateful: [seedState] sets up the state a test starts from,
/// and every `turn_on`/`turn_off` service call updates it, so a test can poll
/// state before and after calling [HaApiService] methods. Works as a plain
/// Dart VM fixture in `test/`, the same way [DddiceMockServer] does for the
/// dddice API.
///
/// Usage:
/// ```dart
/// final mock = HaMockServer();
/// await mock.start();
/// mock.seedState('light.test', state: 'off');
/// // point HaConfigService at mock.baseUrl, then exercise HaApiService...
/// expect(mock.serviceCalls, isNotEmpty);
/// await mock.close();
/// ```
class HaMockServer {
  static const _jsonHeaders = {'content-type': 'application/json'};

  HttpServer? _server;

  final Map<String, HaEntityState> _entities = {};
  final List<HaServiceCall> serviceCalls = [];

  /// Base URL to hand to `HaConfig(url: ...)`. Only valid after [start].
  String get baseUrl {
    final server = _server;
    if (server == null) throw StateError('HaMockServer has not been started');
    return 'http://127.0.0.1:${server.port}';
  }

  /// Starts the server. Pass a fixed [port] only if it must be known ahead
  /// of time; an ephemeral port (the default) is all a unit test needs.
  Future<void> start({int port = 0}) async {
    final router = Router()
      ..get('/api/states/<entityId>', (Request r, String entityId) => _getState(entityId))
      ..post('/api/services/<domain>/<service>',
          (Request r, String domain, String service) async => _postService(domain, service, r));

    _server = await shelf_io.serve(router.call, InternetAddress.loopbackIPv4, port);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ─── test control ─────────────────────────────────────────────────────────

  /// Sets the state [HaApiService] will see for [entityId] until a service
  /// call changes it.
  void seedState(String entityId, {String state = 'off', Map<String, dynamic> attributes = const {}}) {
    _entities[entityId] = HaEntityState(state, attributes);
  }

  /// Current in-memory state for [entityId], or null if never seeded/set.
  HaEntityState? stateOf(String entityId) => _entities[entityId];

  // ─── route handlers ───────────────────────────────────────────────────────

  Response _getState(String entityId) {
    final entity = _entities[entityId];
    if (entity == null) {
      return Response.notFound(jsonEncode({'message': 'Entity not found'}), headers: _jsonHeaders);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    return Response.ok(
      jsonEncode({
        'entity_id': entityId,
        'state': entity.state,
        'attributes': entity.attributes,
        'last_changed': now,
        'last_updated': now,
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _postService(String domain, String service, Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    serviceCalls.add(HaServiceCall(domain, service, body));

    final entityId = body['entity_id'] as String?;
    if (entityId != null) {
      final isOn = service == 'turn_on';
      _entities[entityId] = HaEntityState(
        isOn ? 'on' : 'off',
        isOn ? (Map<String, dynamic>.from(body)..remove('entity_id')) : const {},
      );
    }

    return Response.ok(jsonEncode([]), headers: _jsonHeaders);
  }
}

class HaEntityState {
  final String state;
  final Map<String, dynamic> attributes;
  HaEntityState(this.state, this.attributes);
}

/// A recorded `POST /api/services/<domain>/<service>` call, for assertions
/// like "blinkLightEntity turned the light on with the requested color".
class HaServiceCall {
  final String domain;
  final String service;
  final Map<String, dynamic> body;
  HaServiceCall(this.domain, this.service, this.body);
}
