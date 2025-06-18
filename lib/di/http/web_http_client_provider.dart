import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart';

Client provideHttpClient() {
  return FetchClient(mode: RequestMode.cors);
}
