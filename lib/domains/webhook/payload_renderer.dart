import 'dart:convert';

import 'package:roll_feathers/domains/webhook/payload_context.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';

/// Thrown when a template can't be rendered (unbalanced blocks, or JSON output
/// that doesn't parse). The message is user-facing (shown in the editor).
class PayloadRenderException implements Exception {
  final String message;
  const PayloadRenderException(this.message);
  @override
  String toString() => 'PayloadRenderException: $message';
}

/// Renders a payload template against a [PayloadContext].
///
/// Grammar (Mustache-style `{{ }}`; single braces are literal, so JSON passes
/// through): `{{path}}` scalar (dotted, numeric-indexed; `die` = current-loop or
/// first result die), `{{#resultDice}}…{{/resultDice}}` loop, `{{?path}}…{{/?}}`
/// conditional. The [PayloadFormat] drives escaping + array-join; `json` output is
/// normalized (parsed → re-serialized) to minify (or pretty-print) and to absorb
/// the loop's between-item commas.
class PayloadRenderer {
  static String render(
    String template,
    PayloadContext ctx,
    PayloadFormat format, {
    bool pretty = false,
  }) {
    final nodes = _parse(template);
    final buf = StringBuffer();
    _renderNodes(nodes, ctx.root, null, format, buf);
    final raw = buf.toString();

    if (format == PayloadFormat.json) {
      final Object? decoded;
      try {
        decoded = jsonDecode(_cleanJsonCommas(raw));
      } on FormatException catch (e) {
        throw PayloadRenderException('rendered output is not valid JSON: ${e.message}');
      }
      return pretty ? const JsonEncoder.withIndent('  ').convert(decoded) : jsonEncode(decoded);
    }
    return raw;
  }

  /// String-aware normalization of comma noise so authors (and the loop's
  /// between-item join) never have to get commas exactly right: drops trailing
  /// commas (before `}`/`]`), leading commas (after `{`/`[`), and collapses runs
  /// of commas. String literals are copied verbatim; whitespace outside strings
  /// is dropped (the output is re-serialized anyway).
  static String _cleanJsonCommas(String s) {
    final out = StringBuffer();
    var pendingComma = false;
    String? lastSig; // last significant char emitted

    void resolvePending(String next) {
      if (!pendingComma) return;
      pendingComma = false;
      final trailing = next == '}' || next == ']';
      final leading = lastSig == '{' || lastSig == '[';
      if (!trailing && !leading) out.write(',');
    }

    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == '"') {
        resolvePending('"');
        out.write('"');
        i++;
        while (i < s.length) {
          final c = s[i];
          out.write(c);
          i++;
          if (c == '\\' && i < s.length) {
            out.write(s[i]);
            i++;
            continue;
          }
          if (c == '"') break;
        }
        lastSig = '"';
        continue;
      }
      if (ch == ',') {
        pendingComma = true;
        i++;
        continue;
      }
      if (ch.trim().isEmpty) {
        i++;
        continue; // drop insignificant whitespace
      }
      resolvePending(ch);
      out.write(ch);
      lastSig = ch;
      i++;
    }
    return out.toString();
  }

  /// Renders against the canned sample — for the editor's default preview.
  static String renderSample(PayloadTemplate t, {bool pretty = true}) =>
      render(t.body, PayloadContext.sample, t.format, pretty: pretty);

  // ── parse ─────────────────────────────────────────────────────────────────

  static List<_Node> _parse(String template) {
    final tokens = _tokenize(template);
    final root = <_Node>[];
    final stack = <_Frame>[];
    List<_Node> current = root;

    for (final tok in tokens) {
      switch (tok.type) {
        case _TokType.literal:
          current.add(_Literal(tok.value));
          break;
        case _TokType.scalar:
          current.add(_Scalar(tok.value));
          break;
        case _TokType.loopOpen:
          final node = _Loop(tok.value);
          stack.add(_Frame(node, current, 'loop', tok.value));
          current = node.children;
          break;
        case _TokType.condOpen:
          final node = _Cond(tok.value);
          stack.add(_Frame(node, current, 'cond', tok.value));
          current = node.children;
          break;
        case _TokType.close:
          if (stack.isEmpty) {
            throw PayloadRenderException('unexpected {{/${tok.value}}} — no open block');
          }
          final frame = stack.removeLast();
          final isCondClose = tok.value == '?';
          if (isCondClose && frame.kind != 'cond') {
            throw PayloadRenderException('{{/?}} does not match {{#${frame.name}}}');
          }
          if (!isCondClose && (frame.kind != 'loop' || frame.name != tok.value)) {
            throw PayloadRenderException('{{/${tok.value}}} does not match the open block');
          }
          current = frame.parent;
          current.add(frame.node);
          break;
      }
    }
    if (stack.isNotEmpty) {
      throw PayloadRenderException('unclosed block {{#${stack.last.name}}}');
    }
    return root;
  }

  static List<_Token> _tokenize(String s) {
    final out = <_Token>[];
    final lit = StringBuffer();
    var i = 0;
    while (i < s.length) {
      if (i + 1 < s.length && s[i] == '{' && s[i + 1] == '{') {
        final close = s.indexOf('}}', i + 2);
        if (close < 0) throw const PayloadRenderException('unterminated {{ token');
        if (lit.isNotEmpty) {
          out.add(_Token(_TokType.literal, lit.toString()));
          lit.clear();
        }
        final content = s.substring(i + 2, close).trim();
        out.add(_classify(content));
        i = close + 2;
      } else {
        lit.write(s[i]);
        i++;
      }
    }
    if (lit.isNotEmpty) out.add(_Token(_TokType.literal, lit.toString()));
    return out;
  }

  static _Token _classify(String content) {
    if (content.startsWith('#')) return _Token(_TokType.loopOpen, content.substring(1).trim());
    if (content.startsWith('?')) return _Token(_TokType.condOpen, content.substring(1).trim());
    if (content.startsWith('/')) return _Token(_TokType.close, content.substring(1).trim());
    return _Token(_TokType.scalar, content);
  }

  // ── render ────────────────────────────────────────────────────────────────

  static void _renderNodes(
    List<_Node> nodes,
    Map<String, dynamic> root,
    dynamic currentDie,
    PayloadFormat fmt,
    StringBuffer buf,
  ) {
    for (final n in nodes) {
      if (n is _Literal) {
        buf.write(n.text);
      } else if (n is _Scalar) {
        _appendValue(buf, _resolve(n.path, root, currentDie), fmt);
      } else if (n is _Cond) {
        if (_truthy(_resolve(n.path, root, currentDie))) {
          _renderNodes(n.children, root, currentDie, fmt, buf);
        }
      } else if (n is _Loop) {
        final coll = _resolve(n.collection, root, currentDie);
        if (coll is! List || coll.isEmpty) continue;
        final parts = <String>[];
        for (final item in coll) {
          final sub = StringBuffer();
          _renderNodes(n.children, root, item, fmt, sub);
          parts.add(sub.toString());
        }
        buf.write(_joinLoop(parts, fmt));
      }
    }
  }

  static String _joinLoop(List<String> parts, PayloadFormat fmt) {
    switch (fmt) {
      case PayloadFormat.json:
        // Strip a trailing comma the author may have written inside the block,
        // then join with commas — normalization handles the rest.
        final cleaned = parts.map((p) {
          var t = p.trimRight();
          if (t.endsWith(',')) t = t.substring(0, t.length - 1);
          return t;
        }).where((p) => p.isNotEmpty);
        return cleaned.join(',');
      case PayloadFormat.form:
        final cleaned = parts.map((p) {
          var t = p;
          if (t.endsWith('&')) t = t.substring(0, t.length - 1);
          return t;
        }).where((p) => p.isNotEmpty);
        return cleaned.join('&');
      case PayloadFormat.text:
      case PayloadFormat.xml:
        return parts.join();
    }
  }

  static void _appendValue(StringBuffer buf, dynamic value, PayloadFormat fmt) {
    if (value == null) {
      if (fmt == PayloadFormat.json) {
        // Inside a JSON string (`"hi {{x}}"`) a null must render as empty, not the
        // literal word `null`; in a value position (`{"a":{{x}}}`) it becomes null.
        buf.write(_insideJsonString(buf.toString()) ? '' : 'null');
      }
      return; // form/text: empty
    }
    switch (fmt) {
      case PayloadFormat.json:
        if (value is String) {
          final e = jsonEncode(value);
          buf.write(e.substring(1, e.length - 1)); // strip the added quotes
        } else if (value is num || value is bool) {
          buf.write(value.toString());
        } else {
          buf.write(jsonEncode(value)); // List/Map → raw JSON
        }
        break;
      case PayloadFormat.form:
        final s = (value is String) ? value : (value is num || value is bool) ? value.toString() : jsonEncode(value);
        buf.write(Uri.encodeQueryComponent(s));
        break;
      case PayloadFormat.text:
        buf.write((value is String) ? value : (value is num || value is bool) ? value.toString() : jsonEncode(value));
        break;
      case PayloadFormat.xml:
        final s = (value is String) ? value : (value is num || value is bool) ? value.toString() : jsonEncode(value);
        buf.write(_xmlEscape(s));
        break;
    }
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static bool _truthy(dynamic v) => v != null && v != false && !(v is String && v.isEmpty);

  /// Whether the JSON buffer currently ends inside an open string literal.
  static bool _insideJsonString(String s) {
    var inStr = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inStr && c == r'\') {
        i++; // skip the escaped char
        continue;
      }
      if (c == '"') inStr = !inStr;
    }
    return inStr;
  }

  // ── path resolution ─────────────────────────────────────────────────────────

  static dynamic _resolve(String path, Map<String, dynamic> root, dynamic currentDie) {
    final segs = path.split('.');
    dynamic val;
    var start = 0;
    if (segs.first == 'die') {
      val = currentDie ?? _firstResultDie(root);
      start = 1;
    } else {
      val = root;
    }
    for (var i = start; i < segs.length; i++) {
      final seg = segs[i];
      if (val == null) return null;
      if (val is List) {
        switch (seg) {
          case 'count':
            val = val.length;
            break;
          case 'names':
            val = val.map((e) => (e is Map) ? e['name'] : e).join(',');
            break;
          case 'values':
            val = val.map((e) => (e is Map) ? e['value'] : e).join(',');
            break;
          case 'json':
            break; // leave the list; _appendValue serializes it
          default:
            final idx = int.tryParse(seg);
            if (idx == null || idx < 0 || idx >= val.length) return null;
            val = val[idx];
        }
      } else if (val is Map) {
        val = val[seg];
      } else {
        return null;
      }
    }
    return val;
  }

  static dynamic _firstResultDie(Map<String, dynamic> root) {
    final rd = root['resultDice'];
    return (rd is List && rd.isNotEmpty) ? rd.first : null;
  }
}

// ── nodes / tokens ────────────────────────────────────────────────────────────

abstract class _Node {}

class _Literal extends _Node {
  final String text;
  _Literal(this.text);
}

class _Scalar extends _Node {
  final String path;
  _Scalar(this.path);
}

class _Loop extends _Node {
  final String collection;
  final List<_Node> children = [];
  _Loop(this.collection);
}

class _Cond extends _Node {
  final String path;
  final List<_Node> children = [];
  _Cond(this.path);
}

class _Frame {
  final _Node node;
  final List<_Node> parent;
  final String kind; // 'loop' | 'cond'
  final String name;
  _Frame(this.node, this.parent, this.kind, this.name);
}

enum _TokType { literal, scalar, loopOpen, condOpen, close }

class _Token {
  final _TokType type;
  final String value;
  _Token(this.type, this.value);
}
