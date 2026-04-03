import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:codex_remote/src/app.dart';
import 'package:codex_remote/src/app_controller.dart';
import 'package:codex_remote/src/home_page.dart';
import 'package:codex_remote/src/models.dart';
import 'package:codex_remote/src/transport.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('app renders compact chat shell without status card', (
    WidgetTester tester,
  ) async {
    final controller = AppController.testing();
    controller.entries.addAll(<ActivityEntry>[
      ActivityEntry(
        key: 'user-1',
        kind: EntryKind.user,
        title: 'You',
        body: 'User message',
      ),
      ActivityEntry(
        key: 'agent-1',
        kind: EntryKind.agent,
        title: 'Codex',
        body: 'Agent message',
      ),
    ]);
    controller.pendingPrompts.add(
      const PendingPrompt(
        id: 'pending-1',
        text: 'Queued prompt',
        mode: PendingPromptMode.queued,
      ),
    );
    controller.rateLimitSummary = '1h 77% left • 1d 42% left';
    controller.contextWindowSummary = '75% ctx';
    controller.contextUsagePercent = 75;
    controller.modelOptions.add(
      const ModelOption(
        id: 'model_1',
        model: 'gpt-5.4',
        displayName: 'GPT-5.4',
        description: 'Default frontier model',
        isDefault: true,
        hidden: false,
      ),
    );

    await tester.pumpWidget(CodexRemoteApp(controller: controller));

    expect(find.text('Message Codex...'), findsOneWidget);
    expect(find.text('Plan off'), findsOneWidget);
    expect(find.text('GPT-5.4'), findsOneWidget);
    expect(find.text('medium'), findsOneWidget);
    expect(find.text('Queued prompt'), findsOneWidget);
    expect(find.text('1 queued'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('composer-meta-left-text')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('composer-meta-right-indicator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('composer-meta-right-percent')),
      findsOneWidget,
    );
    expect(find.text('1h 77% left • 1d 42% left'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('User message'), findsOneWidget);
    expect(find.text('Agent message'), findsOneWidget);
    expect(find.text('Threads'), findsNothing);
    expect(find.text('Event log'), findsNothing);
    expect(find.text('Command'), findsNothing);
    expect(find.byTooltip('Files'), findsOneWidget);
    expect(find.byTooltip('Automations'), findsOneWidget);
    expect(find.byTooltip('Downloads'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('New thread'), findsNothing);
    expect(find.textContaining('Status:'), findsNothing);
    expect(find.textContaining('Server:'), findsNothing);
    expect(find.textContaining('Thread:'), findsNothing);
    expect(find.textContaining('Mode:'), findsNothing);
  });

  testWidgets('agent messages render markdown formatting', (
    WidgetTester tester,
  ) async {
    final controller = AppController.testing();
    controller.entries.add(
      ActivityEntry(
        key: 'agent-md',
        kind: EntryKind.agent,
        title: 'Codex',
        body: '# Heading\n\nUse `code` and **bold** text.',
      ),
    );

    await tester.pumpWidget(CodexRemoteApp(controller: controller));

    expect(find.text('Heading'), findsOneWidget);
    expect(find.textContaining('Use'), findsOneWidget);
    expect(find.textContaining('bold'), findsOneWidget);
  });

  testWidgets(
    'long-pressing a user message exposes copy and edit, and edit loads the composer',
    (WidgetTester tester) async {
      final controller = AppController.testing();
      controller.entries.add(
        ActivityEntry(
          key: 'user-1',
          kind: EntryKind.user,
          title: 'You',
          body: 'Editable message',
        ),
      );

      await tester.pumpWidget(CodexRemoteApp(controller: controller));

      await tester.longPress(find.text('Editable message'));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      final composer = tester.widget<TextField>(find.byType(TextField));
      expect(composer.controller?.text, 'Editable message');
    },
  );

  testWidgets('settings exposes websocket bearer token field', (
    WidgetTester tester,
  ) async {
    final controller = AppController.testing();

    await tester.pumpWidget(CodexRemoteApp(controller: controller));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Websocket bearer token'), findsOneWidget);
    expect(find.text('Model override'), findsNothing);
    expect(
      find.text(
        'Sent during the websocket handshake when app-server auth is enabled.',
      ),
      findsOneWidget,
    );
    expect(find.text('Remote cwd'), findsNothing);
  });

  testWidgets('automation page filters to current thread by default', (
    WidgetTester tester,
  ) async {
    final controller = AppController.testing();
    controller.activeThreadId = 'thread-a';
    controller.automations.addAll(<AutomationDefinition>[
      const AutomationDefinition(
        id: 'automation-a',
        name: 'Current thread automation',
        enabled: true,
        ownerThreadId: 'thread-a',
        nodes: <AutomationNode>[],
      ),
      const AutomationDefinition(
        id: 'automation-b',
        name: 'Other thread automation',
        enabled: true,
        ownerThreadId: 'thread-b',
        nodes: <AutomationNode>[],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: AutomationPage(controller: controller)),
    );

    expect(find.text('Current thread automation'), findsOneWidget);
    expect(find.text('Other thread automation'), findsNothing);

    await tester.tap(find.text('Current'));
    await tester.pumpAndSettle();

    expect(find.text('Current thread automation'), findsOneWidget);
    expect(find.text('Other thread automation'), findsOneWidget);
  });

  testWidgets(
    'non-current thread automations can be copied to the current thread',
    (WidgetTester tester) async {
      final controller = AppController.testing();
      controller.activeThreadId = 'thread-a';
      controller.automations.addAll(<AutomationDefinition>[
        const AutomationDefinition(
          id: 'automation-a',
          name: 'Current thread automation',
          enabled: true,
          ownerThreadId: 'thread-a',
          nodes: <AutomationNode>[
            AutomationNode(id: 'node-a', kind: AutomationNodeKind.runCommand),
          ],
        ),
        const AutomationDefinition(
          id: 'automation-b',
          name: 'Other thread automation',
          enabled: true,
          ownerThreadId: 'thread-b',
          nodes: <AutomationNode>[
            AutomationNode(id: 'node-b', kind: AutomationNodeKind.runCommand),
          ],
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: AutomationPage(controller: controller)),
      );

      await tester.tap(find.text('Current'));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      final copiedAutomations = controller.automations
          .where((automation) => automation.name == 'Other thread automation')
          .toList(growable: false);
      expect(copiedAutomations, hasLength(2));
      expect(
        copiedAutomations.where(
          (automation) => automation.ownerThreadId == 'thread-a',
        ),
        hasLength(1),
      );
      expect(
        copiedAutomations.where(
          (automation) => automation.ownerThreadId == 'thread-b',
        ),
        hasLength(1),
      );
      expect(copiedAutomations[0].id == copiedAutomations[1].id, isFalse);
      expect(
        copiedAutomations[0].nodes.first.id ==
            copiedAutomations[1].nodes.first.id,
        isFalse,
      );
    },
  );

  testWidgets(
    'composer does not keep autofocus after returning from settings',
    (WidgetTester tester) async {
      final controller = AppController.testing();

      await tester.pumpWidget(CodexRemoteApp(controller: controller));

      await tester.tap(find.byType(TextField).first);
      await tester.pump();

      final focusedComposer = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(focusedComposer.focusNode?.hasFocus, isTrue);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Websocket bearer token'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final unfocusedComposer = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(unfocusedComposer.focusNode?.hasFocus, isFalse);
    },
  );

  testWidgets(
    'automation trigger paths can be picked from the remote file explorer',
    (WidgetTester tester) async {
      final controller = AppController.testing(transport: _FakeTransport());
      controller.activeThreadCwd = '/thread-cwd';

      await tester.pumpWidget(
        MaterialApp(
          home: AutomationNodeEditorPage(
            controller: controller,
            node: const AutomationNode(
              id: 'node_1',
              kind: AutomationNodeKind.watchFileChanged,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Browse remote files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();

      final pathField = tester.widget<TextField>(find.byType(TextField).first);
      expect(pathField.controller?.text, '/thread-cwd/README.md');
    },
  );

  testWidgets(
    'threads button shows a progress indicator while history is loading',
    (WidgetTester tester) async {
      final controller = AppController.testing();
      controller.isLoadingHistory = true;

      await tester.pumpWidget(CodexRemoteApp(controller: controller));

      expect(find.byTooltip('Threads'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byTooltip('Threads'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('command center exposes full standalone command workflow', (
    WidgetTester tester,
  ) async {
    final controller = AppController.testing();
    controller.recentCommands.add(
      const RecentCommand(
        commandText: 'git status',
        cwd: '/workspace/project',
        mode: CommandSessionMode.buffered,
        sandboxMode: SandboxMode.workspaceWrite,
        allowNetwork: false,
        disableTimeout: false,
        timeoutMs: 60000,
        disableOutputCap: false,
        outputBytesCap: 32768,
      ),
    );

    await tester.pumpWidget(CodexRemoteApp(controller: controller));
    await tester.tap(find.byTooltip('Command'));
    await tester.pumpAndSettle();

    expect(find.text('Command Center'), findsOneWidget);
    expect(find.text('Buffered'), findsOneWidget);
    expect(find.text('Interactive'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Run command'), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);
    expect(find.text('Clear finished'), findsOneWidget);
    expect(find.text('Clear all'), findsOneWidget);
  });

  test(
    'sending a prompt creates an immediate local pending user entry',
    () async {
      final transport = _FakeTransport();
      final gate = Completer<void>();
      transport.delayNextTurnStart = gate;
      final controller = AppController.testing(transport: transport);

      final sendFuture = controller.sendPrompt('Optimistic message');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.entries, isNotEmpty);
      final optimistic = controller.entries.last;
      expect(optimistic.kind, EntryKind.user);
      expect(optimistic.body, 'Optimistic message');
      expect(optimistic.isLocalPending, isTrue);

      gate.complete();
      await sendFuture;

      expect(controller.entries.last.isLocalPending, isTrue);

      transport.emitNotification('item/completed', <String, dynamic>{
        'turnId': 'turn_1',
        'item': <String, dynamic>{
          'id': 'user_msg_1',
          'type': 'userMessage',
          'content': <dynamic>[
            <String, dynamic>{'type': 'text', 'text': 'Optimistic message'},
          ],
          'status': 'completed',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.entries.last.key, 'user_msg_1');
      expect(controller.entries.last.isLocalPending, isFalse);
    },
  );

  testWidgets('pending local user messages render with the sending sheen', (
    WidgetTester tester,
  ) async {
    final controller = AppController.testing();
    controller.entries.add(
      ActivityEntry(
        key: 'pending-user-1',
        kind: EntryKind.user,
        title: 'You',
        body: 'Sending image...',
        isLocalPending: true,
      ),
    );

    await tester.pumpWidget(CodexRemoteApp(controller: controller));

    expect(find.text('Sending image...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pending-message-sheen')),
      findsOneWidget,
    );
  });

  testWidgets('file changes render in a git-style diff view', (
    WidgetTester tester,
  ) async {
    final controller = AppController.testing();
    controller.entries.add(
      ActivityEntry(
        key: 'diff-1',
        kind: EntryKind.fileChange,
        title: 'File change',
        body: [
          'lib/src/app.dart • modified',
          'diff --git a/lib/src/app.dart b/lib/src/app.dart',
          'index 1111111..2222222 100644',
          '--- a/lib/src/app.dart',
          '+++ b/lib/src/app.dart',
          '@@ -1,3 +1,4 @@',
          '-old line',
          '+new line',
          ' context line',
        ].join('\n'),
      ),
    );

    await tester.pumpWidget(CodexRemoteApp(controller: controller));

    expect(find.byKey(const ValueKey<String>('git-diff-view')), findsOneWidget);
    expect(
      find.text('diff --git a/lib/src/app.dart b/lib/src/app.dart'),
      findsOneWidget,
    );
    expect(find.text('-old line'), findsOneWidget);
    expect(find.text('+new line'), findsOneWidget);
  });

  testWidgets('tool outputs collapse by default and can be expanded', (
    WidgetTester tester,
  ) async {
    final controller = AppController.testing();
    final longBody = List<String>.generate(
      24,
      (index) => 'tool output line ${index + 1}',
    ).join('\n');
    controller.entries.add(
      ActivityEntry(
        key: 'tool-1',
        kind: EntryKind.tool,
        title: 'Tool call',
        body: longBody,
      ),
    );

    await tester.pumpWidget(CodexRemoteApp(controller: controller));

    expect(
      find.byKey(const ValueKey<String>('entry-body-expand')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('entry-body-expand')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('entry-body-collapse')),
      findsOneWidget,
    );
  });

  testWidgets('command outputs collapse by default and can be expanded', (
    WidgetTester tester,
  ) async {
    final controller = AppController.testing();
    final longBody = List<String>.generate(
      24,
      (index) => 'command output line ${index + 1}',
    ).join('\n');
    controller.entries.add(
      ActivityEntry(
        key: 'command-1',
        kind: EntryKind.command,
        title: 'Command',
        body: longBody,
      ),
    );

    await tester.pumpWidget(CodexRemoteApp(controller: controller));

    expect(
      find.byKey(const ValueKey<String>('entry-body-expand')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('entry-body-expand')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('entry-body-collapse')),
      findsOneWidget,
    );
  });

  test(
    'controller queues active-turn prompts and drains them on completion',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.sendPrompt('first');
      expect(transport.turnStartCount, 1);
      expect(controller.activeTurnId, 'turn_1');

      await controller.sendPrompt('second');
      expect(controller.queuedPromptCount, 1);
      expect(controller.queuedPrompts.first, 'second');

      transport.emitNotification('turn/completed', <String, dynamic>{
        'threadId': 'thr_1',
        'turn': <String, dynamic>{
          'id': 'turn_1',
          'status': 'completed',
          'items': <dynamic>[],
          'error': null,
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.queuedPromptCount, 0);
      expect(transport.turnStartCount, 2);
      expect(controller.activeTurnId, 'turn_2');
    },
  );

  test(
    'controller starts the next turn after final answer without waiting for turn completed',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.sendPrompt('first');
      transport.emitNotification('item/completed', <String, dynamic>{
        'threadId': 'thr_1',
        'turnId': 'turn_1',
        'item': <String, dynamic>{
          'id': 'msg_1',
          'type': 'agentMessage',
          'text': 'done',
          'phase': 'final_answer',
        },
      });

      await controller.sendPrompt('second');

      expect(transport.turnStartCount, 2);
      expect(controller.queuedPromptCount, 0);
      expect(controller.activeTurnId, 'turn_2');
    },
  );

  test(
    'queued prompt drains after final answer even before turn completed',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.sendPrompt('first');
      await controller.sendPrompt('second');
      expect(controller.queuedPromptCount, 1);

      transport.emitNotification('item/completed', <String, dynamic>{
        'threadId': 'thr_1',
        'turnId': 'turn_1',
        'item': <String, dynamic>{
          'id': 'msg_1',
          'type': 'agentMessage',
          'text': 'done',
          'phase': 'final_answer',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.queuedPromptCount, 0);
      expect(transport.turnStartCount, 2);
      expect(controller.activeTurnId, 'turn_2');
    },
  );

  test(
    'controller supports explicit steering while a turn is active',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.sendPrompt('first');
      final accepted = await controller.steerPrompt('refine it');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(accepted, isTrue);
      expect(transport.turnSteerCount, 1);
      expect(controller.queuedPromptCount, 0);
    },
  );

  test('controller sends websocket bearer token during connect', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);
    await controller.saveSettings(
      controller.settings.copyWith(websocketBearerToken: 'cap-token-123'),
    );

    await controller.connect();

    expect(transport.lastBearerToken, 'cap-token-123');
    expect(transport.connectCount, 1);
  });

  test('controller reconnects when websocket bearer token changes', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.connect();
    expect(transport.connectCount, 1);

    await controller.reconnectWithSettings(
      controller.settings.copyWith(websocketBearerToken: 'signed-token-456'),
    );

    expect(transport.connectCount, 2);
    expect(transport.lastBearerToken, 'signed-token-456');
  });

  test('controller starts a fresh thread in the selected directory', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.connect();
    await controller.startFreshThreadInDirectory('/workspace/project');

    expect(transport.lastThreadStartCwd, '/workspace/project');
    expect(controller.activeThreadCwd, '/workspace/project');
  });

  test(
    'file browser falls back when fs/readDirectory fails on /home/ege',
    () async {
      final transport = _FakeTransport()..failHomeDirectoryRead = true;
      final controller = AppController.testing(transport: transport);

      await controller.loadDirectory('/home/ege');

      expect(controller.fileBrowserError, isNull);
      expect(controller.fileBrowserPath, '/home/ege');
      expect(
        controller.fileBrowserEntries.map((entry) => entry.fileName),
        containsAll(<String>['Documents', '.steampath']),
      );
    },
  );

  test('sendPrompt connects before starting a turn', () async {
    final transport = _StrictConnectFakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.sendPrompt('hello');

    expect(transport.connectCount, 1);
    expect(transport.turnStartCount, 1);
    expect(transport.sentBeforeConnect, isFalse);
    expect(controller.activeThreadId, 'thr_1');
  });

  test('pending prompts can be taken back for editing and cancelled', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.sendPrompt('first');
    await controller.sendPrompt('second');
    expect(controller.queuedPromptCount, 1);

    final pendingId = controller.pendingPrompts.first.id;
    final restored = controller.takePendingPromptForEditing(pendingId);
    expect(restored?.text, 'second');
    expect(controller.queuedPromptCount, 0);

    await controller.sendPrompt('third');
    expect(controller.queuedPromptCount, 1);
    controller.cancelPendingPrompt(controller.pendingPrompts.first.id);
    expect(controller.queuedPromptCount, 0);
  });

  test(
    'interactive command output collapses malformed one-char-per-line streams',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.startCommandExecution(
        commandText: 'flutter build apk --release',
        cwd: '',
        sandboxMode: SandboxMode.workspaceWrite,
        allowNetwork: false,
        mode: CommandSessionMode.interactive,
        timeoutMs: 60000,
        disableTimeout: false,
        outputBytesCap: 32768,
        disableOutputCap: false,
      );

      final session = controller.activeCommandSession!;
      transport.emitNotification('command/exec/outputDelta', <String, dynamic>{
        'processId': session.processId,
        'stream': 'stdout',
        'deltaBase64': base64Encode(
          utf8.encode('f\nl\nu\nt\nt\ne\nr\n \nb\nu\ni\nl\nd\n'),
        ),
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(session.stdout, contains('flutter build'));
    },
  );

  test(
    'interactive command output preserves terminal carriage-return updates',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.startCommandExecution(
        commandText: 'flutter build apk --release',
        cwd: '',
        sandboxMode: SandboxMode.workspaceWrite,
        allowNetwork: false,
        mode: CommandSessionMode.interactive,
        timeoutMs: 60000,
        disableTimeout: false,
        outputBytesCap: 32768,
        disableOutputCap: false,
      );

      final session = controller.activeCommandSession!;
      void emitChunk(String value) {
        transport
            .emitNotification('command/exec/outputDelta', <String, dynamic>{
              'processId': session.processId,
              'stream': 'stdout',
              'deltaBase64': base64Encode(utf8.encode(value)),
            });
      }

      emitChunk(
        "Running Gradle task 'assembleRelease'...                               ",
      );
      emitChunk('⣽');
      emitChunk('\b');
      emitChunk('⣻');
      emitChunk('\b');
      emitChunk('⢿');
      emitChunk('\r');
      emitChunk("Running Gradle task 'assembleRelease'... 12.3s");
      emitChunk('\r\n');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        session.stdout,
        contains("Running Gradle task 'assembleRelease'... 12.3s"),
      );
      expect(session.stdout.contains('\n⣽'), isFalse);
    },
  );

  test(
    'interactive flutter commands stream without requesting a tty',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.startCommandExecution(
        commandText: 'flutter analyze',
        cwd: '',
        sandboxMode: SandboxMode.workspaceWrite,
        allowNetwork: false,
        mode: CommandSessionMode.interactive,
        timeoutMs: 60000,
        disableTimeout: false,
        outputBytesCap: 32768,
        disableOutputCap: false,
      );

      final session = controller.activeCommandSession!;
      expect(session.isInteractive, isTrue);
      expect(session.usesTty, isFalse);
      expect(transport.lastCommandUsesTty, isFalse);
      expect(transport.lastCommandStreamsStdin, isTrue);
    },
  );

  test('command execution defaults to the active thread cwd', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.sendPrompt('first');
    await controller.startCommandExecution(
      commandText: 'pwd',
      cwd: '',
      sandboxMode: SandboxMode.workspaceWrite,
      allowNetwork: false,
      mode: CommandSessionMode.buffered,
      timeoutMs: 60000,
      disableTimeout: false,
      outputBytesCap: 32768,
      disableOutputCap: false,
    );

    expect(transport.lastCommandCwd, '/thread-cwd');
  });

  test(
    'thread started notifications do not override an already selected thread',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.sendPrompt('first');
      expect(controller.activeThreadId, 'thr_1');

      transport.emitNotification('thread/started', <String, dynamic>{
        'thread': <String, dynamic>{'id': 'thr_newer', 'cwd': '/other-cwd'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.activeThreadId, 'thr_1');
      expect(controller.activeThreadCwd, '/thread-cwd');
      expect(controller.settings.resumeThreadId, 'thr_1');
    },
  );

  test('renaming a thread updates the active thread title', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.sendPrompt('first');
    await controller.renameThread('thr_1', 'Renamed thread');

    expect(controller.activeThreadName, 'Renamed thread');
  });

  testWidgets('active thread is renamed from the app bar title', (
    WidgetTester tester,
  ) async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.sendPrompt('first');
    await tester.pumpWidget(CodexRemoteApp(controller: controller));

    expect(find.text('Thread One'), findsOneWidget);

    await tester.tap(find.text('Thread One'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Rename thread'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Renamed in app bar');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(controller.activeThreadName, 'Renamed in app bar');
    expect(find.text('Renamed in app bar'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
  });

  test('file browser lists directories and previews files', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.openFileBrowser(path: '/thread-cwd');
    expect(controller.fileBrowserPath, '/thread-cwd');
    expect(controller.fileBrowserEntries.length, 2);
    expect(controller.fileBrowserEntries.first.fileName, 'lib');

    await controller.openFile('/thread-cwd/README.md');
    expect(controller.selectedFilePath, '/thread-cwd/README.md');
    expect(controller.selectedFileContent, contains('hello from fs'));
    expect(controller.selectedFileBytes, isNotNull);
    expect(controller.selectedFileIsHumanReadable, isTrue);
  });

  test('binary files are downloadable but not previewed as text', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.openFile('/thread-cwd/archive.bin');

    expect(controller.selectedFileBytes, isNotNull);
    expect(controller.selectedFileIsHumanReadable, isFalse);
    expect(controller.selectedFileContent, isNull);
  });

  test(
    'human-readable files can be edited and saved through fs/writeFile',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.openFile('/thread-cwd/README.md');
      await controller.saveOpenedFileContent('edited file\nline two\n');
      await controller.openFile('/thread-cwd/README.md');

      expect(controller.selectedFileContent, 'edited file\nline two\n');
      expect(
        utf8.decode(controller.selectedFileBytes!),
        'edited file\nline two\n',
      );
    },
  );

  test(
    'controller sends text files inline and images as image inputs',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.sendPrompt(
        'Review these',
        attachments: <ComposerAttachment>[
          ComposerAttachment(
            id: 'file-1',
            fileName: 'notes.md',
            kind: ComposerAttachmentKind.textFile,
            bytes: Uint8List.fromList(utf8.encode('# Notes')),
            textContent: '# Notes',
          ),
          ComposerAttachment(
            id: 'image-1',
            fileName: 'image.png',
            kind: ComposerAttachmentKind.image,
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            mimeType: 'image/png',
          ),
        ],
      );

      final input = transport.lastTurnStartInput!;
      expect(input.first['type'], 'text');
      expect(input.first['text'], contains('Attached file: notes.md'));
      expect(input.last, <String, dynamic>{
        'type': 'image',
        'url': 'data:image/png;base64,AQID',
      });
    },
  );

  test(
    'switching threads unsubscribes the previous thread subscription',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.resumeThreadFromHistory('thr_1');
      controller.activeTurnId = null;
      await controller.resumeThreadFromHistory('thr_2');

      expect(transport.unsubscribedThreadIds, contains('thr_1'));
      expect(controller.activeThreadId, 'thr_2');
    },
  );

  test('file download streams to the chosen directory', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(
      transport: transport,
      httpClientFactory: () => _FakeHttpClient(_FakeTransport._downloadBody),
    );
    controller.activeThreadCwd = '/thread-cwd';
    final picker = _FakeFilePicker();
    final tempDir = await Directory.systemTemp.createTemp(
      'codex_download_test_',
    );
    picker.directoryPath = tempDir.path;
    FilePicker.platform = picker;

    try {
      final savedPath = await controller.saveFileToDevice(
        '/thread-cwd/README.md',
      );

      expect(picker.requestedDirectoryDialogTitle, 'Choose download location');
      final savedFile = File(
        '${tempDir.path}${Platform.pathSeparator}README.md',
      );
      expect(savedPath, savedFile.path);
      expect(await savedFile.exists(), isTrue);
      expect(
        await savedFile.readAsString(),
        'hello from fs\nsecond line\nthird line\n',
      );
      expect(transport.lastDownloadDisableTimeout, isTrue);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test(
    'file downloads use an incremented name when the destination already exists',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(
        transport: transport,
        httpClientFactory: () => _FakeHttpClient(_FakeTransport._downloadBody),
      );
      final picker = _FakeFilePicker();
      final tempDir = await Directory.systemTemp.createTemp(
        'codex_duplicate_download_',
      );
      picker.directoryPath = tempDir.path;
      FilePicker.platform = picker;

      try {
        final existingFile = File(
          '${tempDir.path}${Platform.pathSeparator}README.md',
        );
        await existingFile.writeAsString('existing');

        final savedPath = await controller.saveFileToDevice(
          '/thread-cwd/README.md',
        );

        final duplicateFile = File(
          '${tempDir.path}${Platform.pathSeparator}README (1).md',
        );
        expect(savedPath, duplicateFile.path);
        expect(await duplicateFile.exists(), isTrue);
        expect(
          await duplicateFile.readAsString(),
          'hello from fs\nsecond line\nthird line\n',
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'file downloads reuse the remembered directory for the active thread',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(
        transport: transport,
        httpClientFactory: () => _FakeHttpClient(_FakeTransport._downloadBody),
      );
      controller.activeThreadId = 'thr_1';
      final picker = _FakeFilePicker();
      final tempDir = await Directory.systemTemp.createTemp(
        'codex_thread_download_',
      );
      picker.directoryPath = tempDir.path;
      FilePicker.platform = picker;

      try {
        final firstPath = await controller.saveFileToDevice(
          '/thread-cwd/README.md',
        );
        expect(firstPath, isNotNull);
        expect(picker.directoryRequestCount, 1);

        picker.directoryPath = null;
        final secondPath = await controller.saveFileToDevice(
          '/thread-cwd/README.md',
        );

        expect(secondPath, isNotNull);
        expect(picker.directoryRequestCount, 1);
        expect(
          controller.settings.threadDownloadDirectories['thr_1'],
          tempDir.path,
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test('relay file downloads use bridge http download', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(
      transport: transport,
      httpClientFactory: () => _FakeHttpClient(_FakeTransport._downloadBody),
    );
    await controller.connect();
    await controller.saveSettings(
      controller.settings.copyWith(
        connectionMode: ConnectionMode.relay,
        relayUrl: 'https://relay.example.com',
      ),
    );
    final picker = _FakeFilePicker();
    final tempDir = await Directory.systemTemp.createTemp(
      'codex_relay_download_',
    );
    picker.directoryPath = tempDir.path;
    FilePicker.platform = picker;

    try {
      final savedPath = await controller.saveFileToDevice(
        '/thread-cwd/README.md',
      );

      final savedFile = File(
        '${tempDir.path}${Platform.pathSeparator}README.md',
      );
      expect(savedPath, savedFile.path);
      expect(await savedFile.exists(), isTrue);
      expect(
        await savedFile.readAsString(),
        'hello from fs\nsecond line\nthird line\n',
      );
      expect(transport.lastDownloadDisableTimeout, isNull);
      expect(controller.downloadRecords.first.status?.progress, 1);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('relay connections report the relay endpoint in the status log', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);
    await controller.saveSettings(
      controller.settings.copyWith(
        connectionMode: ConnectionMode.relay,
        relayUrl: 'https://relay.example.com',
      ),
    );

    await controller.connect();

    expect(controller.status, ConnectionStatus.ready);
    expect(
      controller.entries.any(
        (entry) => entry.body == 'Connected to https://relay.example.com.',
      ),
      isTrue,
    );
  });

  testWidgets(
    'file preview opens as a full-screen route from the file browser',
    (WidgetTester tester) async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);
      controller.activeThreadCwd = '/thread-cwd';

      await tester.pumpWidget(CodexRemoteApp(controller: controller));
      await tester.tap(find.byTooltip('Files'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('README.md'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('/thread-cwd/README.md'), findsOneWidget);
      expect(find.textContaining('hello from fs'), findsOneWidget);
    },
  );

  testWidgets('file preview supports editing and saving human-readable files', (
    WidgetTester tester,
  ) async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);
    controller.activeThreadCwd = '/thread-cwd';

    await tester.pumpWidget(CodexRemoteApp(controller: controller));
    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('README.md'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).last,
      'updated from editor\nsecond line\n',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(
      controller.selectedFileContent,
      'updated from editor\nsecond line\n',
    );
  });

  testWidgets(
    'message file references open the preview and highlight the referenced line',
    (WidgetTester tester) async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);
      controller.activeThreadCwd = '/thread-cwd';
      controller.entries.add(
        ActivityEntry(
          key: 'agent-ref',
          kind: EntryKind.agent,
          title: 'Codex',
          body: 'Open [README.md](README.md#L2) for the relevant line.',
        ),
      );

      await tester.pumpWidget(CodexRemoteApp(controller: controller));

      await tester.tap(find.textContaining('README.md', findRichText: true));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('/thread-cwd/README.md'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('highlighted-file-line')),
        findsOneWidget,
      );
      expect(find.text('second line'), findsOneWidget);
    },
  );

  test('model options are loaded from the api', () async {
    final transport = _FakeTransport();
    final controller = AppController.testing(transport: transport);

    await controller.loadModelOptions(force: true);

    expect(controller.modelOptions, isNotEmpty);
    expect(controller.modelOptions.first.model, 'gpt-5.4');
  });

  test(
    'controller loads rate limits and context window metadata from the api',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.connect();

      expect(controller.rateLimitSummary, '1h 77% left • 1d 42% left');
      expect(controller.contextWindowSummary, '128k window');
      expect(controller.contextUsagePercent, isNull);
      expect(controller.composerMetaLeftText, '1h 77% left • 1d 42% left');
      expect(controller.composerMetaRightText, '128k window');
    },
  );

  test(
    'active thread token usage updates context summary from notifications',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.sendPrompt('first');
      transport.emitNotification('thread/tokenUsage/updated', <String, dynamic>{
        'threadId': 'thr_1',
        'turnId': 'turn_1',
        'tokenUsage': <String, dynamic>{
          'modelContextWindow': 128000,
          'total': <String, dynamic>{
            'cachedInputTokens': 0,
            'inputTokens': 1000,
            'outputTokens': 2000,
            'reasoningOutputTokens': 1000,
            'totalTokens': 32000,
          },
          'last': <String, dynamic>{
            'cachedInputTokens': 0,
            'inputTokens': 1000,
            'outputTokens': 2000,
            'reasoningOutputTokens': 1000,
            'totalTokens': 4000,
          },
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.contextWindowSummary, '3% last/window');
      expect(controller.contextUsagePercent, 3);
      expect(controller.composerMetaRightText, '3% last/window');
    },
  );

  test(
    'token usage uses the latest breakdown instead of cumulative thread totals',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.connect();
      await controller.sendPrompt('first');
      transport.emitNotification('thread/tokenUsage/updated', <String, dynamic>{
        'threadId': 'thr_1',
        'turnId': 'turn_1',
        'tokenUsage': <String, dynamic>{
          'modelContextWindow': 128000,
          'total': <String, dynamic>{
            'cachedInputTokens': 0,
            'inputTokens': 30000,
            'outputTokens': 30000,
            'reasoningOutputTokens': 30000,
            'totalTokens': 200000,
          },
          'last': <String, dynamic>{
            'cachedInputTokens': 0,
            'inputTokens': 1000,
            'outputTokens': 1000,
            'reasoningOutputTokens': 1000,
            'totalTokens': 3000,
          },
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.contextWindowSummary, '2% last/window');
      expect(controller.contextUsagePercent, 2);
    },
  );

  test(
    'automation watches file changes, downloads the file, and opens APKs',
    () async {
      final transport = _FakeTransport();
      final openedPaths = <String>[];
      final tempDir = await Directory.systemTemp.createTemp(
        'automation-download',
      );
      final controller = AppController.testing(
        transport: transport,
        httpClientFactory: () => _FakeHttpClient(_FakeTransport._downloadBody),
        openPath: (String path) async {
          openedPaths.add(path);
          return true;
        },
      );
      controller.activeThreadId = 'thr_1';
      await controller.saveSettings(
        controller.settings.copyWith(
          threadDownloadDirectories: <String, String>{'thr_1': tempDir.path},
        ),
      );

      await controller.connect();
      await controller.saveAutomation(
        AutomationDefinition(
          id: 'automation_1',
          name: 'Install APK',
          enabled: true,
          nodes: const <AutomationNode>[
            AutomationNode(
              id: 'trigger_1',
              kind: AutomationNodeKind.watchFileChanged,
              path: '/thread-cwd/app-release.apk',
            ),
            AutomationNode(
              id: 'action_1',
              kind: AutomationNodeKind.downloadChangedFile,
            ),
            AutomationNode(
              id: 'action_2',
              kind: AutomationNodeKind.installDownloadedApk,
              path: '{{previous.downloadedPath}}',
            ),
          ],
        ),
      );

      expect(
        transport.watchPathsById.values,
        contains('/thread-cwd/app-release.apk'),
      );

      transport.emitNotification('fs/changed', <String, dynamic>{
        'watchId': 'watch_1',
        'changedPaths': <String>['/thread-cwd/app-release.apk'],
      });
      for (var attempt = 0; attempt < 20 && openedPaths.isEmpty; attempt += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(openedPaths, hasLength(1));
      expect(openedPaths.single.endsWith('.apk'), isTrue);
      expect(
        File(
          '${tempDir.path}${Platform.pathSeparator}app-release.apk',
        ).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'directory change automation runs the configured command in the watched folder',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.connect();
      await controller.saveAutomation(
        const AutomationDefinition(
          id: 'automation_2',
          name: 'Build APK',
          enabled: true,
          nodes: <AutomationNode>[
            AutomationNode(
              id: 'trigger_1',
              kind: AutomationNodeKind.watchDirectoryChanged,
              path: '/thread-cwd',
            ),
            AutomationNode(
              id: 'action_1',
              kind: AutomationNodeKind.runCommand,
              commandText: 'flutter build apk --release',
            ),
          ],
        ),
      );

      transport.emitNotification('fs/changed', <String, dynamic>{
        'watchId': 'watch_1',
        'changedPaths': <String>['/thread-cwd/lib/main.dart'],
      });
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(transport.lastShellCommand, 'flutter build apk --release');
      expect(transport.lastCommandCwd, '/thread-cwd');
    },
  );

  test('automations sharing a path reuse one backend watch', () async {
    final transport = _FakeTransport()..failOnDuplicateWatchPaths = true;
    final controller = AppController.testing(transport: transport);

    await controller.connect();
    await controller.saveAutomation(
      const AutomationDefinition(
        id: 'automation_shared_1',
        name: 'Build APK',
        enabled: true,
        nodes: <AutomationNode>[
          AutomationNode(
            id: 'trigger_1',
            kind: AutomationNodeKind.watchDirectoryChanged,
            path: '/opt/flutter/packages/flutter_tools/gradle',
          ),
          AutomationNode(
            id: 'action_1',
            kind: AutomationNodeKind.runCommand,
            commandText: 'echo build',
          ),
        ],
      ),
    );
    await controller.saveAutomation(
      const AutomationDefinition(
        id: 'automation_shared_2',
        name: 'Report change',
        enabled: true,
        nodes: <AutomationNode>[
          AutomationNode(
            id: 'trigger_1',
            kind: AutomationNodeKind.watchDirectoryChanged,
            path: '/opt/flutter/packages/flutter_tools/gradle',
          ),
          AutomationNode(
            id: 'action_1',
            kind: AutomationNodeKind.runCommand,
            commandText: 'echo report',
          ),
        ],
      ),
    );

    expect(
      transport.watchPathsById.values.where(
        (path) => path == '/opt/flutter/packages/flutter_tools/gradle',
      ),
      hasLength(1),
    );
  });

  test(
    'turn completed automation runs its command after a completed turn',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.connect();
      await controller.saveAutomation(
        const AutomationDefinition(
          id: 'automation_3',
          name: 'Post-turn command',
          enabled: true,
          nodes: <AutomationNode>[
            AutomationNode(
              id: 'trigger_1',
              kind: AutomationNodeKind.turnCompleted,
            ),
            AutomationNode(
              id: 'action_1',
              kind: AutomationNodeKind.runCommand,
              commandText: 'echo done',
            ),
          ],
        ),
      );

      transport.emitNotification('turn/completed', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn_1',
          'status': 'completed',
          'error': null,
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(transport.lastShellCommand, 'echo done');
    },
  );

  test(
    'turn completed automation can send a message to the active thread',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);
      controller.activeThreadId = 'thr_1';

      await controller.connect();
      await controller.saveAutomation(
        const AutomationDefinition(
          id: 'automation_4',
          name: 'Notify thread',
          enabled: true,
          nodes: <AutomationNode>[
            AutomationNode(
              id: 'trigger_1',
              kind: AutomationNodeKind.turnCompleted,
            ),
            AutomationNode(
              id: 'action_1',
              kind: AutomationNodeKind.sendMessageToCurrentThread,
              commandText: 'Build finished for {{trigger.changedPath}}',
            ),
          ],
        ),
      );

      transport.emitNotification('turn/completed', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn_1',
          'status': 'completed',
          'error': null,
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(transport.lastTurnStartInput, isNotNull);
      expect(
        transport.lastTurnStartInput,
        predicate<List<Map<String, dynamic>>>(
          (items) => items.any(
            (item) =>
                item['type'] == 'text' &&
                item['text'] == 'Build finished for turn_1',
          ),
        ),
      );
    },
  );

  test(
    'did file or folder change and if/else can stop later automation steps',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.connect();
      await controller.saveAutomation(
        const AutomationDefinition(
          id: 'automation_5',
          name: 'Conditional build',
          enabled: true,
          nodes: <AutomationNode>[
            AutomationNode(
              id: 'trigger_1',
              kind: AutomationNodeKind.turnCompleted,
            ),
            AutomationNode(
              id: 'check_1',
              kind: AutomationNodeKind.didPathChangeSinceLastRun,
              path: '/thread-cwd/README.md',
            ),
            AutomationNode(id: 'branch_1', kind: AutomationNodeKind.ifElse),
            AutomationNode(
              id: 'command_1',
              kind: AutomationNodeKind.runCommand,
              commandText: 'echo build',
            ),
          ],
        ),
      );

      transport.emitNotification('turn/completed', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn_1',
          'status': 'completed',
          'error': null,
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(transport.lastShellCommand, 'echo build');

      transport.lastShellCommand = null;
      transport.emitNotification('turn/completed', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn_2',
          'status': 'completed',
          'error': null,
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(transport.lastShellCommand, isNull);
    },
  );

  test(
    'resuming an active thread hydrates live turn items and continues streaming updates',
    () async {
      final transport = _FakeTransport();
      final controller = AppController.testing(transport: transport);

      await controller.resumeThreadFromHistory('thr_active');

      expect(controller.activeThreadId, 'thr_active');
      expect(controller.activeTurnId, 'turn_active');
      final resumedEntry = controller.entries.firstWhere(
        (entry) => entry.key == 'msg_active',
      );
      expect(resumedEntry.body, 'Partial');

      transport.emitNotification('item/agentMessage/delta', <String, dynamic>{
        'threadId': 'thr_active',
        'turnId': 'turn_active',
        'itemId': 'msg_active',
        'delta': ' reply',
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(resumedEntry.body, 'Partial reply');
    },
  );
}

class _FakeTransport implements AppTransport {
  static const String _downloadBody =
      'hello from fs\nsecond line\nthird line\n';
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  final Map<String, Uint8List> _fileBytesByPath = <String, Uint8List>{
    '/thread-cwd/README.md': Uint8List.fromList(
      utf8.encode('hello from fs\nsecond line\nthird line\n'),
    ),
    '/thread-cwd/archive.bin': Uint8List.fromList(<int>[
      0,
      159,
      146,
      150,
      1,
      2,
      3,
    ]),
  };
  final Map<String, int> _modifiedAtByPath = <String, int>{
    '/thread-cwd': 10,
    '/thread-cwd/README.md': 11,
    '/thread-cwd/archive.bin': 12,
    '/thread-cwd/lib': 13,
  };
  bool _connected = false;
  int turnStartCount = 0;
  int turnSteerCount = 0;
  bool failNextSteer = false;
  String? lastCommandCwd;
  String? lastShellCommand;
  List<Map<String, dynamic>>? lastTurnStartInput;
  bool? lastDownloadDisableTimeout;
  bool? lastCommandUsesTty;
  bool? lastCommandStreamsStdin;
  Uri? lastConnectedUri;
  final List<String> unsubscribedThreadIds = <String>[];
  int _watchCounter = 0;
  final Map<String, String> watchPathsById = <String, String>{};
  Completer<void>? delayNextTurnStart;
  int connectCount = 0;
  String? lastBearerToken;
  String? lastThreadStartCwd;
  bool failOnDuplicateWatchPaths = false;
  bool failHomeDirectoryRead = false;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(AppSettings settings) async {
    _connected = true;
    connectCount += 1;
    lastConnectedUri = Uri.parse(
      settings.connectionMode == ConnectionMode.relay
          ? settings.relayUrl
          : settings.serverUrl,
    );
    lastBearerToken = settings.websocketBearerToken.trim();
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<void> send(String payload) async {
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final id = decoded['id'];
    final method = decoded['method'];
    if (method == 'initialize') {
      _respond(id as int, <String, dynamic>{
        'userAgent': 'fake',
        'codexHome': '/tmp',
        'platformFamily': 'unix',
        'platformOs': 'linux',
      });
      return;
    }
    if (method == 'thread/start') {
      final params =
          decoded['params'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      lastThreadStartCwd = params['cwd']?.toString();
      _respond(id as int, <String, dynamic>{
        'thread': <String, dynamic>{
          'id': 'thr_1',
          'cwd': lastThreadStartCwd ?? '/thread-cwd',
          'name': 'Thread One',
        },
      });
      return;
    }
    if (method == 'thread/read') {
      final params = decoded['params'] as Map<String, dynamic>;
      final threadId = params['threadId']?.toString();
      _respond(id as int, <String, dynamic>{
        'thread': <String, dynamic>{
          'id': threadId,
          'cwd': '/thread-cwd',
          'name': threadId == 'thr_active' ? 'Active thread' : 'Thread One',
          'turns': <dynamic>[
            <String, dynamic>{
              'items': <dynamic>[
                <String, dynamic>{
                  'id': 'hist_user',
                  'type': 'userMessage',
                  'content': <dynamic>[
                    <String, dynamic>{'type': 'text', 'text': 'Earlier'},
                  ],
                },
              ],
            },
          ],
        },
      });
      return;
    }
    if (method == 'thread/resume') {
      final params = decoded['params'] as Map<String, dynamic>;
      final threadId = params['threadId']?.toString();
      _respond(id as int, <String, dynamic>{
        'thread': <String, dynamic>{
          'id': threadId,
          'cwd': '/thread-cwd',
          'name': threadId == 'thr_active' ? 'Active thread' : 'Thread One',
        },
        'turn': <String, dynamic>{
          'id': 'turn_active',
          'status': 'inProgress',
          'items': <dynamic>[
            <String, dynamic>{
              'id': 'msg_active',
              'type': 'agentMessage',
              'text': 'Partial',
              'phase': 'final_answer',
            },
          ],
          'error': null,
        },
      });
      return;
    }
    if (method == 'thread/name/set') {
      _respond(id as int, <String, dynamic>{});
      return;
    }
    if (method == 'thread/unsubscribe') {
      final params = decoded['params'] as Map<String, dynamic>;
      final threadId = params['threadId']?.toString();
      if (threadId != null && threadId.isNotEmpty) {
        unsubscribedThreadIds.add(threadId);
      }
      _respond(id as int, <String, dynamic>{'status': 'ok'});
      return;
    }
    if (method == 'turn/start') {
      turnStartCount += 1;
      lastTurnStartInput =
          ((decoded['params'] as Map<String, dynamic>)['input']
                  as List<dynamic>)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
      if (delayNextTurnStart != null) {
        final gate = delayNextTurnStart!;
        delayNextTurnStart = null;
        unawaited(() async {
          await gate.future;
          _respond(id as int, <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn_$turnStartCount',
              'status': 'inProgress',
              'items': <dynamic>[],
              'error': null,
            },
          });
        }());
        return;
      }
      _respond(id as int, <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn_$turnStartCount',
          'status': 'inProgress',
          'items': <dynamic>[],
          'error': null,
        },
      });
      return;
    }
    if (method == 'turn/steer') {
      turnSteerCount += 1;
      if (failNextSteer) {
        failNextSteer = false;
        _error(id as int, 'steer failed');
      } else {
        _respond(id as int, <String, dynamic>{'turnId': 'turn_1'});
      }
      return;
    }
    if (method == 'command/exec') {
      final params = decoded['params'] as Map<String, dynamic>;
      final command = (params['command'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList();
      lastCommandCwd = params['cwd']?.toString();
      if (command.length >= 3 &&
          command.first == '/bin/bash' &&
          command[1] == '-lc') {
        lastShellCommand = command[2];
      }
      lastCommandUsesTty = params['tty'] == true;
      lastCommandStreamsStdin = params['streamStdin'] == true;
      if (command.length >= 3 &&
          command.first == '/bin/bash' &&
          command[2] == r'wc -c < "$1"') {
        final byteCount = utf8.encode(_downloadBody).length;
        _respond(id as int, <String, dynamic>{
          'exitCode': 0,
          'stdout': '$byteCount\n',
          'stderr': '',
        });
        return;
      }
      if (command.length >= 5 &&
          command.first == '/usr/bin/env' &&
          command[1] == 'python3' &&
          command[2] == '-c') {
        final targetPath = command[4];
        if (targetPath == '/home/ege') {
          _respond(id as int, <String, dynamic>{
            'exitCode': 0,
            'stdout': jsonEncode(<String, dynamic>{
              'entries': <Map<String, dynamic>>[
                <String, dynamic>{
                  'fileName': 'Documents',
                  'isDirectory': true,
                  'isFile': false,
                },
                <String, dynamic>{
                  'fileName': '.steampath',
                  'isDirectory': false,
                  'isFile': false,
                },
              ],
            }),
            'stderr': '',
          });
          return;
        }
      }
      if (command.length >= 4 &&
          command.first == '/usr/bin/env' &&
          command[1] == 'python3') {
        lastDownloadDisableTimeout = params['disableTimeout'] == true;
        final processId = params['processId']?.toString() ?? '';
        final token = command.last;
        emitNotification('command/exec/outputDelta', <String, dynamic>{
          'processId': processId,
          'stream': 'stdout',
          'deltaBase64': base64Encode(
            utf8.encode(
              '${jsonEncode(<String, dynamic>{'event': 'ready', 'port': 31337, 'token': token})}\n',
            ),
          ),
          'capReached': false,
        });
        _respond(id as int, <String, dynamic>{
          'processId': processId,
          'exitCode': 0,
          'stdout': '',
          'stderr': '',
        });
        return;
      }
      _respond(id as int, <String, dynamic>{
        'processId': params['processId'],
        'exitCode': 0,
        'stdout': '/thread-cwd\n',
        'stderr': '',
      });
      return;
    }
    if (method == 'command/exec/resize') {
      _respond(id as int, <String, dynamic>{});
      return;
    }
    if (method == 'fs/watch') {
      final params = decoded['params'] as Map<String, dynamic>;
      final path = params['path']?.toString() ?? '';
      if (failOnDuplicateWatchPaths && watchPathsById.values.contains(path)) {
        _error(id as int, 'Already watching path: $path');
        return;
      }
      _watchCounter += 1;
      final watchId = 'watch_$_watchCounter';
      watchPathsById[watchId] = path;
      _respond(id as int, <String, dynamic>{'watchId': watchId, 'path': path});
      return;
    }
    if (method == 'fs/unwatch') {
      final params = decoded['params'] as Map<String, dynamic>;
      watchPathsById.remove(params['watchId']?.toString() ?? '');
      _respond(id as int, <String, dynamic>{});
      return;
    }
    if (method == 'fs/readDirectory') {
      final params = decoded['params'] as Map<String, dynamic>;
      final path = params['path']?.toString();
      if (failHomeDirectoryRead && path == '/home/ege') {
        _error(id as int, 'code -32603');
        return;
      }
      if (path == '/') {
        _respond(id as int, <String, dynamic>{
          'entries': <Map<String, dynamic>>[
            <String, dynamic>{
              'fileName': 'home',
              'isDirectory': true,
              'isFile': false,
            },
            <String, dynamic>{
              'fileName': 'thread-cwd',
              'isDirectory': true,
              'isFile': false,
            },
          ],
        });
      } else if (path == '/home') {
        _respond(id as int, <String, dynamic>{
          'entries': <Map<String, dynamic>>[
            <String, dynamic>{
              'fileName': 'ege',
              'isDirectory': true,
              'isFile': false,
            },
          ],
        });
      } else if (path == '/thread-cwd') {
        _respond(id as int, <String, dynamic>{
          'entries': <Map<String, dynamic>>[
            <String, dynamic>{
              'fileName': 'lib',
              'isDirectory': true,
              'isFile': false,
            },
            <String, dynamic>{
              'fileName': 'README.md',
              'isDirectory': false,
              'isFile': true,
            },
          ],
        });
      } else {
        _respond(id as int, <String, dynamic>{'entries': <dynamic>[]});
      }
      return;
    }
    if (method == 'fs/getMetadata') {
      final params = decoded['params'] as Map<String, dynamic>;
      final path = params['path']?.toString() ?? '';
      final isDirectory = path == '/thread-cwd' || path == '/thread-cwd/lib';
      final isFile = _fileBytesByPath.containsKey(path);
      _respond(id as int, <String, dynamic>{
        'createdAtMs': 1,
        'modifiedAtMs': _modifiedAtByPath[path] ?? 0,
        'isDirectory': isDirectory,
        'isFile': isFile,
      });
      return;
    }
    if (method == 'fs/readFile') {
      final params = decoded['params'] as Map<String, dynamic>;
      final path = params['path']?.toString() ?? '';
      final bytes =
          _fileBytesByPath[path] ??
          Uint8List.fromList(
            utf8.encode('hello from fs\nsecond line\nthird line\n'),
          );
      _respond(id as int, <String, dynamic>{'dataBase64': base64Encode(bytes)});
      return;
    }
    if (method == 'bridge/download/start') {
      final params = decoded['params'] as Map<String, dynamic>;
      final path = params['path']?.toString() ?? '';
      final bytes =
          _fileBytesByPath[path] ??
          Uint8List.fromList(
            utf8.encode('hello from fs\nsecond line\nthird line\n'),
          );
      final fileName = path.split('/').where((part) => part.isNotEmpty).last;
      _respond(id as int, <String, dynamic>{
        'url': 'https://relay.example.com/api/v1/bridge-download/device/token',
        'fileName': fileName,
        'sizeBytes': bytes.length,
      });
      return;
    }
    if (method == 'fs/writeFile') {
      final params = decoded['params'] as Map<String, dynamic>;
      final path = params['path']?.toString() ?? '';
      final dataBase64 = params['dataBase64']?.toString() ?? '';
      _fileBytesByPath[path] = Uint8List.fromList(base64Decode(dataBase64));
      _modifiedAtByPath[path] = (_modifiedAtByPath[path] ?? 0) + 1;
      _respond(id as int, <String, dynamic>{});
      return;
    }
    if (method == 'account/rateLimits/read') {
      _respond(id as int, <String, dynamic>{
        'rateLimits': <String, dynamic>{
          'primary': <String, dynamic>{
            'usedPercent': 23,
            'windowDurationMins': 60,
          },
          'secondary': <String, dynamic>{
            'usedPercent': 58,
            'windowDurationMins': 1440,
          },
        },
      });
      return;
    }
    if (method == 'config/read') {
      _respond(id as int, <String, dynamic>{
        'config': <String, dynamic>{
          'model_context_window': 128000,
          'model_auto_compact_token_limit': 96000,
        },
        'origins': <String, dynamic>{},
      });
      return;
    }
    if (method == 'model/list') {
      _respond(id as int, <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'model_1',
            'model': 'gpt-5.4',
            'displayName': 'GPT-5.4',
            'description': 'Default frontier model',
            'isDefault': true,
            'hidden': false,
            'defaultReasoningEffort': 'medium',
            'supportedReasoningEfforts': <dynamic>[],
          },
          <String, dynamic>{
            'id': 'model_2',
            'model': 'gpt-5.4-mini',
            'displayName': 'GPT-5.4 Mini',
            'description': 'Smaller model',
            'isDefault': false,
            'hidden': false,
            'defaultReasoningEffort': 'medium',
            'supportedReasoningEfforts': <dynamic>[],
          },
        ],
      });
      return;
    }
  }

  void emitNotification(String method, Map<String, dynamic> params) {
    _controller.add(
      jsonEncode(<String, dynamic>{'method': method, 'params': params}),
    );
  }

  void _respond(int id, Map<String, dynamic> result) {
    _controller.add(jsonEncode(<String, dynamic>{'id': id, 'result': result}));
  }

  void _error(int id, String message) {
    _controller.add(
      jsonEncode(<String, dynamic>{
        'id': id,
        'error': <String, dynamic>{'code': -32600, 'message': message},
      }),
    );
  }
}

class _StrictConnectFakeTransport extends _FakeTransport {
  bool sentBeforeConnect = false;

  @override
  Future<void> connect(AppSettings settings) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await super.connect(settings);
  }

  @override
  Future<void> send(String payload) async {
    if (!isConnected) {
      sentBeforeConnect = true;
      throw StateError('send called before connect completed');
    }
    await super.send(payload);
  }
}

class _FakeFilePicker extends FilePicker with MockPlatformInterfaceMixin {
  String? directoryPath;
  String? requestedDirectoryDialogTitle;
  int directoryRequestCount = 0;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
  }) {
    directoryRequestCount += 1;
    requestedDirectoryDialogTitle = dialogTitle;
    return Future<String?>.value(directoryPath);
  }
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(String body) : _bytes = Uint8List.fromList(utf8.encode(body));

  final Uint8List _bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeHttpClientRequest(_bytes);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._bytes);

  final Uint8List _bytes;

  @override
  Future<HttpClientResponse> close() async {
    return _FakeHttpClientResponse(_bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this._bytes);

  final Uint8List _bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
