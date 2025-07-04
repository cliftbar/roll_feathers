import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_routing/shelf_routing.dart';

import '../dice_sdks/dice_sdks.dart';
import '../domains/die_domain.dart';
import '../domains/roll_domain.dart';

abstract class ApiDomain {
  List<String> getIpAddresses();
}

class EmptyApiDomain extends ApiDomain {
  @override
  List<String> getIpAddresses() {
    return [];
  }
}

class ApiDomainServer extends ApiDomain {
  final List<NetworkInterface> _networkInterfaces;
  static final Logger _log = Logger("ApiDomainServer");

  ApiDomainServer._(this._networkInterfaces);

  static Future<ApiDomain> create({required RollDomain rollDomain, required DieDomain dieDomain}) async {
    List<NetworkInterface> iFaces = [];
    try {
      iFaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
    } on Exception catch (e) {
      _log.info("iface exception: $e");
    }
    Router router = Router();

    router.get("/api/rolls", (Request request) {
      _log.info("api request ${request.url}");
      int? count = int.tryParse(request.params["count"] ?? "");
      List<RollResult> results = rollDomain.rollHistory.sublist(0, count);
      return JsonResponse.ok(results.map((r) => r.toJson()));
    });

    router.get("/api/dice", (Request request) {
      _log.info("api request ${request.url}");

      List<GenericDie> result = dieDomain.dice;
      return JsonResponse.ok(result.map((d) => d.toJson()));
    });

    final app = const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

    await shelf_io.serve(app, InternetAddress.anyIPv4, 8080);
    return ApiDomainServer._(iFaces);
  }

  @override
  List<String> getIpAddresses() {
    return _networkInterfaces.map((e) => e.addresses[0].address).toList();
  }
}
