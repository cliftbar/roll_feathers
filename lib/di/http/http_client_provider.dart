import 'package:http/http.dart';
import 'package:http/io_client.dart';

import 'package:roll_feathers/util/platform_info.dart';

Client provideHttpClient(PlatformInfo platform) {
  if (platform.isAndroid) {
    // return CronetClient.defaultCronetEngine();
  }
  if (platform.isIOS || platform.isMacOS) {
    // return CupertinoClient.defaultSessionConfiguration();
    return IOClient();
  }
  return IOClient();
}
