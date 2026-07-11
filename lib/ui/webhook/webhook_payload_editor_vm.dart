import 'package:async/async.dart';
import 'package:flutter/foundation.dart';

import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/domains/webhook/webhook_payload_domain.dart';
import 'package:roll_feathers/util/command.dart';

/// ViewModel for the payload editor (MVVM + Command). Holds the editable draft,
/// recomputes the live preview + validation on change, and saves.
class WebhookPayloadEditorViewModel extends ChangeNotifier {
  final WebhookPayloadDomain _domain;
  final String _id;
  final bool isBuiltin;

  String name;
  String method;
  PayloadFormat format;
  String? contentType;
  final Map<String, String> headers;
  String body;

  late final Command0 save;
  late final Command0 testSend;

  PreviewResult _preview = const PreviewResult.success('');
  PreviewResult get preview => _preview;

  /// True once the user has changed anything — drives the unsaved-changes guard.
  /// Reset after a successful save.
  bool dirty = false;

  String? _nameError;
  String? get nameError => _nameError;

  /// Effective request Content-Type (override, else the format default) — a getter
  /// so the UI doesn't allocate a PayloadTemplate every rebuild just to show it.
  String get effectiveContentType => contentType ?? format.defaultContentType;

  /// The token a rule uses to reference this payload: `webhook <url> with <ref>`.
  /// Built-ins reference by their stable id (e.g. `generic`); user payloads by
  /// name. Empty until the payload has a usable name.
  String get reference => isBuiltin ? _id : name.trim();

  /// The full DSL fragment to paste after a webhook URL in a rule.
  String get ruleFragment => 'with $reference';

  /// URL for the "Test send" affordance, and the last result.
  String testUrl = '';
  String? _testResult;
  String? get testResult => _testResult;

  WebhookPayloadEditorViewModel(this._domain, PayloadTemplate initial)
      : _id = initial.id,
        isBuiltin = initial.isBuiltin,
        name = initial.name,
        method = initial.method,
        format = initial.format,
        contentType = initial.contentType,
        headers = Map.of(initial.headers),
        body = initial.body {
    _recompute();
    _validateNameSync();
    save = Command0(_save);
    testSend = Command0(_testSend);
  }

  void setTestUrl(String v) {
    testUrl = v;
    // A prior send result no longer describes the URL you're about to hit.
    if (_testResult != null) {
      _testResult = null;
      notifyListeners();
    }
  }

  /// Marks the draft dirty and clears any stale test-send result, since the
  /// rendered payload has changed. Call from every payload-mutating setter.
  void _touched() {
    dirty = true;
    _testResult = null;
  }

  Future<Result<void>> _testSend() async {
    _testResult = 'Sending…';
    notifyListeners();
    _testResult = await _domain.testSend(build(), testUrl.trim());
    notifyListeners();
    return Result.value(null);
  }

  /// The available substitution tokens, grouped, for the helper palette.
  Map<String, List<String>> get variablePalette => const {
        'Roll': ['{{rule.name}}', '{{rule.displayName}}', '{{aggregate}}', '{{timestamp}}', '{{rollType}}'],
        'Match': ['{{matched.start}}', '{{matched.end}}'],
        'Die (single / in loop)': ['{{die.name}}', '{{die.value}}', '{{die.type}}', '{{die.battery}}', '{{die.color}}', '{{die.colorInt}}'],
        'Dice (collection)': ['{{resultDice.count}}', '{{resultDice.names}}', '{{resultDice.values}}', '{{resultDice.json}}'],
        'Loops / conditionals': ['{{#resultDice}}…{{/resultDice}}', '{{#allDice}}…{{/allDice}}', '{{?die.battery}}…{{/?}}'],
        'Rule outputs': ['{{blink.color}}', '{{blink.colorInt}}', '{{threshold}}', '{{modifier}}'],
      };

  void setName(String v) {
    name = v;
    dirty = true;
    _validateNameSync();
    notifyListeners();
    _checkNameUniqueLive(v);
  }

  /// Async uniqueness check so a duplicate name is flagged while typing, not only
  /// on Save. Ignores a stale result if the user kept typing.
  Future<void> _checkNameUniqueLive(String candidate) async {
    if (_nameError != null) return; // already blocked (empty/reserved)
    final taken = await _domain.isNameTaken(candidate.trim(), excludeId: _id);
    if (candidate != name || _nameError != null) return; // stale, or newly blocked
    if (taken) {
      _nameError = 'Name already used';
      notifyListeners();
    }
  }

  void setBody(String v) {
    body = v;
    _touched();
    _recompute();
  }

  void setMethod(String m) {
    method = m;
    // Smart default: GET is a query string (form); POST defaults to JSON.
    if (m.toUpperCase() == 'GET') {
      format = PayloadFormat.form;
    } else if (format == PayloadFormat.form) {
      format = PayloadFormat.json;
    }
    _touched();
    _recompute();
  }

  void setFormat(PayloadFormat f) {
    format = f;
    _touched();
    _recompute();
  }

  void setContentType(String? c) {
    contentType = (c == null || c.trim().isEmpty) ? null : c.trim();
    _touched();
    notifyListeners();
  }

  void setHeader(String key, String value) {
    if (key.trim().isEmpty) return;
    headers[key.trim()] = value;
    _touched();
    notifyListeners();
  }

  void removeHeader(String key) {
    headers.remove(key);
    _touched();
    notifyListeners();
  }

  bool get canSave => !isBuiltin && _nameError == null && name.trim().isNotEmpty && _preview.ok;

  PayloadTemplate build() => PayloadTemplate(
        id: _id,
        name: name.trim(),
        method: method,
        format: format,
        contentType: contentType,
        headers: Map.of(headers),
        body: body,
        category: 'custom',
      );

  void _recompute() {
    _preview = _domain.preview(build());
    notifyListeners();
  }

  void _validateNameSync() {
    final n = name.trim();
    if (n.isEmpty) {
      _nameError = 'Name required';
    } else if (_domain.isReserved(n)) {
      _nameError = 'Reserved name — pick another';
    } else {
      _nameError = null; // uniqueness checked on save (async)
    }
  }

  Future<Result<void>> _save() async {
    _validateNameSync();
    if (_nameError == null && await _domain.isNameTaken(name.trim(), excludeId: _id)) {
      _nameError = 'Name already used';
    }
    notifyListeners();
    if (!canSave) return Result.error(Exception(_nameError ?? 'Fix the payload before saving'));
    await _domain.save(build());
    dirty = false;
    return Result.value(null);
  }
}
