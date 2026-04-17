import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class SseClient {
  SseClient({required this.url, this.headers = const {}});

  final Uri url;
  final Map<String, String> headers;
  final _controller = StreamController<String>.broadcast();
  StreamSubscription<String>? _sub;
  http.Client? _client;

  Stream<String> get events => _controller.stream;

  Future<void> connect() async {
    await disconnect();
    _client = http.Client();
    final request = http.Request('GET', url);
    request.headers.addAll(headers);
    request.headers['Accept'] = 'text/event-stream';
    final response = await _client!.send(request);

    if (response.statusCode != 200) {
      throw Exception('SSE failed with status ${response.statusCode}');
    }

    _sub = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data: '))
        .map((line) => line.substring(6).trim())
        .listen(
      (line) {
        if (line.isNotEmpty) {
          _controller.add(line);
        }
      },
      onError: _controller.addError,
    );
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}
