import 'package:async/async.dart';
import 'package:flutter/foundation.dart';

import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/domains/webhook/webhook_payload_domain.dart';
import 'package:roll_feathers/util/command.dart';

/// ViewModel for the webhook payloads list (MVVM + Command).
class WebhookPayloadsScreenViewModel extends ChangeNotifier {
  final WebhookPayloadDomain _domain;

  late final List<PayloadTemplate> builtins;
  List<PayloadTemplate> _user = [];
  List<PayloadTemplate> get userPayloads => _user;

  bool _loading = true;
  bool get loading => _loading;

  late final Command0 load;
  late final Command1<void, PayloadTemplate> deletePayload;

  WebhookPayloadsScreenViewModel(this._domain) {
    builtins = _domain.builtins();
    load = Command0(_load)..execute();
    deletePayload = Command1(_delete);
  }

  Future<Result<void>> _load() async {
    try {
      _user = await _domain.loadUserPayloads();
      _loading = false;
      return Result.value(null);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  Future<Result<void>> _delete(PayloadTemplate p) async {
    try {
      await _domain.delete(p.id);
      await _load();
      return Result.value(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// A blank user payload to open in the editor (not persisted until saved).
  PayloadTemplate newBlank() => _domain.newBlank();

  /// A copy of [p] to open in the editor (not persisted until saved).
  PayloadTemplate duplicate(PayloadTemplate p) => _domain.duplicate(p);
}
