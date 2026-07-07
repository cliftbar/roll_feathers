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

  PreviewResult _preview = const PreviewResult.success('');
  PreviewResult get preview => _preview;

  String? _nameError;
  String? get nameError => _nameError;

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
    _validateNameSync();
    notifyListeners();
  }

  void setBody(String v) {
    body = v;
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
    _recompute();
  }

  void setFormat(PayloadFormat f) {
    format = f;
    _recompute();
  }

  void setContentType(String? c) {
    contentType = (c == null || c.trim().isEmpty) ? null : c.trim();
    notifyListeners();
  }

  void setHeader(String key, String value) {
    if (key.trim().isEmpty) return;
    headers[key.trim()] = value;
    notifyListeners();
  }

  void removeHeader(String key) {
    headers.remove(key);
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
    return Result.value(null);
  }
}
