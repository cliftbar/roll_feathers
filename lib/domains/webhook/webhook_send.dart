/// Shared webhook transport helpers used by both the real fire path
/// ([WebhookDomain.fire]) and the editor's test-send ([WebhookPayloadDomain.testSend]),
/// so the two behave identically (query-string building, timeout, URL policy)
/// and secrets are handled consistently.
library;

/// How long to wait for a webhook request before giving up. Webhook effects are
/// fire-and-forget; without a bound a slow/hung endpoint would leak pending
/// futures and sockets across many rolls.
const Duration kWebhookTimeout = Duration(seconds: 10);

/// User-Agent sent on every webhook request. [appVersion] is appended when known
/// (the real fire path); the editor test-send omits it.
String webhookUserAgent([String? appVersion]) =>
    appVersion == null ? 'roll-feathers' : 'roll-feathers/$appVersion';

/// Redacts a webhook URL for logging or user-facing errors: keeps only
/// scheme + host (+ port) and drops the path and query. Services like Discord
/// embed a secret token in the URL path (`.../webhooks/<id>/<token>`), so the
/// full URL must never reach logs (which `main` pipes to stdout/logcat).
String redactUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return '<url>';
  final scheme = u.scheme.isEmpty ? '' : '${u.scheme}://';
  final port = u.hasPort ? ':${u.port}' : '';
  return '$scheme${u.host}$port';
}

/// True if [url] is an absolute `http`/`https` URL we're willing to send to.
/// Rejects other schemes (`file:`, `content:`, …) and relative/hostless URLs.
bool isAllowedWebhookUrl(String url) {
  final u = Uri.tryParse(url.trim());
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
}

/// Appends the rendered [query] (a form-encoded body) to [url] as a query string
/// for a GET request, picking the right `?` / `&` / `''` separator.
Uri buildGetUri(String url, String query) {
  final String sep;
  if (url.endsWith('?') || url.endsWith('&')) {
    sep = '';
  } else if (url.contains('?')) {
    sep = '&';
  } else {
    sep = '?';
  }
  return Uri.parse('$url$sep$query');
}
