import 'package:roll_feathers/domains/library/editable_library.dart';
import 'package:roll_feathers/util/json_serializable.dart';

/// How a payload body serializes: escaping, array-join, and default Content-Type.
/// `method` (GET/POST) is transport (query vs body); `format` is the wire format.
enum PayloadFormat {
  json('application/json'),
  form('application/x-www-form-urlencoded'),
  text('text/plain'),
  xml('application/xml');

  const PayloadFormat(this.defaultContentType);

  final String defaultContentType;

  static PayloadFormat byName(String name) =>
      PayloadFormat.values.firstWhere((f) => f.name == name, orElse: () => PayloadFormat.json);
}

/// A named, user-editable webhook payload template. Discord and the generic
/// payloads are ordinary built-in instances of this — nothing is hardcoded.
class PayloadTemplate implements JsonSerializable, EditableLibraryItem {
  /// UUID for user items; stable slug for built-ins ("discord", "generic").
  @override
  final String id;

  /// User-facing label; also the `webhook <url> with <name>` reference key.
  @override
  final String name;

  /// Grouping in the list: "discord" | "generic" | "custom".
  @override
  final String category;

  /// Built-ins are read-only (duplicate to edit).
  @override
  final bool isBuiltin;

  /// Transport: "GET" (query string) or "POST" (request body).
  final String method;

  /// Wire format — drives escaping, array-join, and the default Content-Type.
  final PayloadFormat format;

  /// Optional Content-Type override; falls back to [format.defaultContentType].
  final String? contentType;

  /// Static custom headers (auth, vendor, …). Content-Type is added separately.
  final Map<String, String> headers;

  /// The raw template text (see PayloadRenderer for the grammar).
  final String body;

  const PayloadTemplate({
    required this.id,
    required this.name,
    required this.body,
    this.category = 'custom',
    this.isBuiltin = false,
    this.method = 'POST',
    this.format = PayloadFormat.json,
    this.contentType,
    this.headers = const {},
  });

  String get effectiveContentType => contentType ?? format.defaultContentType;

  bool get isGet => method.toUpperCase() == 'GET';

  PayloadTemplate copyWith({
    String? id,
    String? name,
    String? category,
    bool? isBuiltin,
    String? method,
    PayloadFormat? format,
    String? contentType,
    Map<String, String>? headers,
    String? body,
  }) =>
      PayloadTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        isBuiltin: isBuiltin ?? this.isBuiltin,
        method: method ?? this.method,
        format: format ?? this.format,
        contentType: contentType ?? this.contentType,
        headers: headers ?? this.headers,
        body: body ?? this.body,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'method': method,
        'format': format.name,
        if (contentType != null) 'contentType': contentType,
        if (headers.isNotEmpty) 'headers': headers,
        'body': body,
      };

  static PayloadTemplate fromJson(Map<String, dynamic> json) => PayloadTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        category: (json['category'] as String?) ?? 'custom',
        isBuiltin: false, // persisted items are always user items
        method: (json['method'] as String?) ?? 'POST',
        format: PayloadFormat.byName((json['format'] as String?) ?? 'json'),
        contentType: json['contentType'] as String?,
        headers: (json['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
        body: (json['body'] as String?) ?? '',
      );
}
