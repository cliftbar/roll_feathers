import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:roll_feathers/domains/webhook/payload_context.dart';
import 'package:roll_feathers/domains/webhook/payload_renderer.dart';
import 'package:roll_feathers/domains/webhook/webhook_send.dart';
import 'package:roll_feathers/repositories/webhook/webhook_payload_repository.dart';
import 'package:roll_feathers/services/app_service.dart';

final Logger _log = Logger('WebhookDomain');

class WebhookDomain {
  final http.Client? _httpClient;
  final String _appVersion;
  final AppService _appService;
  final WebhookPayloadRepository _payloads;

  WebhookDomain({
    http.Client? httpClient,
    String appVersion = 'unknown',
    required AppService appService,
    WebhookPayloadRepository? payloads,
  })  : _httpClient = httpClient,
        _appVersion = appVersion,
        _appService = appService,
        _payloads = payloads ?? SharedPrefsWebhookPayloadRepository();

  /// Resolve [payloadName] → render it against [context] in the template's
  /// format → send to [url]. Method + content-type come from the resolved
  /// template. Never throws: a disabled setting, an unknown payload, a render
  /// error, or a network failure logs and skips.
  Future<void> fire({
    required String url,
    required String payloadName,
    required PayloadContext context,
  }) async {
    if (!await _appService.getWebhooksEnabled()) {
      _log.fine('[fire] webhooks disabled; skipping $url');
      return;
    }
    // Redacted for logs: a webhook URL often embeds a secret token in its path.
    final safeUrl = redactUrl(url);
    if (!isAllowedWebhookUrl(url)) {
      _log.warning('[fire] refusing non-http(s) or malformed URL $safeUrl; skipping');
      return;
    }
    final tmpl = await _payloads.byName(payloadName);
    if (tmpl == null) {
      _log.warning('[fire] unknown payload "$payloadName"; skipping $safeUrl');
      return;
    }
    final String body;
    try {
      body = PayloadRenderer.render(tmpl.body, context, tmpl.format);
    } on PayloadRenderException catch (e) {
      _log.warning('[fire] payload "$payloadName" render failed: ${e.message}');
      return;
    }

    final client = _httpClient ?? http.Client();
    final headers = <String, String>{
      'User-Agent': webhookUserAgent(_appVersion),
      ...tmpl.headers,
    };
    try {
      if (tmpl.isGet) {
        await client.get(buildGetUri(url, body), headers: headers).timeout(kWebhookTimeout);
      } else {
        headers['Content-Type'] = tmpl.effectiveContentType;
        final request = http.Request('POST', Uri.parse(url))
          ..headers.addAll(headers)
          ..body = body;
        final response = await client.send(request).timeout(kWebhookTimeout);
        if (response.statusCode == 429) {
          _log.warning('[fire] POST to $safeUrl rate-limited (429)'
              '${response.headers['retry-after'] != null ? '; retry-after=${response.headers['retry-after']}' : ''}');
        } else if (response.statusCode >= 400) {
          _log.warning('[fire] POST to $safeUrl failed with status ${response.statusCode}');
        }
      }
    } on http.ClientException catch (e) {
      // e.toString() includes the request URI (with any secret); log only .message.
      _log.warning('[fire] error firing to $safeUrl: ${e.message}');
    } on FormatException {
      _log.warning('[fire] invalid URL $safeUrl');
    } catch (e) {
      _log.warning('[fire] error firing to $safeUrl: $e');
    } finally {
      if (_httpClient == null) client.close();
    }
  }
}
