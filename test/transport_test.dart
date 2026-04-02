import 'dart:convert';

import 'package:codex_remote/src/transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relay https URLs are converted to wss websocket URLs', () {
    final uri = relayWebSocketUri(Uri.parse('https://cr.rousoftware.com'));

    expect(uri.toString(), 'wss://cr.rousoftware.com/ws');
  });

  test('relay http localhost URLs are converted to ws websocket URLs', () {
    final uri = relayWebSocketUri(Uri.parse('http://localhost:8787/base'));

    expect(uri.toString(), 'ws://localhost:8787/base/ws');
  });

  test('relay salt derivation matches bridge implementation', () async {
    final salt = await deriveRelaySaltBytes(
      localNonce: 'client-nonce',
      peerNonce: 'bridge-nonce',
    );

    expect(
      base64Url.encode(salt),
      '5WWyJtktOJGpcs087B9KSLzGOVlI36AUZon3fY6PmaE=',
    );
  });
}
