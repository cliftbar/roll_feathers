import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';

class DddiceRoom {
  final String slug;
  final String name;
  const DddiceRoom({required this.slug, required this.name});

  String get displayName => name.isNotEmpty ? name : slug;
}

class DddiceTheme {
  final String id;
  final String name;
  const DddiceTheme({required this.id, required this.name});
}

class DddiceActivationCode {
  final String code;
  final String secret;
  const DddiceActivationCode({required this.code, required this.secret});
}

/// Thrown when the dddice API returns 401.
class DddiceAuthException implements Exception {
  const DddiceAuthException();
}

/// Thrown when the dddice API returns an unexpected non-200 status.
class DddiceApiException implements Exception {
  final int statusCode;
  const DddiceApiException(this.statusCode);
  @override
  String toString() => 'DddiceApiException($statusCode)';
}

class DddiceRepository {
  static const _defaultBase = 'https://dddice.com/api/1.0';

  final String _base;
  final http.Client _client;
  final _log = Logger('DddiceRepository');

  /// [baseUrl] lets tests point the repository at a local mock server (see
  /// `lib/testing/dddice_mock_server.dart`) instead of the real dddice API.
  DddiceRepository(this._client, {String? baseUrl}) : _base = baseUrl ?? _defaultBase;

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  String _dddiceType(GenericDType dtype) {
    return switch (dtype.name) {
      'd4' => 'd4',
      'd6' => 'd6',
      'd8' => 'd8',
      'd10' => 'd10',
      'd00' => 'd10x',
      'd12' => 'd12',
      'd20' => 'd20',
      _ => 'mod',
    };
  }

  Map<String, dynamic>? _operator(RollType rollType) {
    return switch (rollType) {
      RollType.max => {
          'k': {'1': []}
        },
      RollType.min => {
          'd': {'1': []}
        },
      _ => null,
    };
  }

  /// Joins [roomSlug] as a participant using [token].
  /// Treats 409 (already a participant) as success.
  /// Throws on network errors; returns normally on success.
  Future<void> joinRoom(String token, String roomSlug) async {
    final response = await _client.post(
      Uri.parse('$_base/room/$roomSlug/participant'),
      headers: _authHeaders(token),
      body: '{}',
    );
    if (response.statusCode == 409) return; // already joined
    if (response.statusCode >= 400) {
      throw Exception('joinRoom failed: ${response.statusCode}');
    }
  }

  /// Fires a roll to the dddice API.
  /// Throws [DddiceAuthException] on 401, [DddiceApiException] on other 4xx/5xx.
  Future<void> fireRoll({
    required String token,
    required String roomSlug,
    required String theme,
    required List<GenericDie> dice,
    required RollResult result,
  }) async {
    final mappedDice = dice.map((d) => {
          'type': _dddiceType(d.dType),
          'theme': theme,
          'value': d.getFaceValueOrElse(),
        }).toList();

    final body = <String, dynamic>{
      'room': roomSlug,
      'dice': mappedDice,
      'external_id': result.rollTime.millisecondsSinceEpoch.toString(),
    };
    final op = _operator(result.rollType);
    if (op != null) body['operator'] = op;
    final ruleName = result.ruleName;
    if (ruleName != null && ruleName.isNotEmpty) body['label'] = ruleName;

    final response = await _client.post(
      Uri.parse('$_base/roll'),
      headers: _authHeaders(token),
      body: jsonEncode(body),
    );
    if (response.statusCode == 401) throw const DddiceAuthException();
    if (response.statusCode >= 400) throw DddiceApiException(response.statusCode);
  }

  Future<List<DddiceRoom>> listRooms(String token) async {
    final response = await _client.get(
      Uri.parse('$_base/room'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('listRooms failed: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];
    return data
        .cast<Map<String, dynamic>>()
        .map((r) => DddiceRoom(
              slug: r['slug'] as String? ?? r['custom_slug'] as String? ?? '',
              name: r['name'] as String? ?? '',
            ))
        .where((r) => r.slug.isNotEmpty)
        .toList();
  }

  Future<List<DddiceTheme>> listThemes(String token) async {
    final response = await _client.get(
      Uri.parse('$_base/dice-box'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('listThemes failed: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];
    return data
        .cast<Map<String, dynamic>>()
        .map((t) => DddiceTheme(
              id: t['id'] as String? ?? '',
              name: t['name'] as String? ?? '',
            ))
        .where((t) => t.id.isNotEmpty)
        .toList();
  }

  /// Creates a new room for the given [token]. Returns the created room on
  /// success, or null if the request fails (caller may continue without a room).
  Future<DddiceRoom?> createRoom(String token) async {
    try {
      final response = await _client.post(
        Uri.parse('$_base/room'),
        headers: _authHeaders(token),
        body: '{}',
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        _log.warning('createRoom failed: ${response.statusCode}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      final slug =
          data?['slug'] as String? ?? data?['custom_slug'] as String?;
      final name = data?['name'] as String?;
      if (slug == null || slug.isEmpty) {
        _log.warning('createRoom: no slug in response');
        return null;
      }
      return DddiceRoom(slug: slug, name: name ?? slug);
    } catch (e, st) {
      _log.warning('createRoom error', e, st);
      return null;
    }
  }

  Future<String?> createGuestUser() async {
    try {
      final response = await _client.post(
        Uri.parse('$_base/user'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      );
      if (response.statusCode != 201 && response.statusCode != 200) {
        _log.warning('createGuestUser failed: ${response.statusCode}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // API returns {"type":"token","data":"<token>"} — data is a bare string
      final data = json['data'];
      final token = json['token'] as String? ??
          (data is String ? data : (data as Map<String, dynamic>?)?['token'] as String?);
      if (token == null) {
        _log.warning('createGuestUser: no token in response');
      }
      return token;
    } catch (e, st) {
      _log.warning('createGuestUser error', e, st);
      return null;
    }
  }

  Future<DddiceActivationCode?> createActivationCode() async {
    try {
      final response = await _client.post(
        Uri.parse('$_base/activate'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      );
      if (response.statusCode != 201 && response.statusCode != 200) {
        _log.warning('createActivationCode failed: ${response.statusCode}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final code = data['code'] as String?;
      final secret = data['secret'] as String?;
      if (code == null || secret == null) {
        _log.warning('createActivationCode: missing code or secret in response');
        return null;
      }
      return DddiceActivationCode(code: code, secret: secret);
    } catch (e, st) {
      _log.warning('createActivationCode error', e, st);
      return null;
    }
  }

  /// Returns the token string when activation is complete, or null when still
  /// pending (non-200 response). Throws on network or parse errors so callers
  /// can distinguish a transient failure from "not ready yet".
  Future<String?> pollActivation(String code, String secret) async {
    final response = await _client.get(
      Uri.parse('$_base/activate/$code'),
      headers: {
        'Authorization': 'Secret $secret',
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return data['token'] as String?;
  }
}
