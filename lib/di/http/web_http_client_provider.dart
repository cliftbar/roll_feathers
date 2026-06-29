import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart';

import 'package:roll_feathers/util/platform_info.dart';

// `platform` is unused on web (single client) but kept for a uniform signature
// with the native provider, which selects a client by OS.
Client provideHttpClient(PlatformInfo platform) {
  return FetchClient(mode: RequestMode.cors);
}
