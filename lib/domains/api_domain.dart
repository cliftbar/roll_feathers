import 'dart:io';

import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_routing/shelf_routing.dart';

abstract class ApiDomain {
  List<String> getIpAddresses();
}

class EmptyApiDomain extends ApiDomain {
  @override
  List<String> getIpAddresses() {
    // TODO: implement getIpAddress
    return [];
  }
}

/// Builds the request handler in isolation from [shelf_io.serve], so tests
/// can exercise routes by calling it directly with constructed [Request]s
/// instead of binding a real socket.
Handler buildApiHandler(RollDomain rollDomain) {
  var router = Router();

  router.get("/api/last-roll", (Request request) {
    var result = rollDomain.rollHistory.firstOrNull;
    if (result == null) {
      return Response.notFound(result);
    }
    return JsonResponse.ok(result.toJson());
  });

  return const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
}

class ApiDomainServer extends ApiDomain {
  final List<NetworkInterface> _networkInterfaces;

  ApiDomainServer._(this._networkInterfaces);

  static Future<ApiDomain> create({required RollDomain rollDomain, int port = 8080}) async {
    List<NetworkInterface> iFaces = [];
    try {
      iFaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
    } on Exception catch (_) {
      // Ignored for now
    }

    try {
      await shelf_io.serve(buildApiHandler(rollDomain), InternetAddress.anyIPv4, port);
    } on SocketException {
      return EmptyApiDomain();
    }
    return ApiDomainServer._(iFaces);
  }

  @override
  List<String> getIpAddresses() {
    return _networkInterfaces.map((e) => e.addresses[0].address).toList();
  }
}
