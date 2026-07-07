import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:roll_feathers/domains/library/editable_library.dart';
import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';

/// Repository over webhook payload templates — the [LibraryRepository] contract
/// (built-in catalog + user items) plus name resolution. Load/save/query only.
abstract class WebhookPayloadRepository implements LibraryRepository<PayloadTemplate> {
  /// Built-in payloads (shipped in code, read-only).
  @override
  List<PayloadTemplate> builtins();

  @override
  Future<List<PayloadTemplate>> loadUserItems();
  @override
  Future<void> upsert(PayloadTemplate item);
  @override
  Future<void> delete(String id);

  /// Resolve a payload for a DSL `with <name>` / target-keyword reference: by
  /// id first, then by name, across built-ins then user items. Null if missing.
  Future<PayloadTemplate?> byName(String ref);
}

/// [WebhookPayloadRepository] backed by [SharedPreferences] for user items and
/// [kBuiltinPayloads] for the built-in catalog.
class SharedPrefsWebhookPayloadRepository implements WebhookPayloadRepository {
  static const _prefsKey = 'webhook_payloads';

  @override
  List<PayloadTemplate> builtins() => kBuiltinPayloads;

  @override
  Future<List<PayloadTemplate>> loadUserItems() async {
    final prefs = SharedPreferencesAsync();
    final raw = await prefs.getString(_prefsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((j) => PayloadTemplate.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> _saveAll(List<PayloadTemplate> items) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_prefsKey, jsonEncode(items.map((p) => p.toJson()).toList()));
  }

  @override
  Future<void> upsert(PayloadTemplate item) async {
    final items = await loadUserItems();
    final idx = items.indexWhere((p) => p.id == item.id);
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.add(item);
    }
    await _saveAll(items);
  }

  @override
  Future<void> delete(String id) async {
    final items = await loadUserItems();
    items.removeWhere((p) => p.id == id);
    await _saveAll(items);
  }

  @override
  Future<PayloadTemplate?> byName(String ref) async {
    for (final b in builtins()) {
      if (b.id == ref || b.name == ref) return b;
    }
    for (final u in await loadUserItems()) {
      if (u.id == ref || u.name == ref) return u;
    }
    return null;
  }
}
