import 'package:kumwe_sdk/kumwe_sdk.dart';

final class FakeKumweTransport implements KumweTransport {
  FakeKumweTransport(Iterable<KumweResponse> responses)
    : _responses = List<KumweResponse>.of(responses);

  final List<KumweResponse> _responses;
  final List<KumweRequest> requests = [];

  @override
  Future<KumweResponse> send(KumweRequest request) async {
    requests.add(request);
    if (_responses.isEmpty) {
      throw StateError('No fake response remains.');
    }
    return _responses.removeAt(0);
  }
}
