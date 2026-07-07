import 'package:uuid/uuid.dart';

import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_context.dart';
import 'package:roll_feathers/domains/webhook/payload_renderer.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';
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
  static const _uuid = Uuid();

  WebhookPayloadDomain(this._repo);

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

  /// A blank user payload seeded with the Generic JSON body (a valid start point).
  PayloadTemplate newBlank() => PayloadTemplate(
        id: _uuid.v4(),
        name: 'New Payload',
        body: builtins().firstWhere((p) => p.id == 'generic').body,
      );

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

  bool isReserved(String name) => kReservedPayloadNames.contains(name);

  /// A built-in or another user payload already uses [name] (or it's reserved).
  Future<bool> isNameTaken(String name, {String? excludeId}) async {
    if (isReserved(name)) return true;
    final users = await loadUserPayloads();
    return users.any((p) => p.name == name && p.id != excludeId);
  }
}
