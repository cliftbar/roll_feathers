import 'dart:io';

import 'package:http/http.dart';
import 'package:http/io_client.dart';

Client provideHttpClient() {
  if (Platform.isAndroid) {
    // return CronetClient.defaultCronetEngine();
  }
  if (Platform.isIOS || Platform.isMacOS) {
    // return CupertinoClient.defaultSessionConfiguration();
    return IOClient();
  }
  return IOClient();
}
