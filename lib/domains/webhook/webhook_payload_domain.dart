import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_context.dart';
import 'package:roll_feathers/domains/webhook/payload_renderer.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/domains/webhook/webhook_send.dart';
import 'package:roll_feathers/repositories/webhook/webhook_payload_repository.dart';

/// The result of rendering a template for the editor preview.
class PreviewResult {
  final String? output;
  final String? error;

  const PreviewResult.success(this.output) : error = null;
  const PreviewResult.failure(this.error) : output = null;

  bool get ok => error == null;
}

/// Orchestrates webhook payload templates for the editor UI (UI → domain → repo).
/// No firing here — that's [WebhookDomain]; this is CRUD + preview + validation.
class WebhookPayloadDomain {
  final WebhookPayloadRepository _repo;
  final http.Client? _client;
  static const _uuid = Uuid();

  WebhookPayloadDomain(this._repo, {http.Client? client}) : _client = client;

  List<PayloadTemplate> builtins() => _repo.builtins();
  Future<List<PayloadTemplate>> loadUserPayloads() => _repo.loadUserItems();
  Future<void> save(PayloadTemplate p) => _repo.upsert(p);
  Future<void> delete(String id) => _repo.delete(id);

  /// A copy of [p] as a fresh user item (new id, "(copy)" name, editable).
  PayloadTemplate duplicate(PayloadTemplate p) => p.copyWith(
        id: _uuid.v4(),
        name: '${p.name} (copy)',
        isBuiltin: false,
      );

  /// A blank user payload seeded with the Generic JSON body (a valid start point);
  /// falls back to an empty JSON object if that built-in is ever absent.
  PayloadTemplate newBlank() {
    final generic = builtins().where((p) => p.id == 'generic');
    return PayloadTemplate(
      id: _uuid.v4(),
      name: 'New Payload',
      body: generic.isEmpty ? '{}' : generic.first.body,
    );
  }

  /// Render [t] against the canned sample (or a supplied [context]) for the live
  /// preview: pretty-printed JSON, or an error message.
  PreviewResult preview(PayloadTemplate t, {PayloadContext? context}) {
    try {
      final out = PayloadRenderer.render(
        t.body,
        context ?? PayloadContext.sample,
        t.format,
        pretty: t.format == PayloadFormat.json,
      );
      return PreviewResult.success(out);
    } on PayloadRenderException catch (e) {
      return PreviewResult.failure(e.message);
    }
  }

  /// Renders [t] against the sample and actually sends it to [url] (a live test
  /// during authoring, so CORS/endpoint problems surface now). Returns a short
  /// human status. Ignores the global webhooks-enabled toggle — it's explicit.
  Future<String> testSend(PayloadTemplate t, String url, {PayloadContext? context}) async {
    if (url.trim().isEmpty) return 'Enter a URL to test.';
    if (!isAllowedWebhookUrl(url)) return 'Enter a valid http(s) URL.';
    final String body;
    try {
      body = PayloadRenderer.render(t.body, context ?? PayloadContext.sample, t.format);
    } on PayloadRenderException catch (e) {
      return 'Payload error: ${e.message}';
    }
    final client = _client ?? http.Client();
    final ua = <String, String>{'User-Agent': webhookUserAgent()};
    try {
      final http.Response resp;
      if (t.isGet) {
        resp = await client.get(buildGetUri(url, body), headers: {...ua, ...t.headers}).timeout(kWebhookTimeout);
      } else {
        final headers = <String, String>{...ua, ...t.headers, 'Content-Type': t.effectiveContentType};
        resp = await client.post(Uri.parse(url), headers: headers, body: body).timeout(kWebhookTimeout);
      }
      final ok = resp.statusCode < 400;
      return '${ok ? '✓ Sent' : '✗ Failed'} — HTTP ${resp.statusCode}';
    } on http.ClientException catch (e) {
      // e.toString() includes the request URI (which may embed a secret); show
      // only the message, not the URL.
      return 'Send failed: ${e.message}';
    } on Exception catch (e) {
      return 'Send failed: $e';
    } finally {
      if (_client == null) client.close();
    }
  }

  bool isReserved(String name) => kReservedPayloadNames.contains(name);

  /// A built-in or another user payload already uses [name] (or it's reserved).
  Future<bool> isNameTaken(String name, {String? excludeId}) async {
    if (isReserved(name)) return true;
    final users = await loadUserPayloads();
    return users.any((p) => p.name == name && p.id != excludeId);
  }
}
