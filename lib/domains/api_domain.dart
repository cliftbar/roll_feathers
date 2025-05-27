import 'dart:io';

import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_routing/shelf_routing.dart';

class ApiDomain {
  final HttpServer _apiServer;
  final RollDomain _rollDomain;
  final List<NetworkInterface> _networkInterfaces;

  ApiDomain._(this._apiServer, this._rollDomain, this._networkInterfaces);

  static Future<ApiDomain> create({required RollDomain rollDomain}) async {
    var ifaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    var router = Router();

    router.get("/api/last-roll", (Request request) {
      print("api request ${request.url}");

      var result = rollDomain.rollHistory.firstOrNull;
      if (result == null) {
        return Response.notFound(result);
      }
      return JsonResponse.ok(result.toJson());
    });

    final app = const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

    var server = await shelf_io.serve(app, InternetAddress.anyIPv4, 8080);
    return ApiDomain._(server, rollDomain, ifaces);
  }

  List<String> getIpAddress() {
    return _networkInterfaces.map((e) => e.addresses[0].address).toList();
  }
}
