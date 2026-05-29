import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/util/json_serializable.dart';

final Logger _log = Logger('WebhookDomain');

abstract interface class WebhookPayload implements JsonSerializable {
  Map<String, String> toQueryParams();
}

class WebhookDomain {
  final http.Client? _httpClient;
  final String _appVersion;
  final AppService _appService;

  WebhookDomain({
    http.Client? httpClient,
    String appVersion = 'unknown',
    required AppService appService,
  })  : _httpClient = httpClient,
        _appVersion = appVersion,
        _appService = appService;

  Future<void> fireWebhook({
    required String url,
    required String method,
    required WebhookPayload payload,
  }) async {
    final enabled = await _appService.getWebhooksEnabled();
    if (!enabled) {
      _log.fine('[fireWebhook] webhooks disabled in settings; skipping $url');
      return;
    }

    final client = _httpClient ?? http.Client();
    final headers = <String, String>{};

    // TODO: Surface CORS and forbidden header errors in the UI.
    // Setting User-Agent manually is forbidden on web and will cause a silent failure/CORS error in some browsers.
    headers['User-Agent'] = 'roll-feathers/$_appVersion';

    try {
      if (method == 'GET') {
        final uri = Uri.parse(url).replace(queryParameters: payload.toQueryParams());
        await client.get(uri, headers: headers);
      } else {
        // NOTE: application/json triggers a CORS preflight (OPTIONS) request on web.
        // The target server must be configured to handle this and return correct CORS headers.
        headers['Content-Type'] = 'application/json';

        final request = http.Request(method, Uri.parse(url));
        request.headers.addAll(headers);
        request.body = jsonEncode(payload.toJson());

        final response = await client.send(request);
        if (response.statusCode >= 400) {
          _log.warning('[fireWebhook] $method to $url failed with status ${response.statusCode}');
        }
      }
    } on FormatException catch (e) {
      _log.warning('[fireWebhook] invalid URL "$url": $e');
    } catch (e) {
      _log.warning('[fireWebhook] error firing to $url: $e');
    } finally {
      // Only close if we created it here.
      if (_httpClient == null) client.close();
    }
  }
}
