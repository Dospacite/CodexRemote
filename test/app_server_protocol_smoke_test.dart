import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const runSmokeEnv = 'CODEX_REMOTE_RUN_APP_SERVER_SMOKE';
  final shouldRunSmoke = Platform.environment[runSmokeEnv] == '1';

  test('app-server websocket smoke test', () async {
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:5000',
    ).timeout(const Duration(seconds: 5));
    addTearDown(() async {
      await socket.close();
    });

    final messages = StreamIterator<dynamic>(socket);
    var requestId = 0;
    final streamedOutputByProcessId = <String, StringBuffer>{};

    Future<Map<String, dynamic>> request(
      String method, [
      Map<String, dynamic>? params,
    ]) async {
      requestId += 1;
      socket.add(
        jsonEncode(<String, dynamic>{
          'id': requestId,
          'method': method,
          'params': params ?? <String, dynamic>{},
        }),
      );

      while (true) {
        final advanced = await messages.moveNext().timeout(
          const Duration(seconds: 10),
        );
        if (!advanced) {
          fail('Socket closed while waiting for response to $method.');
        }
        final decoded =
            jsonDecode(messages.current as String) as Map<String, dynamic>;
        if (decoded['method'] == 'command/exec/outputDelta') {
          final params =
              decoded['params'] as Map<String, dynamic>? ?? <String, dynamic>{};
          final processId = params['processId']?.toString();
          final deltaBase64 = params['deltaBase64']?.toString();
          if (processId != null && deltaBase64 != null) {
            streamedOutputByProcessId.putIfAbsent(processId, StringBuffer.new);
            streamedOutputByProcessId[processId]!.write(
              utf8.decode(base64Decode(deltaBase64), allowMalformed: true),
            );
          }
          continue;
        }
        if (decoded['id'] == requestId) {
          final error = decoded['error'];
          if (error != null) {
            fail('JSON-RPC $method failed: $error');
          }
          return decoded['result'] as Map<String, dynamic>;
        }
      }
    }

    final initialize = await request('initialize', <String, dynamic>{
      'clientInfo': <String, dynamic>{
        'name': 'codex_remote_smoke_test',
        'title': 'Codex Remote Smoke Test',
        'version': '1.0.0',
      },
    });
    expect(initialize['codexHome'], isNotNull);

    socket.add(jsonEncode(<String, dynamic>{'method': 'initialized'}));

    final threadStart = await request('thread/start');
    final thread = threadStart['thread'] as Map<String, dynamic>;
    final threadId = thread['id'] as String;
    expect(threadId, isNotEmpty);
    expect(threadStart['approvalPolicy'], isNotNull);
    expect(threadStart['sandbox'], isNotNull);

    final threadList = await request('thread/list', <String, dynamic>{
      'limit': 10,
      'sortKey': 'updated_at',
    });
    final listedThreads = threadList['data'] as List<dynamic>;
    expect(listedThreads, isA<List<dynamic>>());
    expect(threadList.containsKey('nextCursor'), isTrue);

    final threadRead = await request('thread/read', <String, dynamic>{
      'threadId': threadId,
    });
    final readThread = threadRead['thread'] as Map<String, dynamic>;
    expect(readThread['id'], threadId);
    expect(readThread['turns'], isA<List<dynamic>>());

    final turnStart = await request('turn/start', <String, dynamic>{
      'threadId': threadId,
      'input': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': 'Protocol smoke test.'},
      ],
    });
    final turn = turnStart['turn'] as Map<String, dynamic>;
    expect(turn['id'], isNotNull);
    expect(turn['status'], 'inProgress');

    const bufferedProcessId = 'smoke-buffered';
    final bufferedExec = await request('command/exec', <String, dynamic>{
      'processId': bufferedProcessId,
      'command': <String>['/bin/echo', 'codex-remote'],
      'streamStdoutStderr': true,
    });
    expect(bufferedExec['exitCode'], 0);
    expect(
      streamedOutputByProcessId[bufferedProcessId]?.toString(),
      contains('codex-remote'),
    );

    const interactiveProcessId = 'smoke-interactive';
    requestId += 1;
    final interactiveExecId = requestId;
    socket.add(
      jsonEncode(<String, dynamic>{
        'id': interactiveExecId,
        'method': 'command/exec',
        'params': <String, dynamic>{
          'processId': interactiveProcessId,
          'command': <String>['/bin/cat'],
          'streamStdin': true,
          'streamStdoutStderr': true,
        },
      }),
    );

    requestId += 1;
    final interactiveWriteId = requestId;
    socket.add(
      jsonEncode(<String, dynamic>{
        'id': interactiveWriteId,
        'method': 'command/exec/write',
        'params': <String, dynamic>{
          'processId': interactiveProcessId,
          'deltaBase64': base64Encode(utf8.encode('ping-from-test\n')),
          'closeStdin': true,
        },
      }),
    );

    Map<String, dynamic>? interactiveExec;
    var sawWriteAck = false;
    while (interactiveExec == null || !sawWriteAck) {
      final advanced = await messages.moveNext().timeout(
        const Duration(seconds: 10),
      );
      if (!advanced) {
        fail('Socket closed while waiting for interactive command responses.');
      }
      final decoded =
          jsonDecode(messages.current as String) as Map<String, dynamic>;
      if (decoded['method'] == 'command/exec/outputDelta') {
        final params =
            decoded['params'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final processId = params['processId']?.toString();
        final deltaBase64 = params['deltaBase64']?.toString();
        if (processId != null && deltaBase64 != null) {
          streamedOutputByProcessId.putIfAbsent(processId, StringBuffer.new);
          streamedOutputByProcessId[processId]!.write(
            utf8.decode(base64Decode(deltaBase64), allowMalformed: true),
          );
        }
        continue;
      }
      if (decoded['id'] == interactiveWriteId) {
        final error = decoded['error'];
        if (error != null) {
          fail('JSON-RPC command/exec/write failed: $error');
        }
        sawWriteAck = true;
      }
      if (decoded['id'] == interactiveExecId) {
        final error = decoded['error'];
        if (error != null) {
          fail('JSON-RPC command/exec failed: $error');
        }
        interactiveExec = decoded['result'] as Map<String, dynamic>;
      }
    }

    expect(interactiveExec['exitCode'], 0);
    expect(
      streamedOutputByProcessId[interactiveProcessId]?.toString(),
      contains('ping-from-test'),
    );
  }, skip: !shouldRunSmoke
      ? 'Set $runSmokeEnv=1 when a local app-server is listening on ws://127.0.0.1:5000.'
      : false);
}
