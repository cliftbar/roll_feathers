import 'dart:convert';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:format/format.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_service.dart';

import '../../dice_sdks/message_sdk.dart';
import '../../util/color.dart';

class State {
  final String entityId;
  final String state;
  final Map<String, dynamic> attributes;
  final DateTime lastChanged;
  final DateTime lastUpdated;

  State({
    required this.entityId,
    required this.state,
    required this.attributes,
    required this.lastChanged,
    required this.lastUpdated,
  });

  static State fromJson(Map<String, dynamic> jsonData) {
    return State(
      entityId: jsonData["entity_id"],
      state: jsonData['state'],
      attributes: jsonData['attributes'],
      lastChanged: DateTime.parse(jsonData['last_changed']),
      lastUpdated: DateTime.parse(jsonData['last_updated']),
    );
  }

  Map<String, dynamic> toJson() {
    return {"entity_id": entityId, "state": state, "attributes": attributes};
  }
}

class HaApiService implements HaService {
  static final statesPath = "{url}/api/states";
  static final entityStatePath = "$statesPath/{entityId}";
  static final servicePath = "{url}/api/services/{domain}/{service}";

  final _log = Logger("HaApiService");
  final HaConfigService _haConfigService;
  final Client _httpClient;

  HaApiService._(this._haConfigService, this._httpClient);

  static Future<HaApiService> create(Client httpClient) async {
    HaApiService service = HaApiService._(HaConfigService(), httpClient);

    return service;
  }

  Future<State> _getState(String? entityId) async {
    HaConfig conf = await _haConfigService.getConfig();
    String entityIdToUse = entityId ?? conf.entity;

    Uri url = Uri.parse(format(entityStatePath, {#url: conf.url, #entityId: entityIdToUse}));

    Response resp = await _httpClient.get(url, headers: getHeaders(conf));

    if (resp.statusCode != 200) {
      throw Exception("bad HA response: ${resp.body}");
    }

    Map<String, dynamic> decodedResponse = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

    var retState = State.fromJson(decodedResponse);

    return retState;
  }

  Future<State> _postState(State newState) async {
    HaConfig conf = await _haConfigService.getConfig();
    Uri url = Uri.parse(format(entityStatePath, {#url: conf.url, #entityId: newState.entityId}));

    Response resp = await _httpClient.post(url, headers: getHeaders(conf), body: jsonEncode(newState.toJson()));

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception("bad HA response: ${resp.body}");
    }

    Map<String, dynamic> decodedResponse = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    var retState = State.fromJson(decodedResponse);

    return retState;
  }

  Future<List<dynamic>> _postService({
    required String entityId,
    required HaDomainService action,
    Map<String, dynamic>? serviceData,
    bool withResponse = false,
  }) async {
    serviceData = serviceData ?? {};
    serviceData["entity_id"] = entityId;
    HaConfig conf = await _haConfigService.getConfig();
    Uri url = Uri.parse(format(servicePath, {#url: conf.url, #domain: action.domain, #service: action.service}));
    if (withResponse) {
      url.queryParameters["return_response"] = "";
    }

    Response resp = await _httpClient.post(url, headers: getHeaders(conf), body: jsonEncode(serviceData));

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception("bad HA response: ${resp.body}");
    }

    List<dynamic> decodedResponse = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;

    return decodedResponse;
  }

  Map<String, String> getHeaders(HaConfig conf) {
    return {"Authorization": "Bearer ${conf.token}", 'Content-Type': 'application/json; charset=UTF-8'};
  }

  @override
  Future<void> blinkLightEntity(String entity, Blinker blink, {int times = 1}) async {
    Map<String, dynamic> revertPayload = {};
    HaDomainService revertAction = HaDomainService.lightOn;

    try {
      var currentState = await _getState(entity);

      if (currentState.state == "on") {
        revertAction = HaDomainService.lightOn;
        ColorMode colorMode = ColorMode.fromName(currentState.attributes["color_mode"]);
        if (colorMode.attributeKey != null) {
          revertPayload = {
            "brightness": currentState.attributes["brightness"] ?? 255,
            colorMode.attributeKey!: currentState.attributes[colorMode.attributeKey],
          };
        }
      } else {
        revertAction = HaDomainService.lightOff;
      }
    } catch (e) {
      ("error reading ha state of '$entity': $e");
      revertAction = HaDomainService.lightOff;
    }

    Map<String, dynamic> blinkPayload = {
      "rgb_color": [blink.r255(), blink.g255(), blink.b255()],
      "brightness": blink.a255(),
    };

    for (int i = 0; i < times; i++) {
      await _postService(entityId: entity, action: HaDomainService.lightOn, serviceData: blinkPayload);
      await Future.delayed(Duration(milliseconds: blink.getOnDuration().inMilliseconds));
    }
    await _postService(entityId: entity, action: revertAction, serviceData: revertPayload);

    _log.fine("HA Api blink");
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> setEntityColor(String entity, Color color) async {
    RFColor c = RFColor.of(color);

    Map<String, dynamic> setPayload = {
      "rgb_color": [c.r255(), c.g255(), c.b255()],
      "brightness": c.a255(),
    };
    await _postService(entityId: entity, action: HaDomainService.lightOn, serviceData: setPayload);
  }
}

enum ColorMode {
  unknown("unknown", null),
  onoff("onoff", null),
  brightness("brightness", null),
  colorTemp("color_temp", "color_temp"),
  hs("hs", "hs_color"),
  rgb("rgb", "rgb_color"),
  xy("xy", "xy_color");

  final String name;
  final String? attributeKey;

  const ColorMode(this.name, this.attributeKey);

  static ColorMode fromName(String name) {
    return ColorMode.values.firstWhereOrNull((v) => v.name == name) ?? ColorMode.unknown;
  }
}
