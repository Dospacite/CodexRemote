import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';

import 'models.dart';

const String _androidEventChannelName = 'codex_remote/android_events';
const String _androidMethodChannelName = 'codex_remote/android_transport';

abstract class AppTransport {
  Stream<String> get messages;
  bool get isConnected;
  Future<void> connect(AppSettings settings);
  Future<void> disconnect();
  Future<void> send(String payload);
}

class PlatformAdaptiveTransport implements AppTransport {
  final AppTransport _directTransport;
  final AppTransport _relayTransport;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  AppTransport? _active;

  PlatformAdaptiveTransport({
    required AppTransport directTransport,
    required AppTransport relayTransport,
  }) : _directTransport = directTransport,
       _relayTransport = relayTransport {
    _directTransport.messages.listen(
      _messages.add,
      onError: _messages.addError,
    );
    _relayTransport.messages.listen(
      _messages.add,
      onError: _messages.addError,
    );
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  bool get isConnected => _active?.isConnected ?? false;

  @override
  Future<void> connect(AppSettings settings) async {
    final next = settings.connectionMode == ConnectionMode.relay
        ? _relayTransport
        : _directTransport;
    if (_active != null && !identical(_active, next)) {
      await _active!.disconnect();
    }
    _active = next;
    await next.connect(settings);
  }

  @override
  Future<void> disconnect() async {
    await _active?.disconnect();
  }

  @override
  Future<void> send(String payload) async {
    await _active?.send(payload);
  }
}

class DirectWebSocketTransport implements AppTransport {
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  bool get isConnected => _connected;

  void _notifyUnexpectedDisconnect() {
    _messages.addError(StateError('Transport disconnected.'));
  }

  @override
  Future<void> connect(AppSettings settings) async {
    await disconnect();
    final authToken = settings.websocketBearerToken.trim();
    final socket = await WebSocket.connect(
      settings.serverUrl,
      headers: authToken.isEmpty
          ? null
          : <String, dynamic>{'Authorization': 'Bearer $authToken'},
    );
    socket.pingInterval = const Duration(seconds: 20);
    _channel = IOWebSocketChannel(socket);
    _subscription = _channel!.stream.listen(
      (dynamic event) {
        if (event is String) {
          _messages.add(event);
        }
      },
      onError: _messages.addError,
      onDone: () {
        final wasConnected = _connected;
        _connected = false;
        if (wasConnected) {
          _notifyUnexpectedDisconnect();
        }
      },
    );
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  Future<void> send(String payload) async {
    _channel?.sink.add(payload);
  }
}

class AndroidForegroundTransport implements AppTransport {
  AndroidForegroundTransport()
    : _events = const EventChannel(_androidEventChannelName),
      _methods = const MethodChannel(_androidMethodChannelName);

  final EventChannel _events;
  final MethodChannel _methods;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _readyCompleter;
  bool _connected = false;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  bool get isConnected => _connected;

  void _notifyUnexpectedDisconnect() {
    _messages.addError(StateError('Transport disconnected.'));
  }

  @override
  Future<void> connect(AppSettings settings) async {
    await _subscription?.cancel();
    _connected = false;
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;
    _subscription = _events.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! String) {
          return;
        }
        _handleTransportEvent(event, readyCompleter);
        _messages.add(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(error, stackTrace);
        }
        _messages.addError(error, stackTrace);
      },
      onDone: () {
        final wasConnected = _connected;
        _connected = false;
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(StateError('Transport disconnected.'));
        } else if (wasConnected) {
          _notifyUnexpectedDisconnect();
        }
      },
    );
    final authToken = settings.websocketBearerToken.trim();
    await _methods.invokeMethod<void>('connect', <String, dynamic>{
      'url': settings.serverUrl,
      'bearerToken': authToken,
    });
    await readyCompleter.future.timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> disconnect() async {
    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(StateError('Transport disconnected.'));
    }
    _readyCompleter = null;
    await _methods.invokeMethod<void>('disconnect');
    _connected = false;
  }

  @override
  Future<void> send(String payload) async {
    final readyCompleter = _readyCompleter;
    if (readyCompleter == null) {
      throw StateError('Android foreground transport is not connected.');
    }
    await readyCompleter.future;
    await _methods.invokeMethod<void>('send', <String, dynamic>{
      'payload': payload,
    });
  }

  void _handleTransportEvent(String event, Completer<void> readyCompleter) {
    dynamic decoded;
    try {
      decoded = jsonDecode(event);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    if (decoded['method'] != 'android/transportStatus') {
      return;
    }
    final params = decoded['params'];
    if (params is! Map<String, dynamic>) {
      return;
    }
    final status = params['status']?.toString();
    switch (status) {
      case 'connected':
        _connected = true;
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
        break;
      case 'disconnected':
        _connected = false;
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(StateError('Transport disconnected.'));
        }
        break;
      case 'error':
        _connected = false;
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(
            StateError(
              params['message']?.toString() ?? 'Android transport error.',
            ),
          );
        }
        break;
    }
  }
}

class AndroidRelaySecureTransport implements AppTransport {
  AndroidRelaySecureTransport()
    : _events = const EventChannel(_androidEventChannelName),
      _methods = const MethodChannel(_androidMethodChannelName);

  final EventChannel _events;
  final MethodChannel _methods;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final Ed25519 _signing = Ed25519();
  final X25519 _keyAgreement = X25519();
  final Cipher _cipher = Chacha20.poly1305Aead();
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _readyCompleter;
  bool _connected = false;
  AppSettings? _settings;
  KeyPair? _sessionKeyPair;
  SecretKey? _sessionSecretKey;
  String? _sessionId;
  String? _sessionNonce;
  int _sendCounter = 0;
  int _receiveCounter = 0;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  bool get isConnected => _connected;

  void _notifyUnexpectedDisconnect() {
    _messages.addError(StateError('Transport disconnected.'));
  }

  @override
  Future<void> connect(AppSettings settings) async {
    await disconnect();
    if (settings.relayUrl.trim().isEmpty ||
        settings.relayDeviceId.trim().isEmpty ||
        settings.relayClientPrivateKey.trim().isEmpty ||
        settings.relayClientPublicKey.trim().isEmpty ||
        settings.relayBridgeSigningPublicKey.trim().isEmpty) {
      throw StateError('Relay mode is selected, but relay pairing is missing.');
    }
    final relayUri = Uri.tryParse(settings.relayUrl);
    if (relayUri == null || !relayUri.hasScheme || relayUri.host.isEmpty) {
      throw StateError('Relay URL is invalid.');
    }
    if (!_isAllowedRelayUri(relayUri)) {
      throw StateError('Relay mode requires HTTPS for non-local relay servers.');
    }
    _settings = settings;
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;
    _subscription = _events.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! String) {
          return;
        }
        if (_handleTransportEvent(event, readyCompleter)) {
          return;
        }
        unawaited(_handleRelayMessage(event));
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(error, stackTrace);
        } else {
          _messages.addError(error, stackTrace);
        }
      },
      onDone: () {
        final wasConnected = _connected;
        _connected = false;
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(StateError('Transport disconnected.'));
        } else if (wasConnected) {
          _notifyUnexpectedDisconnect();
        }
      },
    );
    await _methods.invokeMethod<void>('connect', <String, dynamic>{
      'url': relayWebSocketUri(relayUri).toString(),
      'bearerToken': null,
    });
    await readyCompleter.future.timeout(const Duration(seconds: 20));
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _sendCounter = 0;
    _receiveCounter = 0;
    _sessionId = null;
    _sessionNonce = null;
    _sessionKeyPair = null;
    _sessionSecretKey = null;
    _settings = null;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('Transport disconnected.'));
    }
    _readyCompleter = null;
    await _subscription?.cancel();
    _subscription = null;
    await _methods.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> send(String payload) async {
    final ready = _readyCompleter;
    if (ready == null) {
      throw StateError('Relay transport is not connected.');
    }
    await ready.future;
    final secretKey = _sessionSecretKey;
    final sessionId = _sessionId;
    final settings = _settings;
    if (secretKey == null || sessionId == null || settings == null) {
      throw StateError('Relay session is not ready.');
    }
    final counter = _sendCounter++;
    final aad = _relayAad(
      counter: counter,
      deviceId: settings.relayDeviceId,
      sessionId: sessionId,
    );
    final secretBox = await _cipher.encrypt(
      utf8.encode(payload),
      secretKey: secretKey,
      nonce: _nonceFor(prefix: 'CLNT', counter: counter),
      aad: aad,
    );
    final combined = Uint8List.fromList(
      <int>[...secretBox.cipherText, ...secretBox.mac.bytes],
    );
    await _sendRaw(
      jsonEncode(<String, dynamic>{
        'counter': counter,
        'ciphertext': _b64urlEncode(combined),
        'sessionId': sessionId,
        'type': 'relay_frame',
      }),
    );
  }

  bool _handleTransportEvent(String event, Completer<void> readyCompleter) {
    dynamic decoded;
    try {
      decoded = jsonDecode(event);
    } catch (_) {
      return false;
    }
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    if (decoded['method'] != 'android/transportStatus') {
      return false;
    }
    final params = decoded['params'];
    if (params is! Map<String, dynamic>) {
      return true;
    }
    final status = params['status']?.toString();
    switch (status) {
      case 'connected':
        break;
      case 'disconnected':
        _connected = false;
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(StateError('Transport disconnected.'));
        } else {
          _messages.addError(StateError('Transport disconnected.'));
        }
        break;
      case 'error':
        _connected = false;
        final message =
            params['message']?.toString() ?? 'Android transport error.';
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(StateError(message));
        } else {
          _messages.addError(StateError(message));
        }
        break;
    }
    return true;
  }

  Future<void> _sendRaw(String payload) async {
    await _methods.invokeMethod<void>('send', <String, dynamic>{
      'payload': payload,
    });
  }

  Future<void> _handleRelayMessage(String event) async {
    final payload = jsonDecode(event) as Map<String, dynamic>;
    switch (payload['type']) {
      case 'challenge':
        await _respondToChallenge(payload);
      case 'authenticated':
        break;
      case 'session_open':
        await _completeSession(payload);
      case 'relay_frame':
        await _handleEncryptedFrame(payload);
      case 'close_session':
        final sessionId = payload['sessionId']?.toString();
        if (sessionId == null || sessionId == _sessionId) {
          _messages.addError(StateError('Relay session closed by peer.'));
        }
      default:
        break;
    }
  }

  Future<void> _respondToChallenge(Map<String, dynamic> payload) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    final authNonce = _randomToken(12);
    final authTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sessionKeyPair = await _keyAgreement.newKeyPair();
    final sessionKeyPairData = await sessionKeyPair.extract();
    final sessionPublicKey = await sessionKeyPair.extractPublicKey();
    final sessionNonce = _randomToken(12);
    final signedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signingKeyPair = _clientSigningKeyPair(settings);
    final authSignature = await _signing.sign(
      _canonicalJson(<String, dynamic>{
        'authNonce': authNonce,
        'authTimestamp': authTimestamp,
        'challenge': payload['challenge'],
        'connectionId': payload['connectionId'],
        'deviceId': settings.relayDeviceId,
        'role': 'client',
        'type': 'codex-remote-auth-v1',
      }),
      keyPair: signingKeyPair,
    );
    final sessionSignature = await _signing.sign(
      _canonicalJson(<String, dynamic>{
        'deviceId': settings.relayDeviceId,
        'role': 'client',
        'sessionNonce': sessionNonce,
        'sessionPublicKey': _b64urlEncode(sessionPublicKey.bytes),
        'signedAt': signedAt,
        'type': 'codex-remote-session-bundle-v1',
      }),
      keyPair: signingKeyPair,
    );
    _sessionKeyPair = sessionKeyPairData;
    _sessionNonce = sessionNonce;
    await _sendRaw(
      jsonEncode(<String, dynamic>{
        'authNonce': authNonce,
        'authSignature': _b64urlEncode(authSignature.bytes),
        'authTimestamp': authTimestamp,
        'deviceId': settings.relayDeviceId,
        'role': 'client',
        'sessionBundle': <String, dynamic>{
          'sessionNonce': sessionNonce,
          'sessionPublicKey': _b64urlEncode(sessionPublicKey.bytes),
          'signature': _b64urlEncode(sessionSignature.bytes),
          'signedAt': signedAt,
        },
        'type': 'authenticate',
      }),
    );
  }

  Future<void> _completeSession(Map<String, dynamic> payload) async {
    final settings = _settings;
    final sessionKeyPair = _sessionKeyPair;
    final sessionNonce = _sessionNonce;
    if (settings == null || sessionKeyPair == null || sessionNonce == null) {
      return;
    }
    final peerSigningKey = payload['peerSigningPublicKey']?.toString() ?? '';
    if (peerSigningKey != settings.relayBridgeSigningPublicKey) {
      throw StateError('Relay bridge identity does not match the paired bridge.');
    }
    final bundle = payload['peerSessionBundle'] as Map<String, dynamic>;
    final peerSessionPublicKey = bundle['sessionPublicKey']?.toString() ?? '';
    final peerSessionNonce = bundle['sessionNonce']?.toString() ?? '';
    final signatureBytes = _b64urlDecode(bundle['signature']?.toString() ?? '');
    final verified = await _signing.verify(
      _canonicalJson(<String, dynamic>{
        'deviceId': settings.relayDeviceId,
        'role': 'bridge',
        'sessionNonce': peerSessionNonce,
        'sessionPublicKey': peerSessionPublicKey,
        'signedAt': bundle['signedAt'],
        'type': 'codex-remote-session-bundle-v1',
      }),
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          _b64urlDecode(peerSigningKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!verified) {
      throw StateError('Bridge session signature verification failed.');
    }
    final sharedSecret = await _keyAgreement.sharedSecretKey(
      keyPair: sessionKeyPair,
      remotePublicKey: SimplePublicKey(
        _b64urlDecode(peerSessionPublicKey),
        type: KeyPairType.x25519,
      ),
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final salt = await deriveRelaySaltBytes(
      localNonce: sessionNonce,
      peerNonce: peerSessionNonce,
    );
    _sessionSecretKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode(settings.relayDeviceId),
    );
    final sessionId = payload['sessionId']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Relay did not provide a session identifier.');
    }
    _sessionId = sessionId;
    _sendCounter = 0;
    _receiveCounter = 0;
    if (!(_readyCompleter?.isCompleted ?? true)) {
      _readyCompleter?.complete();
    }
  }

  Future<void> _handleEncryptedFrame(Map<String, dynamic> payload) async {
    final secretKey = _sessionSecretKey;
    final sessionId = _sessionId;
    final settings = _settings;
    if (secretKey == null || sessionId == null || settings == null) {
      return;
    }
    final messageSessionId = payload['sessionId']?.toString();
    if (messageSessionId != sessionId) {
      return;
    }
    final counter = payload['counter'] as int? ?? -1;
    if (counter != _receiveCounter) {
      throw StateError(
        'Unexpected relay frame counter: expected $_receiveCounter, received $counter.',
      );
    }
    _receiveCounter += 1;
    final combined = _b64urlDecode(payload['ciphertext']?.toString() ?? '');
    if (combined.length < 16) {
      throw StateError('Relay ciphertext is truncated.');
    }
    final cipherText = combined.sublist(0, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));
    final secretBox = SecretBox(
      cipherText,
      nonce: _nonceFor(prefix: 'BRDG', counter: counter),
      mac: mac,
    );
    final plainBytes = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: _relayAad(
        counter: counter,
        deviceId: settings.relayDeviceId,
        sessionId: sessionId,
      ),
    );
    _messages.add(utf8.decode(plainBytes));
  }

  Uint8List _relayAad({
    required int counter,
    required String deviceId,
    required String sessionId,
  }) {
    return Uint8List.fromList(
      _canonicalJson(<String, dynamic>{
        'counter': counter,
        'deviceId': deviceId,
        'sessionId': sessionId,
        'type': 'relay-frame-v1',
      }),
    );
  }

  SimpleKeyPairData _clientSigningKeyPair(AppSettings settings) {
    return SimpleKeyPairData(
      _b64urlDecode(settings.relayClientPrivateKey),
      publicKey: SimplePublicKey(
        _b64urlDecode(settings.relayClientPublicKey),
        type: KeyPairType.ed25519,
      ),
      type: KeyPairType.ed25519,
    );
  }
}

class RelaySecureTransport implements AppTransport {
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final Ed25519 _signing = Ed25519();
  final X25519 _keyAgreement = X25519();
  final Cipher _cipher = Chacha20.poly1305Aead();
  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _readyCompleter;
  bool _connected = false;
  AppSettings? _settings;
  KeyPair? _sessionKeyPair;
  SecretKey? _sessionSecretKey;
  String? _sessionId;
  String? _sessionNonce;
  int _sendCounter = 0;
  int _receiveCounter = 0;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  bool get isConnected => _connected;

  void _notifyUnexpectedDisconnect() {
    _messages.addError(StateError('Transport disconnected.'));
  }

  @override
  Future<void> connect(AppSettings settings) async {
    await disconnect();
    if (settings.relayUrl.trim().isEmpty ||
        settings.relayDeviceId.trim().isEmpty ||
        settings.relayClientPrivateKey.trim().isEmpty ||
        settings.relayClientPublicKey.trim().isEmpty ||
        settings.relayBridgeSigningPublicKey.trim().isEmpty) {
      throw StateError('Relay mode is selected, but relay pairing is missing.');
    }
    final relayUri = Uri.tryParse(settings.relayUrl);
    if (relayUri == null || !relayUri.hasScheme || relayUri.host.isEmpty) {
      throw StateError('Relay URL is invalid.');
    }
    if (!_isAllowedRelayUri(relayUri)) {
      throw StateError('Relay mode requires HTTPS for non-local relay servers.');
    }
    _settings = settings;
    _readyCompleter = Completer<void>();
    _channel = IOWebSocketChannel.connect(
      relayWebSocketUri(relayUri),
      pingInterval: const Duration(seconds: 20),
      connectTimeout: const Duration(seconds: 15),
    );
    _subscription = _channel!.stream.listen(
      _handleRelayMessage,
      onError: (Object error, StackTrace stackTrace) {
        if (!(_readyCompleter?.isCompleted ?? true)) {
          _readyCompleter?.completeError(error, stackTrace);
        } else {
          _messages.addError(error, stackTrace);
        }
      },
      onDone: () {
        final wasConnected = _connected;
        _connected = false;
        if (wasConnected) {
          _notifyUnexpectedDisconnect();
        }
      },
    );
    await _readyCompleter!.future.timeout(const Duration(seconds: 20));
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _sendCounter = 0;
    _receiveCounter = 0;
    _sessionId = null;
    _sessionNonce = null;
    _sessionKeyPair = null;
    _sessionSecretKey = null;
    _settings = null;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('Transport disconnected.'));
    }
    _readyCompleter = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  Future<void> send(String payload) async {
    final ready = _readyCompleter;
    if (ready == null) {
      throw StateError('Relay transport is not connected.');
    }
    await ready.future;
    final secretKey = _sessionSecretKey;
    final sessionId = _sessionId;
    final settings = _settings;
    if (secretKey == null || sessionId == null || settings == null) {
      throw StateError('Relay session is not ready.');
    }
    final counter = _sendCounter++;
    final aad = _relayAad(
      counter: counter,
      deviceId: settings.relayDeviceId,
      sessionId: sessionId,
    );
    final secretBox = await _cipher.encrypt(
      utf8.encode(payload),
      secretKey: secretKey,
      nonce: _nonceFor(prefix: 'CLNT', counter: counter),
      aad: aad,
    );
    final combined = Uint8List.fromList(
      <int>[...secretBox.cipherText, ...secretBox.mac.bytes],
    );
    _channel?.sink.add(
      jsonEncode(<String, dynamic>{
        'counter': counter,
        'ciphertext': _b64urlEncode(combined),
        'sessionId': sessionId,
        'type': 'relay_frame',
      }),
    );
  }

  Future<void> _handleRelayMessage(dynamic event) async {
    if (event is! String) {
      return;
    }
    final payload = jsonDecode(event) as Map<String, dynamic>;
    switch (payload['type']) {
      case 'challenge':
        await _respondToChallenge(payload);
      case 'authenticated':
        break;
      case 'session_open':
        await _completeSession(payload);
      case 'relay_frame':
        await _handleEncryptedFrame(payload);
      case 'close_session':
        final sessionId = payload['sessionId']?.toString();
        if (sessionId == null || sessionId == _sessionId) {
          _messages.addError(StateError('Relay session closed by peer.'));
        }
      default:
        break;
    }
  }

  Future<void> _respondToChallenge(Map<String, dynamic> payload) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    final authNonce = _randomToken(12);
    final authTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sessionKeyPair = await _keyAgreement.newKeyPair();
    final sessionKeyPairData = await sessionKeyPair.extract();
    final sessionPublicKey = await sessionKeyPair.extractPublicKey();
    final sessionNonce = _randomToken(12);
    final signedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signingKeyPair = _clientSigningKeyPair(settings);
    final authSignature = await _signing.sign(
      _canonicalJson(<String, dynamic>{
        'authNonce': authNonce,
        'authTimestamp': authTimestamp,
        'challenge': payload['challenge'],
        'connectionId': payload['connectionId'],
        'deviceId': settings.relayDeviceId,
        'role': 'client',
        'type': 'codex-remote-auth-v1',
      }),
      keyPair: signingKeyPair,
    );
    final sessionSignature = await _signing.sign(
      _canonicalJson(<String, dynamic>{
        'deviceId': settings.relayDeviceId,
        'role': 'client',
        'sessionNonce': sessionNonce,
        'sessionPublicKey': _b64urlEncode(sessionPublicKey.bytes),
        'signedAt': signedAt,
        'type': 'codex-remote-session-bundle-v1',
      }),
      keyPair: signingKeyPair,
    );
    _sessionKeyPair = sessionKeyPairData;
    _sessionNonce = sessionNonce;
    _channel?.sink.add(
      jsonEncode(<String, dynamic>{
        'authNonce': authNonce,
        'authSignature': _b64urlEncode(authSignature.bytes),
        'authTimestamp': authTimestamp,
        'deviceId': settings.relayDeviceId,
        'role': 'client',
        'sessionBundle': <String, dynamic>{
          'sessionNonce': sessionNonce,
          'sessionPublicKey': _b64urlEncode(sessionPublicKey.bytes),
          'signature': _b64urlEncode(sessionSignature.bytes),
          'signedAt': signedAt,
        },
        'type': 'authenticate',
      }),
    );
  }

  Future<void> _completeSession(Map<String, dynamic> payload) async {
    final settings = _settings;
    final sessionKeyPair = _sessionKeyPair;
    final sessionNonce = _sessionNonce;
    if (settings == null || sessionKeyPair == null || sessionNonce == null) {
      return;
    }
    final peerSigningKey = payload['peerSigningPublicKey']?.toString() ?? '';
    if (peerSigningKey != settings.relayBridgeSigningPublicKey) {
      throw StateError('Relay bridge identity does not match the paired bridge.');
    }
    final bundle = payload['peerSessionBundle'] as Map<String, dynamic>;
    final peerSessionPublicKey = bundle['sessionPublicKey']?.toString() ?? '';
    final peerSessionNonce = bundle['sessionNonce']?.toString() ?? '';
    final signatureBytes = _b64urlDecode(bundle['signature']?.toString() ?? '');
    final verified = await _signing.verify(
      _canonicalJson(<String, dynamic>{
        'deviceId': settings.relayDeviceId,
        'role': 'bridge',
        'sessionNonce': peerSessionNonce,
        'sessionPublicKey': peerSessionPublicKey,
        'signedAt': bundle['signedAt'],
        'type': 'codex-remote-session-bundle-v1',
      }),
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          _b64urlDecode(peerSigningKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!verified) {
      throw StateError('Bridge session signature verification failed.');
    }
    final sharedSecret = await _keyAgreement.sharedSecretKey(
      keyPair: sessionKeyPair,
      remotePublicKey: SimplePublicKey(
        _b64urlDecode(peerSessionPublicKey),
        type: KeyPairType.x25519,
      ),
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final salt = await deriveRelaySaltBytes(
      localNonce: sessionNonce,
      peerNonce: peerSessionNonce,
    );
    _sessionSecretKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode(settings.relayDeviceId),
    );
    final sessionId = payload['sessionId']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Relay did not provide a session identifier.');
    }
    _sessionId = sessionId;
    _sendCounter = 0;
    _receiveCounter = 0;
    if (!(_readyCompleter?.isCompleted ?? true)) {
      _readyCompleter?.complete();
    }
  }

  Future<void> _handleEncryptedFrame(Map<String, dynamic> payload) async {
    final secretKey = _sessionSecretKey;
    final sessionId = _sessionId;
    final settings = _settings;
    if (secretKey == null || sessionId == null || settings == null) {
      return;
    }
    final messageSessionId = payload['sessionId']?.toString();
    if (messageSessionId != sessionId) {
      return;
    }
    final counter = payload['counter'] as int? ?? -1;
    if (counter != _receiveCounter) {
      throw StateError(
        'Unexpected relay frame counter: expected $_receiveCounter, received $counter.',
      );
    }
    _receiveCounter += 1;
    final combined = _b64urlDecode(payload['ciphertext']?.toString() ?? '');
    if (combined.length < 16) {
      throw StateError('Relay ciphertext is truncated.');
    }
    final cipherText = combined.sublist(0, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));
    final secretBox = SecretBox(
      cipherText,
      nonce: _nonceFor(prefix: 'BRDG', counter: counter),
      mac: mac,
    );
    final plainBytes = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: _relayAad(
        counter: counter,
        deviceId: settings.relayDeviceId,
        sessionId: sessionId,
      ),
    );
    _messages.add(utf8.decode(plainBytes));
  }

  Uint8List _relayAad({
    required int counter,
    required String deviceId,
    required String sessionId,
  }) {
    return Uint8List.fromList(
      _canonicalJson(<String, dynamic>{
        'counter': counter,
        'deviceId': deviceId,
        'sessionId': sessionId,
        'type': 'relay-frame-v1',
      }),
    );
  }

  SimpleKeyPairData _clientSigningKeyPair(AppSettings settings) {
    return SimpleKeyPairData(
      _b64urlDecode(settings.relayClientPrivateKey),
      publicKey: SimplePublicKey(
        _b64urlDecode(settings.relayClientPublicKey),
        type: KeyPairType.ed25519,
      ),
      type: KeyPairType.ed25519,
    );
  }
}

AppTransport createDefaultTransport() {
  final directTransport =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? AndroidForegroundTransport()
      : DirectWebSocketTransport();
  final relayTransport =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? AndroidRelaySecureTransport()
      : RelaySecureTransport();
  return PlatformAdaptiveTransport(
    directTransport: directTransport,
    relayTransport: relayTransport,
  );
}

bool _isAllowedRelayUri(Uri relayUri) {
  if (relayUri.scheme == 'https') {
    return true;
  }
  if (relayUri.scheme != 'http') {
    return false;
  }
  final host = relayUri.host.toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host.endsWith('.local');
}

@visibleForTesting
Uri relayWebSocketUri(Uri relayUri) {
  final wsScheme = switch (relayUri.scheme) {
    'https' => 'wss',
    'http' => 'ws',
    _ => relayUri.scheme,
  };
  final normalizedPath = relayUri.path.endsWith('/')
      ? '${relayUri.path}ws'
      : '${relayUri.path}/ws';
  return relayUri.replace(
    scheme: wsScheme,
    path: normalizedPath,
  );
}

@visibleForTesting
Future<List<int>> deriveRelaySaltBytes({
  required String localNonce,
  required String peerNonce,
}) async {
  final sorted = <String>[localNonce, peerNonce]..sort();
  final digest = await Sha256().hash(utf8.encode(sorted.join()));
  return digest.bytes;
}

String _b64urlEncode(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

Uint8List _b64urlDecode(String value) {
  final normalized = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return Uint8List.fromList(base64Url.decode(normalized));
}

Uint8List _canonicalJson(Map<String, dynamic> payload) {
  return Uint8List.fromList(utf8.encode(jsonEncode(_sortJson(payload))));
}

Object _sortJson(Object value) {
  if (value is Map<String, dynamic>) {
    final entries = value.entries.toList()
      ..sort((MapEntry<String, dynamic> a, MapEntry<String, dynamic> b) {
        return a.key.compareTo(b.key);
      });
    return Map<String, dynamic>.fromEntries(
      entries.map((entry) => MapEntry(entry.key, _sortJson(entry.value))),
    );
  }
  if (value is List<dynamic>) {
    return value
        .map((dynamic item) => _sortJson(item))
        .toList(growable: false);
  }
  return value;
}

String _randomToken(int length) {
  final random = Random.secure();
  final seed = Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
  return _b64urlEncode(seed);
}

Uint8List _nonceFor({required String prefix, required int counter}) {
  final bytes = ByteData(12);
  final prefixBytes = ascii.encode(prefix);
  for (var i = 0; i < 4; i += 1) {
    bytes.setUint8(i, prefixBytes[i]);
  }
  bytes.setUint64(4, counter);
  return bytes.buffer.asUint8List();
}
