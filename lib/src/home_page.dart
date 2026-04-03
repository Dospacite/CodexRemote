import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:super_clipboard/super_clipboard.dart';

import 'app_controller.dart';
import 'models.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

Future<void> openDownloadedLocation(
  BuildContext context,
  String savedPath,
) async {
  if (Platform.isAndroid) {
    final currentStatus = await Permission.manageExternalStorage.status;
    if (!currentStatus.isGranted) {
      final requested = await Permission.manageExternalStorage.request();
      if (!requested.isGranted) {
        await openAppSettings();
        if (!context.mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Allow All files access for Codex Remote to open downloaded locations.',
            ),
          ),
        );
        return;
      }
    }
  }
  final parentPath = File(savedPath).parent.path;
  var result = await OpenFilex.open(parentPath);
  if (result.type != ResultType.done) {
    result = await OpenFilex.open(savedPath);
  }
  if (result.type == ResultType.done || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(
        result.message.isNotEmpty
            ? result.message
            : 'Unable to open the downloaded file location.',
      ),
    ),
  );
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  static const int _maxImageAttachmentBytes = 2 * 1024 * 1024;
  static const int _maxImageAttachmentDimension = 1600;
  final TextEditingController _composerController = TextEditingController();
  final List<ComposerAttachment> _composerAttachments = <ComposerAttachment>[];
  final FocusNode _composerFocusNode = FocusNode();
  late final AnimationController _downloadPulseController;
  late final AnimationController _downloadPopController;
  int _previousActiveDownloadCount = 0;
  int _previousDownloadCount = 0;
  bool _showActionBar = true;

  @override
  void initState() {
    super.initState();
    ClipboardEvents.instance?.registerPasteEventListener(_onPasteEvent);
    _downloadPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _downloadPopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    widget.controller.addListener(_handleControllerChanged);
    _previousActiveDownloadCount = widget.controller.activeDownloadCount;
    _previousDownloadCount = widget.controller.downloadRecords.length;
    _syncDownloadAnimations();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    ClipboardEvents.instance?.unregisterPasteEventListener(_onPasteEvent);
    _composerController.dispose();
    _composerFocusNode.dispose();
    _downloadPulseController.dispose();
    _downloadPopController.dispose();
    super.dispose();
  }

  Future<void> _showRateLimitMenu(
    BuildContext context,
    AppController controller,
  ) async {
    if (!controller.hasRateLimitResetDetails) {
      return;
    }
    final box = context.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox) {
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );
    await showMenu<void>(
      context: context,
      position: position,
      items: controller.rateLimitResetDetails
          .map(
            (detail) => PopupMenuItem<void>(
              enabled: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(detail),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final isConnecting =
            controller.status == ConnectionStatus.connecting ||
            controller.status == ConnectionStatus.initializing;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: _TopBarTitle(
              controller: controller,
              onRenameActiveThread: () => _promptRenameActiveThread(context),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: _showActionBar ? 'Hide actions' : 'Show actions',
                onPressed: () {
                  setState(() {
                    _showActionBar = !_showActionBar;
                  });
                },
                icon: Icon(
                  _showActionBar
                      ? Icons.arrow_drop_up_rounded
                      : Icons.arrow_drop_down_rounded,
                  size: 30,
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => _openSettings(context),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          body: Stack(
            children: <Widget>[
              SafeArea(
                top: false,
                child: Column(
                  children: <Widget>[
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 180),
                      crossFadeState: _showActionBar
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: _ActionBar(
                        controller: controller,
                        pulse: _downloadPulseController,
                        pop: _downloadPopController,
                        onOpenThreads: () => _openThreadHistory(context),
                        onOpenFiles: () => _openFiles(context),
                        onOpenCommands: () => _openCommandCenter(context),
                        onOpenAutomations: () => _openAutomations(context),
                        onToggleConnection: () async {
                          if (controller.isConnected) {
                            await controller.disconnect();
                          } else {
                            await controller.connect();
                          }
                        },
                        onOpenDownloads: () => _openDownloadCenter(context),
                      ),
                      secondChild: Container(
                        width: double.infinity,
                        height: 0,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: theme.dividerColor),
                          ),
                        ),
                      ),
                    ),
                    if (controller.approvals.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _ApprovalPanel(controller: controller),
                      ),
                    Expanded(
                      child: controller.entries.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      'Connect to a Codex app-server, then send a prompt. Command output, file changes, approvals, and automations will appear in the same timeline.',
                                      style: theme.textTheme.bodyLarge,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                              itemBuilder: (BuildContext context, int index) {
                                final entry = controller.entries[
                                    controller.entries.length - 1 - index];
                                return _EntryTile(
                                  entry: entry,
                                  onEditMessage: _editTimelineMessage,
                                  onOpenFileReference: _openFileReference,
                                );
                              },
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemCount: controller.entries.length,
                            ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Column(
                        children: <Widget>[
                          if (controller.queuedPromptCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _QueuedPromptBar(
                                controller: controller,
                                onEditPrompt: _editPendingPrompt,
                                onPromotePrompt: widget
                                    .controller
                                    .promotePendingPromptToSteer,
                              ),
                            ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: <Widget>[
                                _FooterIconButton(
                                  tooltip: 'Attach',
                                  icon: Icons.attach_file_outlined,
                                  onPressed: _pickComposerAttachments,
                                ),
                                const SizedBox(width: 8),
                                _FooterActionButton(
                                  label: controller.settings.planMode
                                      ? 'Plan on'
                                      : 'Plan off',
                                  icon: Icons.route_outlined,
                                  onPressed: () => _togglePlanMode(controller),
                                ),
                                const SizedBox(width: 8),
                                _FooterActionButton(
                                  label: _modelLabel(controller),
                                  icon: Icons.tune_outlined,
                                  onPressed: () =>
                                      _editModel(context, controller),
                                ),
                                const SizedBox(width: 8),
                                _FooterActionButton(
                                  label: controller.settings.reasoningEffort,
                                  icon: Icons.psychology_alt_outlined,
                                  onPressed: () => _pickReasoningEffort(
                                    context,
                                    controller,
                                  ),
                                ),
                                if (controller.hasActiveTurn) ...<Widget>[
                                  const SizedBox(width: 8),
                                  _FooterIconButton(
                                    tooltip: 'Stop',
                                    icon: Icons.stop_circle_outlined,
                                    onPressed: controller.interruptTurn,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      const SizedBox(height: 8),
                      if (_composerAttachments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ComposerAttachmentBar(
                            attachments: _composerAttachments,
                            onRemove: _removeComposerAttachment,
                          ),
                        ),
                      TextField(
                        controller: _composerController,
                        focusNode: _composerFocusNode,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message Codex...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (controller.hasActiveTurn) ...<Widget>[
                            OutlinedButton(
                              onPressed: controller.isSteering
                                  ? null
                                  : () => _steerPrompt(controller),
                              child: Text(
                                controller.isSteering ? 'Steering...' : 'Steer',
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                ElevatedButton(
                                  onPressed: () => _sendPrompt(controller),
                                  child: Text(
                                    controller.hasActiveTurn ? 'Queue' : 'Send',
                                  ),
                                ),
                                if (controller.composerMetaLeftText != null ||
                                    controller.composerMetaRightText !=
                                        null) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Builder(
                                          builder: (BuildContext context) {
                                            final text = Text(
                                              controller.composerMetaLeftText ??
                                                  '',
                                              key: const ValueKey<String>(
                                                'composer-meta-left-text',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.left,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    fontSize: 10,
                                                    height: 1.1,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            );
                                            if (!controller
                                                .hasRateLimitResetDetails) {
                                              return text;
                                            }
                                            return InkWell(
                                              key: const ValueKey<String>(
                                                'composer-meta-left-button',
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              onTap: () => _showRateLimitMenu(
                                                context,
                                                controller,
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 2,
                                                    ),
                                                child: text,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      if (controller.composerMetaRightText !=
                                              null &&
                                          controller
                                              .composerMetaRightText!
                                              .isNotEmpty) ...<Widget>[
                                        const SizedBox(width: 8),
                                        if (controller.contextUsagePercent !=
                                            null)
                                          Row(
                                            key: const ValueKey<String>(
                                              'composer-meta-right-indicator',
                                            ),
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(
                                                  value:
                                                      controller
                                                          .contextUsagePercent! /
                                                      100,
                                                  strokeWidth: 2,
                                                  backgroundColor: theme
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(
                                                        theme
                                                            .colorScheme
                                                            .primary,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${controller.contextUsagePercent!.toString().padLeft(2, '0')}%',
                                                key: const ValueKey<String>(
                                                  'composer-meta-right-percent',
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.right,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      fontSize: 10,
                                                      height: 1.1,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          )
                                        else
                                          Text(
                                            controller.composerMetaRightText!,
                                            key: const ValueKey<String>(
                                              'composer-meta-right-text',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.right,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  fontSize: 10,
                                                  height: 1.1,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                    ),
                  ],
                ),
              ),
              if (isConnecting)
                Positioned.fill(
                  child: AbsorbPointer(
                    child: Container(
                      key: const ValueKey<String>('connection-overlay'),
                      color: theme.colorScheme.scrim.withValues(alpha: 0.24),
                      child: const Center(
                        child: CircularProgressIndicator(
                          key: ValueKey<String>('connection-overlay-spinner'),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendPrompt(AppController controller) async {
    if (!(await _ensureThreadDirectorySelected(controller))) {
      return;
    }
    final prompt = _composerController.text;
    final attachments = List<ComposerAttachment>.from(_composerAttachments);
    _composerController.clear();
    setState(() {
      _composerAttachments.clear();
    });
    await controller.sendPrompt(prompt, attachments: attachments);
  }

  Future<bool> _ensureThreadDirectorySelected(AppController controller) async {
    if (!controller.needsThreadDirectorySelection) {
      return true;
    }
    final directory = await _pickThreadDirectory(controller);
    if (directory == null || directory.isEmpty) {
      return false;
    }
    await controller.startFreshThreadInDirectory(directory);
    return true;
  }

  Future<void> _createThreadWithDirectory(AppController controller) async {
    final directory = await _pickThreadDirectory(controller);
    if (directory == null || directory.isEmpty) {
      return;
    }
    await controller.startFreshThreadInDirectory(directory);
  }

  Future<String?> _pickThreadDirectory(AppController controller) async {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationPathPickerPage(
            controller: controller,
            allowDirectorySelection: true,
            allowFileSelection: false,
            title: 'Select thread folder',
            initialPath: controller.preferredFileBrowserRoot,
          );
        },
      ),
    );
  }

  Future<void> _steerPrompt(AppController controller) async {
    final prompt = _composerController.text;
    if (prompt.trim().isEmpty && _composerAttachments.isEmpty) {
      return;
    }
    final attachments = List<ComposerAttachment>.from(_composerAttachments);
    final accepted = await controller.steerPrompt(
      prompt,
      attachments: attachments,
    );
    if (accepted) {
      _composerController.clear();
      setState(() {
        _composerAttachments.clear();
      });
    }
  }

  void _editTimelineMessage(ActivityEntry entry) {
    final content = (entry.body.isEmpty ? entry.title : entry.body).trim();
    if (content.isEmpty) {
      return;
    }
    _composerController
      ..text = content
      ..selection = TextSelection.collapsed(offset: content.length);
  }

  void _dismissComposerFocus() {
    _composerFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _openFileReference(String path, {int? line}) async {
    final resolvedPath = widget.controller.resolveFileReferencePath(path);
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return;
    }
    _dismissComposerFocus();
    await widget.controller.openFile(resolvedPath, highlightedLine: line);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return FilePreviewPage(
            controller: widget.controller,
            onDownload: _downloadPreviewFile,
            onCancelDownload: _cancelPreviewDownload,
          );
        },
      ),
    );
  }

  Future<void> _downloadPreviewFile(
    BuildContext context,
    String filePath,
  ) async {
    try {
      await widget.controller.saveFileToDevice(filePath);
    } catch (error) {
      // Download errors are surfaced in the download center.
    }
  }

  Future<void> _cancelPreviewDownload(String filePath) async {
    await widget.controller.cancelFileDownload(filePath);
  }

  Future<void> _promptRenameActiveThread(BuildContext context) async {
    final threadId = widget.controller.activeThreadId?.trim() ?? '';
    if (threadId.isEmpty) {
      return;
    }
    _dismissComposerFocus();
    final textController = TextEditingController(
      text: widget.controller.activeThreadName?.trim() ?? '',
    );
    final nextName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rename thread'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Thread name'),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(textController.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (nextName == null) {
      return;
    }
    await widget.controller.renameThread(threadId, nextName);
  }

  Future<void> _openDownloadCenter(BuildContext context) async {
    _dismissComposerFocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return DownloadCenterPage(controller: widget.controller);
        },
      ),
    );
  }

  void _handleControllerChanged() {
    final activeCount = widget.controller.activeDownloadCount;
    final totalCount = widget.controller.downloadRecords.length;
    if (activeCount != _previousActiveDownloadCount ||
        totalCount != _previousDownloadCount) {
      _downloadPopController.forward(from: 0);
      _previousActiveDownloadCount = activeCount;
      _previousDownloadCount = totalCount;
      _syncDownloadAnimations();
    }
  }

  void _syncDownloadAnimations() {
    if (widget.controller.activeDownloadCount > 0) {
      if (!_downloadPulseController.isAnimating) {
        _downloadPulseController.repeat(reverse: true);
      }
    } else {
      _downloadPulseController.stop();
      _downloadPulseController.value = 0;
    }
  }

  void _editPendingPrompt(String pendingId) {
    final value = widget.controller.takePendingPromptForEditing(pendingId);
    if (value == null) {
      return;
    }
    _composerController.text = value.text;
    _composerController.selection = TextSelection.collapsed(
      offset: value.text.length,
    );
    setState(() {
      _composerAttachments
        ..clear()
        ..addAll(value.attachments);
    });
  }

  Future<void> _pickComposerAttachments() async {
    _dismissComposerFocus();
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) {
      return;
    }
    final nextAttachments = <ComposerAttachment>[];
    final rejected = <String>[];
    for (final file in result.files) {
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      final name = file.name.trim();
      if (bytes == null || name.isEmpty) {
        continue;
      }
      final attachment = await _attachmentFromBytes(
        fileName: name,
        bytes: bytes,
        mimeType: file.extension == null ? null : _mimeTypeForFileName(name),
      );
      if (attachment == null) {
        rejected.add(name);
      } else {
        nextAttachments.add(attachment);
      }
    }
    if (nextAttachments.isNotEmpty) {
      setState(() {
        _composerAttachments.addAll(nextAttachments);
      });
    }
    if (rejected.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unsupported attachments: ${rejected.join(', ')}'),
        ),
      );
    }
  }

  Future<void> _onPasteEvent(ClipboardReadEvent event) async {
    final reader = await event.getClipboardReader();
    await _handleClipboardReader(reader);
  }

  Future<void> _handleClipboardReader(ClipboardReader reader) async {
    final attachment = await _readImageAttachmentFromClipboard(reader);
    if (!mounted || attachment == null) {
      return;
    }
    setState(() {
      _composerAttachments.add(attachment);
    });
  }

  Future<ComposerAttachment?> _readImageAttachmentFromClipboard(
    ClipboardReader reader,
  ) async {
    for (final item in reader.items) {
      final png = await _readClipboardFile(item, Formats.png);
      if (png != null) {
        return _imageAttachment(
          fileName: await item.getSuggestedName() ?? 'Pasted Image.png',
          bytes: png,
          mimeType: 'image/png',
        );
      }
      final jpeg = await _readClipboardFile(item, Formats.jpeg);
      if (jpeg != null) {
        return _imageAttachment(
          fileName: await item.getSuggestedName() ?? 'Pasted Image.jpg',
          bytes: jpeg,
          mimeType: 'image/jpeg',
        );
      }
      final gif = await _readClipboardFile(item, Formats.gif);
      if (gif != null) {
        return _imageAttachment(
          fileName: await item.getSuggestedName() ?? 'Pasted Image.gif',
          bytes: gif,
          mimeType: 'image/gif',
        );
      }
      final webp = await _readClipboardFile(item, Formats.webp);
      if (webp != null) {
        return _imageAttachment(
          fileName: await item.getSuggestedName() ?? 'Pasted Image.webp',
          bytes: webp,
          mimeType: 'image/webp',
        );
      }
    }
    return null;
  }

  Future<Uint8List?> _readClipboardFile(
    DataReader reader,
    FileFormat format,
  ) async {
    final completer = Completer<Uint8List?>();
    final progress = reader.getFile(
      format,
      (DataReaderFile file) async {
        try {
          completer.complete(await file.readAll());
        } catch (error) {
          completer.completeError(error);
        }
      },
      onError: (Object error) {
        completer.completeError(error);
      },
    );
    if (progress == null) {
      return null;
    }
    return completer.future;
  }

  Future<ComposerAttachment?> _attachmentFromBytes({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    if (_isImageFile(fileName, mimeType)) {
      return _imageAttachment(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType ?? _mimeTypeForFileName(fileName) ?? 'image/png',
      );
    }
    if (!isLikelyHumanReadableFile(fileName, bytes)) {
      return null;
    }
    return ComposerAttachment(
      id: 'attachment-${DateTime.now().microsecondsSinceEpoch}-$fileName',
      fileName: fileName,
      kind: ComposerAttachmentKind.textFile,
      bytes: bytes,
      mimeType: mimeType,
      textContent: String.fromCharCodes(bytes),
    );
  }

  Future<ComposerAttachment> _imageAttachment({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final prepared = _prepareImageAttachment(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
    return ComposerAttachment(
      id: 'attachment-${DateTime.now().microsecondsSinceEpoch}-${prepared.fileName}',
      fileName: prepared.fileName,
      kind: ComposerAttachmentKind.image,
      bytes: prepared.bytes,
      mimeType: prepared.mimeType,
    );
  }

  _PreparedImageAttachment _prepareImageAttachment({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return _PreparedImageAttachment(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
    }
    final longestSide = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final shouldResize = longestSide > _maxImageAttachmentDimension;
    final shouldReencode =
        shouldResize ||
        bytes.length > _maxImageAttachmentBytes ||
        mimeType == 'image/heic' ||
        mimeType == 'image/heif' ||
        mimeType == 'image/bmp' ||
        mimeType == 'image/gif' ||
        mimeType == 'image/webp';
    if (!shouldReencode) {
      return _PreparedImageAttachment(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
    }

    img.Image output = decoded;
    if (shouldResize) {
      if (decoded.width >= decoded.height) {
        output = img.copyResize(decoded, width: _maxImageAttachmentDimension);
      } else {
        output = img.copyResize(decoded, height: _maxImageAttachmentDimension);
      }
    }

    var quality = 88;
    var encoded = Uint8List.fromList(img.encodeJpg(output, quality: quality));
    while (encoded.length > _maxImageAttachmentBytes && quality > 52) {
      quality -= 12;
      encoded = Uint8List.fromList(img.encodeJpg(output, quality: quality));
    }
    return _PreparedImageAttachment(
      fileName: _replaceFileExtension(fileName, 'jpg'),
      bytes: encoded,
      mimeType: 'image/jpeg',
    );
  }

  String _replaceFileExtension(String fileName, String extension) {
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
    return '$baseName.$extension';
  }

  bool _isImageFile(String fileName, String? mimeType) {
    final type = (mimeType ?? '').toLowerCase();
    if (type.startsWith('image/')) {
      return true;
    }
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    return <String>{
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'heic',
      'heif',
    }.contains(extension);
  }

  String? _mimeTypeForFileName(String fileName) {
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => null,
    };
  }

  void _removeComposerAttachment(String id) {
    setState(() {
      _composerAttachments.removeWhere((item) => item.id == id);
    });
  }

  Future<void> _openSettings(BuildContext context) async {
    _dismissComposerFocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return SettingsPage(controller: widget.controller);
        },
      ),
    );
  }

  Future<void> _openAutomations(BuildContext context) async {
    _dismissComposerFocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationPage(controller: widget.controller);
        },
      ),
    );
  }

  Future<void> _openThreadHistory(BuildContext context) async {
    _dismissComposerFocus();
    await widget.controller.loadThreadHistory(reset: true);
    if (!context.mounted) {
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Threads',
      barrierDismissible: true,
      barrierColor: Colors.black54,
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.88,
                  child: ThreadHistorySheet(
                    controller: widget.controller,
                    onCreateThread: () =>
                        _createThreadWithDirectory(widget.controller),
                  ),
                ),
              ),
            );
          },
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
    );
  }

  Future<void> _openFiles(BuildContext context) async {
    _dismissComposerFocus();
    await widget.controller.openFileBrowser();
    if (!context.mounted) {
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Files',
      barrierDismissible: true,
      barrierColor: Colors.black54,
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.92,
                  child: FileBrowserSheet(controller: widget.controller),
                ),
              ),
            );
          },
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
    );
  }

  Future<void> _openCommandCenter(BuildContext context) async {
    _dismissComposerFocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return CommandCenterPage(controller: widget.controller);
        },
      ),
    );
  }

  Future<void> _pickReasoningEffort(
    BuildContext context,
    AppController controller,
  ) async {
    _dismissComposerFocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          top: false,
          child: Wrap(
            children: <String>['low', 'medium', 'high', 'xhigh']
                .map(
                  (item) => ListTile(
                    title: Text(item),
                    onTap: () => Navigator.of(context).pop(item),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
    if (selected == null) {
      return;
    }
    await controller.saveSettings(
      controller.settings.copyWith(reasoningEffort: selected),
    );
  }

  Future<void> _editModel(
    BuildContext context,
    AppController controller,
  ) async {
    _dismissComposerFocus();
    await controller.loadModelOptions(force: true);
    if (!context.mounted) {
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: controller,
            builder: (BuildContext context, Widget? child) {
              final theme = Theme.of(context);
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Model', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    if (controller.modelListError != null)
                      Text(
                        controller.modelListError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    if (controller.isLoadingModels)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: <Widget>[
                            ListTile(
                              title: const Text('Default model'),
                              subtitle: const Text(
                                'Use the server default selection',
                              ),
                              selected: controller.settings.model
                                  .trim()
                                  .isEmpty,
                              onTap: () => Navigator.of(context).pop(''),
                            ),
                            ...controller.modelOptions.map((option) {
                              final value = option.model.trim();
                              return ListTile(
                                title: Text(
                                  option.displayName.isEmpty
                                      ? value
                                      : option.displayName,
                                ),
                                subtitle: option.description.isEmpty
                                    ? null
                                    : Text(option.description),
                                selected:
                                    value.isNotEmpty &&
                                    controller.settings.model.trim() == value,
                                trailing: option.isDefault
                                    ? const Text('Default')
                                    : null,
                                onTap: () => Navigator.of(context).pop(value),
                              );
                            }),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (selected == null) {
      return;
    }
    await controller.saveSettings(
      controller.settings.copyWith(model: selected),
    );
  }

  Future<void> _togglePlanMode(AppController controller) async {
    await controller.saveSettings(
      controller.settings.copyWith(planMode: !controller.settings.planMode),
    );
  }

  String _modelLabel(AppController controller) {
    final model = controller.settings.model.trim();
    if (model.isNotEmpty) {
      return model;
    }
    final defaultOption = controller.modelOptions
        .cast<ModelOption?>()
        .firstWhere((option) => option?.isDefault == true, orElse: () => null);
    if (defaultOption == null) {
      return 'Server default';
    }
    final displayName = defaultOption.displayName.trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final defaultModel = defaultOption.model.trim();
    return defaultModel.isEmpty ? 'Server default' : defaultModel;
  }
}

class _PreparedImageAttachment {
  const _PreparedImageAttachment({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
}

class _TopBarTitle extends StatelessWidget {
  const _TopBarTitle({
    required this.controller,
    required this.onRenameActiveThread,
  });

  final AppController controller;
  final VoidCallback onRenameActiveThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: controller.activeThreadId != null ? onRenameActiveThread : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _titleText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              _subtitleText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _titleText() {
    final activeName = controller.activeThreadName?.trim() ?? '';
    if (activeName.isNotEmpty) {
      return activeName;
    }
    return 'Codex Remote';
  }

  String _subtitleText() {
    if (controller.activeThreadCwd.trim().isNotEmpty) {
      return controller.activeThreadCwd.trim();
    }
    if (controller.settings.connectionMode == ConnectionMode.relay) {
      final bridgeLabel = controller.settings.relayBridgeLabel.trim();
      if (bridgeLabel.isNotEmpty) {
        return bridgeLabel;
      }
      if (controller.settings.relayUrl.trim().isNotEmpty) {
        return controller.settings.relayUrl.trim();
      }
    }
    return controller.settings.serverUrl;
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.controller,
    required this.pulse,
    required this.pop,
    required this.onOpenThreads,
    required this.onOpenFiles,
    required this.onOpenCommands,
    required this.onOpenAutomations,
    required this.onToggleConnection,
    required this.onOpenDownloads,
  });

  final AppController controller;
  final Animation<double> pulse;
  final Animation<double> pop;
  final VoidCallback onOpenThreads;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenCommands;
  final VoidCallback onOpenAutomations;
  final VoidCallback onToggleConnection;
  final VoidCallback onOpenDownloads;

  Widget _animatedActionIcon({required Widget icon, required bool animate}) {
    if (!animate) {
      return icon;
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        final scale = 1 + (pulse.value * 0.05);
        return Transform.scale(scale: scale, child: child);
      },
      child: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCount = controller.activeDownloadCount;
    final totalDownloads = controller.downloadRecords.length;
    final hasRunningAutomation = controller.automations.any(
      (item) => controller.isAutomationRunning(item.id),
    );
    final buttonStyle = IconButton.styleFrom(
      visualDensity: const VisualDensity(horizontal: -0.5, vertical: -0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      minimumSize: const Size(56, 50),
      tapTargetSize: MaterialTapTargetSize.padded,
      alignment: Alignment.centerLeft,
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            IconButton(
              tooltip: 'Threads',
              style: buttonStyle,
              onPressed: controller.isLoadingHistory ? null : onOpenThreads,
              iconSize: 26,
              icon: controller.isLoadingHistory
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.menu, size: 26),
            ),
            IconButton(
              tooltip: controller.isConnected ? 'Disconnect' : 'Connect',
              style: buttonStyle,
              onPressed: onToggleConnection,
              iconSize: 26,
              icon: Icon(
                controller.isConnected ? Icons.link_off : Icons.link,
                size: 26,
              ),
            ),
            IconButton(
              tooltip: 'Command',
              style: buttonStyle,
              onPressed: onOpenCommands,
              iconSize: 26,
              icon: const Icon(Icons.terminal, size: 26),
            ),
            IconButton(
              tooltip: 'Files',
              style: buttonStyle,
              onPressed: onOpenFiles,
              iconSize: 26,
              icon: const Icon(Icons.folder_outlined, size: 26),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                IconButton(
                  tooltip: 'Automations',
                  style: buttonStyle,
                  onPressed: onOpenAutomations,
                  iconSize: 26,
                  icon: _animatedActionIcon(
                    animate: hasRunningAutomation,
                    icon: const Icon(Icons.account_tree_outlined, size: 26),
                  ),
                ),
                if (hasRunningAutomation)
                  Positioned(
                    top: 6,
                    right: 8,
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        key: const ValueKey<String>(
                          'automation-running-indicator',
                        ),
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                IconButton(
                  tooltip: 'Downloads',
                  style: buttonStyle,
                  onPressed: onOpenDownloads,
                  iconSize: 26,
                  icon: _animatedActionIcon(
                    animate: activeCount > 0,
                    icon: Icon(
                      activeCount > 0
                          ? Icons.downloading_rounded
                          : Icons.download_outlined,
                      size: 26,
                    ),
                  ),
                ),
                if (totalDownloads > 0)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: SizedBox(
                      width: 22,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: activeCount > 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            activeCount > 0
                                ? '$activeCount'
                                : '$totalDownloads',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: activeCount > 0
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterActionButton extends StatelessWidget {
  const _FooterActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: theme.colorScheme.onSurface),
          const SizedBox(width: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterIconButton extends StatelessWidget {
  const _FooterIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
      ),
    );
  }
}

class _ApprovalPanel extends StatelessWidget {
  const _ApprovalPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.primary),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: controller.approvals.map((approval) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(approval.title, style: theme.textTheme.titleMedium),
                if (approval.detail.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  SelectableText(
                    approval.detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: approval.availableDecisions.map((decision) {
                    final button =
                        decision == 'accept' || decision == 'acceptForSession'
                        ? ElevatedButton(
                            onPressed: () =>
                                controller.resolveApproval(approval, decision),
                            child: Text(_decisionLabel(decision)),
                          )
                        : OutlinedButton(
                            onPressed: () =>
                                controller.resolveApproval(approval, decision),
                            child: Text(_decisionLabel(decision)),
                          );
                    return button;
                  }).toList(),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _decisionLabel(String decision) {
    return switch (decision) {
      'acceptForSession' => 'Accept for session',
      _ => decision[0].toUpperCase() + decision.substring(1),
    };
  }
}

class _QueuedPromptBar extends StatelessWidget {
  const _QueuedPromptBar({
    required this.controller,
    required this.onEditPrompt,
    required this.onPromotePrompt,
  });

  final AppController controller;
  final ValueChanged<String> onEditPrompt;
  final ValueChanged<String> onPromotePrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: controller.pendingPrompts.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: <Widget>[
                Icon(
                  item.mode == PendingPromptMode.steer
                      ? Icons.settings_outlined
                      : Icons.schedule_send_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pendingPromptLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (item.mode != PendingPromptMode.steer)
                  IconButton(
                    key: ValueKey<String>('pending-prompt-promote-${item.id}'),
                    tooltip: 'Steer',
                    onPressed: () => onPromotePrompt(item.id),
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    splashRadius: 16,
                    icon: const Icon(Icons.settings_outlined, size: 16),
                  ),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => onEditPrompt(item.id),
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  splashRadius: 16,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => controller.cancelPendingPrompt(item.id),
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  splashRadius: 16,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _pendingPromptLabel(PendingPrompt item) {
    final trimmed = item.text.trim();
    final attachmentCount = item.attachments.length;
    if (trimmed.isNotEmpty && attachmentCount == 0) {
      return trimmed;
    }
    if (trimmed.isEmpty && attachmentCount > 0) {
      return attachmentCount == 1
          ? '1 attachment'
          : '$attachmentCount attachments';
    }
    if (attachmentCount > 0) {
      return '$trimmed • ${attachmentCount == 1 ? '1 attachment' : '$attachmentCount attachments'}';
    }
    return 'Pending message';
  }
}

class _ComposerAttachmentBar extends StatelessWidget {
  const _ComposerAttachmentBar({
    required this.attachments,
    required this.onRemove,
  });

  final List<ComposerAttachment> attachments;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: attachments.map((item) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    item.isImage
                        ? Icons.image_outlined
                        : Icons.description_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      item.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Remove attachment',
                    onPressed: () => onRemove(item.id),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MonospaceOutputView extends StatelessWidget {
  const _MonospaceOutputView({
    required this.text,
    required this.style,
    this.scrollable = true,
  });

  final String text;
  final TextStyle? style;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final displayText = _repairDisplayText(text);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final lineLengths = displayText.split('\n').map((line) => line.length);
        final longestLineLength = lineLengths.isEmpty
            ? 0
            : lineLengths.reduce((left, right) => left > right ? left : right);
        final fontSize = style?.fontSize ?? 12;
        final estimatedCharWidth = fontSize * 0.62;
        final contentWidth = (longestLineLength * estimatedCharWidth) + 24;
        final targetWidth =
            constraints.hasBoundedWidth && contentWidth < constraints.maxWidth
            ? constraints.maxWidth
            : contentWidth;
        final content = SizedBox(
          width: targetWidth,
          child: SelectionArea(
            child: Text(
              displayText,
              overflow: TextOverflow.visible,
              softWrap: false,
              textWidthBasis: TextWidthBasis.longestLine,
              strutStyle: const StrutStyle(forceStrutHeight: true, height: 1.2),
              style: style,
            ),
          ),
        );
        if (!scrollable) {
          return content;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(child: content),
        );
      },
    );
  }

  String _repairDisplayText(String value) {
    final lines = value.split('\n');
    if (lines.length < 8) {
      return value;
    }

    final repaired = <String>[];
    final run = <String>[];

    void flushRun() {
      if (run.isEmpty) {
        return;
      }
      final nonEmpty = run.where((line) => line.isNotEmpty).toList();
      final mostlySingleChar =
          nonEmpty.length >= 6 &&
          nonEmpty.every((line) {
            final trimmed = line.trim();
            return line.runes.length == 1 || trimmed.runes.length == 1;
          });
      if (mostlySingleChar) {
        final joined = run.join();
        if (repaired.isNotEmpty && joined.startsWith(RegExp(r'\s'))) {
          repaired[repaired.length - 1] = '${repaired.last}$joined';
        } else {
          repaired.add(joined);
        }
      } else {
        repaired.addAll(run);
      }
      run.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      final isRepairableSingleChar =
          line.isEmpty || line.runes.length == 1 || trimmed.runes.length == 1;
      if (isRepairableSingleChar) {
        run.add(line);
      } else {
        flushRun();
        repaired.add(line);
      }
    }
    flushRun();

    return repaired.join('\n');
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onEditMessage,
    required this.onOpenFileReference,
  });

  final ActivityEntry entry;
  final ValueChanged<ActivityEntry> onEditMessage;
  final Future<void> Function(String path, {int? line}) onOpenFileReference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUserMessage = entry.kind == EntryKind.user;
    final isAgentMessage = entry.kind == EntryKind.agent;
    final isSystemMessage = entry.kind == EntryKind.system;
    final isPendingUserMessage = isUserMessage && entry.isLocalPending;
    final normalizedMessageText =
        (entry.body.isEmpty ? entry.title : entry.body).trim();
    final isContextCompacting =
        isSystemMessage &&
        normalizedMessageText.toLowerCase().contains('context compact');
    final isCard =
        entry.kind == EntryKind.command ||
        entry.kind == EntryKind.fileChange ||
        entry.kind == EntryKind.tool;
    final systemBorderColor = Color.alphaBlend(
      const Color(0xFFFFA24C).withValues(alpha: 0.7),
      scheme.outlineVariant,
    );
    final systemTextColor = Color.alphaBlend(
      const Color(0xFFFFC48A).withValues(alpha: 0.9),
      scheme.onSurfaceVariant,
    );
    final tone = switch (entry.kind) {
      EntryKind.user => scheme.primary.withValues(alpha: 0.16),
      EntryKind.agent => theme.colorScheme.surface,
      EntryKind.reasoning => Colors.transparent,
      EntryKind.command => scheme.surface,
      EntryKind.fileChange => scheme.surface,
      EntryKind.tool => scheme.surface,
      EntryKind.system => const Color(0xFFFFA24C).withValues(alpha: 0.04),
    };
    final pendingUserBorderColor = scheme.outlineVariant.withValues(alpha: 0.8);
    final pendingUserTextColor = scheme.onSurfaceVariant.withValues(
      alpha: 0.58,
    );

    final monospace =
        entry.kind == EntryKind.command ||
        entry.kind == EntryKind.fileChange ||
        entry.title.contains('MCP') ||
        entry.body.contains('{') ||
        entry.body.contains('diff');
    final messageText = normalizedMessageText;
    final canEditMessage =
        entry.kind == EntryKind.user && messageText.trim().isNotEmpty;
    final cardTitle = entry.kind == EntryKind.fileChange
        ? _summarizeFileChangeTitle(entry.body, fallback: entry.title)
        : entry.title;

    if (isContextCompacting) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Divider(
                color: theme.dividerColor,
                thickness: 1,
                height: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Context Compacting',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: systemTextColor,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: theme.dividerColor,
                thickness: 1,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }

    Widget? bodyContent;
    if (isCard && entry.body.isNotEmpty) {
      if (entry.kind == EntryKind.fileChange) {
        bodyContent = _ExpandableEntryBody(
          text: entry.body,
          previewText: _collapsedPreviewText(entry.body),
          child: _GitDiffView(text: entry.body),
        );
      } else if (monospace) {
        bodyContent = _MonospaceOutputView(
          text: entry.body,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            height: 1.2,
          ),
        );
      } else {
        bodyContent = SelectableText(
          entry.body,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        );
      }

      if (entry.kind == EntryKind.tool || entry.kind == EntryKind.command) {
        bodyContent = _ExpandableEntryBody(
          text: entry.body,
          previewText: _collapsedPreviewText(entry.body),
          child: bodyContent,
        );
      }
    }

    final bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (isCard)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(cardTitle, style: theme.textTheme.titleMedium),
              ),
              if (entry.status.isNotEmpty)
                Text(entry.status, style: theme.textTheme.bodySmall),
            ],
          )
        else
          isAgentMessage
              ? _AgentMarkdownMessage(
                  text: messageText,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSurface,
                  ),
                  onOpenFileReference: onOpenFileReference,
                )
              : _MessageContentText(
                  text: messageText,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    color: isSystemMessage
                        ? systemTextColor
                        : isPendingUserMessage
                        ? pendingUserTextColor
                        : theme.colorScheme.onSurface,
                    fontWeight: isSystemMessage ? FontWeight.w300 : null,
                  ),
                  canEdit: canEditMessage,
                  onEdit: () => onEditMessage(entry),
                  onOpenFileReference: onOpenFileReference,
                ),
        if (entry.secondary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(entry.secondary, style: theme.textTheme.bodySmall),
        ],
        if (bodyContent != null) ...<Widget>[
          const SizedBox(height: 10),
          bodyContent,
        ],
        if (entry.isStreaming) ...<Widget>[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      alignment: isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isUserMessage || isAgentMessage
              ? MediaQuery.sizeOf(context).width * 0.84
              : double.infinity,
        ),
        padding: EdgeInsets.all(
          isCard || isUserMessage || isAgentMessage || isSystemMessage ? 14 : 0,
        ),
        decoration: BoxDecoration(
          color: isPendingUserMessage ? Colors.transparent : tone,
          border: isPendingUserMessage
              ? Border.all(color: pendingUserBorderColor, width: 0.9)
              : isSystemMessage
              ? Border.all(color: systemBorderColor, width: 1)
              : isCard || isAgentMessage
              ? Border.all(color: theme.dividerColor)
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: isPendingUserMessage ? Clip.antiAlias : Clip.none,
        child: isPendingUserMessage
            ? Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _PendingMessageSheen(
                      color: scheme.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  bubbleContent,
                ],
              )
            : bubbleContent,
      ),
    );
  }
}

class _PendingMessageSheen extends StatefulWidget {
  const _PendingMessageSheen({required this.color});

  final Color color;

  @override
  State<_PendingMessageSheen> createState() => _PendingMessageSheenState();
}

class _PendingMessageSheenState extends State<_PendingMessageSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: const ValueKey<String>('pending-message-sheen'),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final slide = Tween<double>(
            begin: -1.2,
            end: 1.2,
          ).transform(Curves.easeInOut.transform(_controller.value));
          return FractionalTranslation(
            translation: Offset(slide, 0),
            child: child,
          );
        },
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    Colors.transparent,
                    widget.color,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageContentText extends StatelessWidget {
  const _MessageContentText({
    required this.text,
    required this.style,
    required this.canEdit,
    required this.onEdit,
    required this.onOpenFileReference,
  });

  final String text;
  final TextStyle? style;
  final bool canEdit;
  final VoidCallback onEdit;
  final Future<void> Function(String path, {int? line}) onOpenFileReference;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      _buildSpans(context),
      contextMenuBuilder:
          (BuildContext context, EditableTextState editableTextState) {
            final items = <ContextMenuButtonItem>[
              ...editableTextState.contextMenuButtonItems,
              if (canEdit)
                ContextMenuButtonItem(
                  label: 'Edit',
                  onPressed: () {
                    ContextMenuController.removeAny();
                    onEdit();
                  },
                ),
            ];
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: items,
            );
          },
      style: style,
    );
  }

  TextSpan _buildSpans(BuildContext context) {
    final matches = <_MessageReferenceMatch>[
      ..._matchMarkdownReferences(text),
      ..._matchPlainReferences(text),
    ]..sort((left, right) => left.start.compareTo(right.start));

    final filteredMatches = <_MessageReferenceMatch>[];
    var lastEnd = 0;
    for (final match in matches) {
      if (match.start < lastEnd) {
        continue;
      }
      filteredMatches.add(match);
      lastEnd = match.end;
    }

    if (filteredMatches.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in filteredMatches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              unawaited(onOpenFileReference(match.path, line: match.line));
            },
            child: Text(match.displayText, style: linkStyle),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: style, children: spans);
  }
}

class _AgentMarkdownMessage extends StatelessWidget {
  const _AgentMarkdownMessage({
    required this.text,
    required this.style,
    required this.onOpenFileReference,
  });

  final String text;
  final TextStyle? style;
  final Future<void> Function(String path, {int? line}) onOpenFileReference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedStyle = style ?? theme.textTheme.bodyLarge;
    return SelectionArea(
      child: MarkdownBody(
        data: _linkifyPlainFileReferences(text),
        softLineBreak: true,
        onTapLink: (String linkText, String? href, String title) {
          if (href == null || href.isEmpty) {
            return;
          }
          final resolved = _parseReferenceTarget(href);
          if (resolved == null) {
            return;
          }
          unawaited(onOpenFileReference(resolved.path, line: resolved.line));
        },
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: resolvedStyle,
          h1: theme.textTheme.headlineSmall?.copyWith(
            color: resolvedStyle?.color,
            fontWeight: FontWeight.w700,
          ),
          h2: theme.textTheme.titleLarge?.copyWith(
            color: resolvedStyle?.color,
            fontWeight: FontWeight.w700,
          ),
          h3: theme.textTheme.titleMedium?.copyWith(
            color: resolvedStyle?.color,
            fontWeight: FontWeight.w700,
          ),
          code: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurface,
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          a: resolvedStyle?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          blockquotePadding: const EdgeInsets.only(left: 12),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 2),
            ),
          ),
        ),
        builders: <String, MarkdownElementBuilder>{
          'a': _MarkdownFileLinkBuilder(
            onOpenFileReference: onOpenFileReference,
            style: resolvedStyle?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        },
      ),
    );
  }
}

class _MarkdownFileLinkBuilder extends MarkdownElementBuilder {
  _MarkdownFileLinkBuilder({
    required this.onOpenFileReference,
    required this.style,
  });

  final Future<void> Function(String path, {int? line}) onOpenFileReference;
  final TextStyle? style;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'];
    final resolved = href == null ? null : _parseReferenceTarget(href);
    final linkStyle = style ?? preferredStyle ?? parentStyle;
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: resolved == null
              ? null
              : () {
                  unawaited(
                    onOpenFileReference(resolved.path, line: resolved.line),
                  );
                },
          child: Text(element.textContent, style: linkStyle),
        ),
      ),
    );
  }
}

class _MessageReferenceMatch {
  const _MessageReferenceMatch({
    required this.start,
    required this.end,
    required this.displayText,
    required this.path,
    required this.line,
  });

  final int start;
  final int end;
  final String displayText;
  final String path;
  final int? line;
}

class _ResolvedReference {
  const _ResolvedReference({required this.path, required this.line});

  final String path;
  final int? line;
}

Iterable<_MessageReferenceMatch> _matchMarkdownReferences(String input) sync* {
  final pattern = RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)');
  for (final match in pattern.allMatches(input)) {
    final target = match.group(2);
    if (target == null || target.isEmpty) {
      continue;
    }
    final resolved = _parseReferenceTarget(target);
    if (resolved == null) {
      continue;
    }
    yield _MessageReferenceMatch(
      start: match.start,
      end: match.end,
      displayText: match.group(1) ?? target,
      path: resolved.path,
      line: resolved.line,
    );
  }
}

Iterable<_MessageReferenceMatch> _matchPlainReferences(String input) sync* {
  final pattern = RegExp(
    r'(?<![\w/])((?:/|\.{1,2}/)?(?:[A-Za-z0-9._-]+/)+[A-Za-z0-9._-]+)(?::(\d+)|#L(\d+))',
  );
  for (final match in pattern.allMatches(input)) {
    final target = match.group(0);
    final path = match.group(1);
    if (target == null || path == null) {
      continue;
    }
    final line = int.tryParse(match.group(2) ?? match.group(3) ?? '');
    yield _MessageReferenceMatch(
      start: match.start,
      end: match.end,
      displayText: target,
      path: path,
      line: line,
    );
  }
}

_ResolvedReference? _parseReferenceTarget(String target) {
  final hashIndex = target.indexOf('#');
  String path = hashIndex >= 0 ? target.substring(0, hashIndex) : target;
  final hash = hashIndex >= 0 ? target.substring(hashIndex + 1) : '';
  int? line;

  final colonMatch = RegExp(r'^(.*):(\d+)$').firstMatch(path);
  if (colonMatch != null &&
      !path.startsWith('ws://') &&
      !path.startsWith('http://') &&
      !path.startsWith('https://')) {
    path = colonMatch.group(1) ?? path;
    line = int.tryParse(colonMatch.group(2) ?? '');
  }

  if (hash.startsWith('L')) {
    line = int.tryParse(hash.substring(1));
  }

  if (path.isEmpty) {
    return null;
  }
  return _ResolvedReference(path: path, line: line);
}

String _linkifyPlainFileReferences(String input) {
  final markdownMatches = _matchMarkdownReferences(input).toList();
  final plainMatches = _matchPlainReferences(input).where((plainMatch) {
    for (final markdownMatch in markdownMatches) {
      if (plainMatch.start >= markdownMatch.start &&
          plainMatch.end <= markdownMatch.end) {
        return false;
      }
    }
    return true;
  }).toList()..sort((left, right) => left.start.compareTo(right.start));

  if (plainMatches.isEmpty) {
    return input;
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in plainMatches) {
    if (match.start < cursor) {
      continue;
    }
    buffer.write(input.substring(cursor, match.start));
    final href = match.line == null
        ? match.path
        : '${match.path}#L${match.line}';
    buffer.write('[${match.displayText}]($href)');
    cursor = match.end;
  }
  if (cursor < input.length) {
    buffer.write(input.substring(cursor));
  }
  return buffer.toString();
}

class _ExpandableEntryBody extends StatefulWidget {
  const _ExpandableEntryBody({
    required this.text,
    required this.child,
    this.previewText,
  });

  final String text;
  final Widget child;
  final String? previewText;

  @override
  State<_ExpandableEntryBody> createState() => _ExpandableEntryBodyState();
}

class _ExpandableEntryBodyState extends State<_ExpandableEntryBody> {
  bool _isExpanded = false;

  bool get _shouldCollapse {
    final lines = '\n'.allMatches(widget.text).length + 1;
    return lines > 12 || widget.text.length > 900;
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldCollapse) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final previewText = (widget.previewText ?? widget.text).trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AnimatedCrossFade(
          firstChild: Stack(
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: Text(
                  previewText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.25,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (previewText.contains('\n') || previewText.length > 120)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            theme.colorScheme.surface.withValues(alpha: 0),
                            theme.colorScheme.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          secondChild: widget.child,
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 140),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: ValueKey<String>(
            _isExpanded ? 'entry-body-collapse' : 'entry-body-expand',
          ),
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          icon: Icon(_isExpanded ? Icons.unfold_less : Icons.unfold_more),
          label: Text(_isExpanded ? 'Collapse' : 'Expand'),
        ),
      ],
    );
  }
}

class _GitDiffView extends StatelessWidget {
  const _GitDiffView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = text.split('\n');
    final rows = lines.map((line) => _GitDiffLine.fromRaw(line)).toList();
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      height: 1.25,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        key: const ValueKey<String>('git-diff-view'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: rows.map((row) {
                return ColoredBox(
                  color: row.backgroundColor(theme.colorScheme),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Text(
                      row.displayText,
                      style: style?.copyWith(
                        color: row.foregroundColor(theme.colorScheme),
                        fontWeight: row.isEmphasized
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

String _collapsedPreviewText(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.isNotEmpty)
      .take(2)
      .toList();
  if (lines.isEmpty) {
    return text.trim();
  }
  return lines.join('\n');
}

String _summarizeFileChangeTitle(String text, {required String fallback}) {
  final lines = text.split('\n');
  String fileName = fallback;
  var added = 0;
  var removed = 0;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (fileName == fallback) {
      if (line.contains(' • ')) {
        fileName = line.split(' • ').first.trim();
      } else if (line.startsWith('+++ ')) {
        fileName = line.substring(4).replaceFirst(RegExp(r'^[ab]/'), '').trim();
      } else if (line.startsWith('diff --git ')) {
        final parts = line.split(' ');
        if (parts.length >= 4) {
          fileName = parts[2].replaceFirst(RegExp(r'^[ab]/'), '').trim();
        }
      }
    }
    if (rawLine.startsWith('+') && !rawLine.startsWith('+++ ')) {
      added += 1;
    } else if (rawLine.startsWith('-') && !rawLine.startsWith('--- ')) {
      removed += 1;
    }
  }

  final segments = <String>[fileName];
  if (added > 0) {
    segments.add('+$added');
  }
  if (removed > 0) {
    segments.add('-$removed');
  }
  return segments.join('  ');
}

class _GitDiffLine {
  const _GitDiffLine({required this.displayText, required this.kind});

  factory _GitDiffLine.fromRaw(String raw) {
    if (raw.startsWith('diff --git') ||
        raw.startsWith('index ') ||
        raw.startsWith('--- ') ||
        raw.startsWith('+++ ')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.header);
    }
    if (raw.startsWith('@@')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.hunk);
    }
    if (raw.startsWith('+')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.addition);
    }
    if (raw.startsWith('-')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.removal);
    }
    if (raw.contains(' • ')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.meta);
    }
    return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.context);
  }

  final String displayText;
  final _GitDiffLineKind kind;

  bool get isEmphasized {
    return switch (kind) {
      _GitDiffLineKind.header ||
      _GitDiffLineKind.hunk ||
      _GitDiffLineKind.meta => true,
      _GitDiffLineKind.addition ||
      _GitDiffLineKind.removal ||
      _GitDiffLineKind.context => false,
    };
  }

  Color backgroundColor(ColorScheme scheme) {
    return switch (kind) {
      _GitDiffLineKind.addition => Colors.green.withValues(alpha: 0.14),
      _GitDiffLineKind.removal => Colors.red.withValues(alpha: 0.14),
      _GitDiffLineKind.hunk => scheme.tertiary.withValues(alpha: 0.12),
      _GitDiffLineKind.meta => scheme.primary.withValues(alpha: 0.08),
      _GitDiffLineKind.header => scheme.surfaceContainerHighest.withValues(
        alpha: 0.6,
      ),
      _GitDiffLineKind.context => Colors.transparent,
    };
  }

  Color foregroundColor(ColorScheme scheme) {
    return switch (kind) {
      _GitDiffLineKind.addition => Colors.green.shade800,
      _GitDiffLineKind.removal => Colors.red.shade800,
      _GitDiffLineKind.hunk => scheme.tertiary,
      _GitDiffLineKind.meta => scheme.primary,
      _GitDiffLineKind.header => scheme.onSurfaceVariant,
      _GitDiffLineKind.context => scheme.onSurface,
    };
  }
}

enum _GitDiffLineKind { meta, header, hunk, addition, removal, context }

class DownloadCenterPage extends StatelessWidget {
  const DownloadCenterPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Downloads'),
            actions: <Widget>[
              TextButton(
                onPressed:
                    controller.downloadRecords.any(
                      (item) => item.state != DownloadState.running,
                    )
                    ? controller.clearFinishedDownloads
                    : null,
                child: const Text('Clear finished'),
              ),
            ],
          ),
          body: SafeArea(
            child: controller.downloadRecords.isEmpty
                ? Center(
                    child: Text(
                      'No downloads yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: controller.downloadRecords.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final record = controller.downloadRecords[index];
                      return _DownloadRecordTile(
                        record: record,
                        onOpen: record.targetPath == null
                            ? null
                            : () => openDownloadedLocation(
                                context,
                                record.targetPath!,
                              ),
                        onCancel: record.state == DownloadState.running
                            ? () => controller.cancelFileDownload(
                                record.sourcePath,
                              )
                            : null,
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class AutomationPage extends StatefulWidget {
  const AutomationPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<AutomationPage> {
  bool _showAllAutomations = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final theme = Theme.of(context);
        final visibleAutomations = _showAllAutomations
            ? widget.controller.automations
            : widget.controller.automations
                  .where(widget.controller.isAutomationVisibleInCurrentThread)
                  .toList(growable: false);
        final emptyMessage = _showAllAutomations
            ? 'Create automations from nodes: a filesystem watch trigger followed by sequential actions like download, install APK, or run a command.'
            : 'No automations are scoped to the current thread yet.';
        return Scaffold(
          appBar: AppBar(
            title: const Text('Automations'),
            actions: <Widget>[
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAllAutomations = !_showAllAutomations;
                  });
                },
                icon: Icon(
                  _showAllAutomations ? Icons.list : Icons.filter_alt,
                  size: 18,
                ),
                label: Text(_showAllAutomations ? 'All' : 'Current'),
              ),
              IconButton(
                tooltip: 'New automation',
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          body: visibleAutomations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      emptyMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemBuilder: (BuildContext context, int index) {
                    final automation = visibleAutomations[index];
                    final ownerThreadId = automation.ownerThreadId.trim();
                    final currentThreadId = widget
                        .controller
                        .currentAutomationScopeThreadId
                        .trim();
                    final canCopyToCurrentThread =
                        ownerThreadId.isNotEmpty &&
                        currentThreadId.isNotEmpty &&
                        ownerThreadId != currentThreadId;
                    return _AutomationCard(
                      automation: automation,
                      isRunning: widget.controller.isAutomationRunning(
                        automation.id,
                      ),
                      onToggleEnabled: (value) {
                        widget.controller.setAutomationEnabled(
                          automation.id,
                          value,
                        );
                      },
                      onEdit: () =>
                          _openEditor(context, automation: automation),
                      onCopyToCurrentThread: canCopyToCurrentThread
                          ? () => widget.controller
                                .copyAutomationToCurrentThread(automation.id)
                          : null,
                      onDelete: () =>
                          widget.controller.deleteAutomation(automation.id),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemCount: visibleAutomations.length,
                ),
        );
      },
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    AutomationDefinition? automation,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationEditorPage(
            controller: widget.controller,
            initialAutomation:
                automation ??
                AutomationDefinition(
                  id: 'automation-${DateTime.now().microsecondsSinceEpoch}',
                  name: '',
                  enabled: true,
                  nodes: const <AutomationNode>[],
                ),
          );
        },
      ),
    );
  }
}

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({
    required this.automation,
    required this.isRunning,
    required this.onToggleEnabled,
    required this.onEdit,
    required this.onCopyToCurrentThread,
    required this.onDelete,
  });

  final AutomationDefinition automation;
  final bool isRunning;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onEdit;
  final VoidCallback? onCopyToCurrentThread;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trigger = automation.triggerNode;
    final actions = automation.actionNodes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    automation.name.trim().isEmpty
                        ? 'Untitled automation'
                        : automation.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Switch(value: automation.enabled, onChanged: onToggleEnabled),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              trigger == null
                  ? 'No trigger configured'
                  : trigger.path.trim().isEmpty
                  ? trigger.kind.title
                  : '${trigger.kind.title} • ${trigger.path}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              actions.isEmpty
                  ? 'No actions configured'
                  : actions.map((node) => node.kind.title).join(' → '),
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isRunning
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isRunning
                        ? 'Running'
                        : automation.enabled
                        ? 'Enabled'
                        : 'Disabled',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isRunning
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: onEdit, child: const Text('Edit')),
                if (onCopyToCurrentThread != null)
                  TextButton(
                    onPressed: onCopyToCurrentThread,
                    child: const Text('Copy'),
                  ),
                TextButton(onPressed: onDelete, child: const Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AutomationEditorPage extends StatefulWidget {
  const AutomationEditorPage({
    super.key,
    required this.controller,
    required this.initialAutomation,
  });

  final AppController controller;
  final AutomationDefinition initialAutomation;

  @override
  State<AutomationEditorPage> createState() => _AutomationEditorPageState();
}

class _AutomationEditorPageState extends State<AutomationEditorPage> {
  late final TextEditingController _nameController;
  late bool _enabled;
  late List<AutomationNode> _nodes;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialAutomation.name,
    );
    _enabled = widget.initialAutomation.enabled;
    _nodes = List<AutomationNode>.from(widget.initialAutomation.nodes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trigger = _nodes.where((node) => node.kind.isTrigger).toList();
    final actions = _nodes.where((node) => !node.kind.isTrigger).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automation'),
        actions: <Widget>[
          TextButton(onPressed: _saveAutomation, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Automation name'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Text('Nodes', style: theme.textTheme.titleLarge),
                const Spacer(),
                if (trigger.isEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _addNode(isTrigger: true),
                    icon: const Icon(Icons.flash_on_outlined),
                    label: const Text('Add trigger'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _addNode(isTrigger: false),
                    icon: const Icon(Icons.add),
                    label: const Text('Add action'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_nodes.isEmpty)
              Text(
                'Start with a trigger, then add sequential action and control nodes.',
                style: theme.textTheme.bodyMedium,
              )
            else
              ..._nodes.asMap().entries.map((entry) {
                final index = entry.key;
                final node = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == _nodes.length - 1 ? 0 : 10,
                  ),
                  child: _AutomationNodeCard(
                    index: index,
                    node: node,
                    onEdit: () => _editNode(index),
                    onDelete: () {
                      setState(() {
                        _nodes.removeAt(index);
                      });
                    },
                  ),
                );
              }),
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                'Sequential actions run in the order shown above.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addNode({required bool isTrigger}) async {
    final kind = await showModalBottomSheet<AutomationNodeKind>(
      context: context,
      builder: (BuildContext context) {
        final options = isTrigger
            ? const <AutomationNodeKind>[
                AutomationNodeKind.watchFileChanged,
                AutomationNodeKind.watchDirectoryChanged,
                AutomationNodeKind.turnCompleted,
              ]
            : const <AutomationNodeKind>[
                AutomationNodeKind.didPathChangeSinceLastRun,
                AutomationNodeKind.ifElse,
                AutomationNodeKind.quit,
                AutomationNodeKind.downloadChangedFile,
                AutomationNodeKind.installDownloadedApk,
                AutomationNodeKind.sendMessageToCurrentThread,
                AutomationNodeKind.runCommand,
              ];
        return SafeArea(
          child: Wrap(
            children: options
                .map(
                  (kind) => ListTile(
                    leading: Icon(kind.icon),
                    title: Text(kind.title),
                    onTap: () => Navigator.of(context).pop(kind),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
    if (kind == null || !mounted) {
      return;
    }
    final draft = AutomationNode(
      id: 'node-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
    );
    final edited = await Navigator.of(context).push<AutomationNode>(
      MaterialPageRoute<AutomationNode>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationNodeEditorPage(
            controller: widget.controller,
            node: draft,
          );
        },
      ),
    );
    if (edited == null) {
      return;
    }
    setState(() {
      if (kind.isTrigger) {
        _nodes.removeWhere((node) => node.kind.isTrigger);
        _nodes.insert(0, edited);
      } else {
        _nodes.add(edited);
      }
    });
  }

  Future<void> _editNode(int index) async {
    final edited = await Navigator.of(context).push<AutomationNode>(
      MaterialPageRoute<AutomationNode>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationNodeEditorPage(
            controller: widget.controller,
            node: _nodes[index],
          );
        },
      ),
    );
    if (edited == null) {
      return;
    }
    setState(() {
      _nodes[index] = edited;
      if (edited.kind.isTrigger) {
        final triggerIndex = _nodes.indexWhere((node) => node.id == edited.id);
        if (triggerIndex > 0) {
          final trigger = _nodes.removeAt(triggerIndex);
          _nodes.insert(0, trigger);
        }
      }
    });
  }

  Future<void> _saveAutomation() async {
    final name = _nameController.text.trim();
    final hasTrigger = _nodes.any((node) => node.kind.isTrigger);
    final hasAction = _nodes.any((node) => !node.kind.isTrigger);
    if (name.isEmpty || !hasTrigger || !hasAction) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Automation needs a name, one trigger, and at least one action.',
          ),
        ),
      );
      return;
    }
    await widget.controller.saveAutomation(
      widget.initialAutomation.copyWith(
        name: name,
        enabled: _enabled,
        nodes: List<AutomationNode>.from(_nodes),
      ),
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}

class _AutomationNodeCard extends StatelessWidget {
  const _AutomationNodeCard({
    required this.index,
    required this.node,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final AutomationNode node;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Text('${index + 1}', style: theme.textTheme.labelSmall),
        ),
        title: Text(node.kind.title),
        subtitle: Text(
          _automationNodeSummary(node),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onEdit,
        trailing: IconButton(
          tooltip: 'Delete node',
          onPressed: onDelete,
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }
}

class AutomationNodeEditorPage extends StatefulWidget {
  const AutomationNodeEditorPage({
    super.key,
    required this.controller,
    required this.node,
  });

  final AppController controller;
  final AutomationNode node;

  @override
  State<AutomationNodeEditorPage> createState() =>
      _AutomationNodeEditorPageState();
}

class _AutomationNodeEditorPageState extends State<AutomationNodeEditorPage> {
  late final TextEditingController _pathController;
  late final TextEditingController _commandController;
  late final TextEditingController _cwdController;
  late final TextEditingController _directoryController;
  late final TextEditingController _conditionTokenController;
  late AutomationBranchOutcome _whenTrue;
  late AutomationBranchOutcome _whenFalse;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.node.path);
    _commandController = TextEditingController(text: widget.node.commandText);
    _cwdController = TextEditingController(text: widget.node.cwd);
    _directoryController = TextEditingController(text: widget.node.directory);
    _conditionTokenController = TextEditingController(
      text: widget.node.conditionToken,
    );
    _whenTrue = widget.node.whenTrue;
    _whenFalse = widget.node.whenFalse;
  }

  @override
  void dispose() {
    _pathController.dispose();
    _commandController.dispose();
    _cwdController.dispose();
    _directoryController.dispose();
    _conditionTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    return Scaffold(
      appBar: AppBar(
        title: Text(node.kind.title),
        actions: <Widget>[
          TextButton(onPressed: _saveNode, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            if (node.kind == AutomationNodeKind.watchFileChanged ||
                node.kind ==
                    AutomationNodeKind.watchDirectoryChanged) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      decoration: InputDecoration(
                        labelText:
                            node.kind ==
                                AutomationNodeKind.watchDirectoryChanged
                            ? 'Folder path'
                            : 'File path',
                        hintText:
                            node.kind ==
                                AutomationNodeKind.watchDirectoryChanged
                            ? '/workspace/app'
                            : '/workspace/app/build/app-release.apk',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Browse remote files',
                    onPressed: () => _browseForPath(
                      node.kind,
                      allowDirectorySelection:
                          node.kind == AutomationNodeKind.watchDirectoryChanged,
                      allowFileSelection:
                          node.kind != AutomationNodeKind.watchDirectoryChanged,
                    ),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ],
              ),
            ],
            if (node.kind == AutomationNodeKind.turnCompleted) ...<Widget>[
              const Text(
                'Triggers after the app-server reports an LLM turn completed. No filesystem path is required.',
              ),
              const SizedBox(height: 8),
              Text(
                'Use this with actions like Run command to start follow-up automation after a response finishes.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (node.kind == AutomationNodeKind.watchFileChanged ||
                node.kind ==
                    AutomationNodeKind.watchDirectoryChanged) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Pick the trigger target from the remote file explorer.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (node.kind ==
                AutomationNodeKind.didPathChangeSinceLastRun) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      decoration: const InputDecoration(
                        labelText: 'File or folder path',
                        hintText: '/workspace/app/build/app-release.apk',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Browse remote files',
                    onPressed: () => _browseForPath(
                      node.kind,
                      allowDirectorySelection: true,
                      allowFileSelection: true,
                    ),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Compares the selected file or folder against the previous execution of this automation and stores {{previous.changed}} for the next node.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (node.kind == AutomationNodeKind.ifElse) ...<Widget>[
              TextField(
                controller: _conditionTokenController,
                decoration: const InputDecoration(
                  labelText: 'Condition value or template',
                  hintText: '{{previous.changed}}',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AutomationBranchOutcome>(
                initialValue: _whenTrue,
                decoration: const InputDecoration(labelText: 'When true'),
                items: AutomationBranchOutcome.values
                    .map(
                      (value) => DropdownMenuItem<AutomationBranchOutcome>(
                        value: value,
                        child: Text(_branchOutcomeLabel(value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _whenTrue = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AutomationBranchOutcome>(
                initialValue: _whenFalse,
                decoration: const InputDecoration(labelText: 'When false'),
                items: AutomationBranchOutcome.values
                    .map(
                      (value) => DropdownMenuItem<AutomationBranchOutcome>(
                        value: value,
                        child: Text(_branchOutcomeLabel(value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _whenFalse = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Defaults to {{previous.changed}} so it can branch after a Did file or folder change node.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (node.kind == AutomationNodeKind.quit) ...<Widget>[
              const Text(
                'Stops the automation immediately when this node is reached.',
              ),
            ],
            if (node.kind ==
                AutomationNodeKind.downloadChangedFile) ...<Widget>[
              Text(
                'Downloads the file path reported by the trigger. If no explicit directory is set here, the automation uses the remembered download directory for the active thread.',
              ),
              const SizedBox(height: 8),
              Text(
                'Optional templates: {{trigger.changedPath}}, {{previous.downloadedPath}}, {{node.someId.downloadedPath}}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _directoryController,
                decoration: const InputDecoration(
                  labelText: 'Download directory (optional)',
                  hintText: '/storage/emulated/0/Download',
                ),
              ),
            ],
            if (node.kind ==
                AutomationNodeKind.installDownloadedApk) ...<Widget>[
              const Text(
                'Opens the downloaded APK with the system installer. By default it uses the previous download node output.',
              ),
              const SizedBox(height: 8),
              Text(
                'Optional path override or template: {{previous.downloadedPath}}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'APK path override (optional)',
                  hintText: '{{previous.downloadedPath}}',
                ),
              ),
            ],
            if (node.kind ==
                AutomationNodeKind.sendMessageToCurrentThread) ...<Widget>[
              TextField(
                controller: _commandController,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'A new APK build is ready.',
                ),
                maxLines: 4,
                minLines: 2,
              ),
              const SizedBox(height: 8),
              Text(
                'Templates: {{trigger.changedPath}}, {{previous.downloadedPath}}, {{previous.stdout}}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (node.kind == AutomationNodeKind.runCommand) ...<Widget>[
              TextField(
                controller: _commandController,
                decoration: const InputDecoration(
                  labelText: 'Command',
                  hintText: 'flutter build apk --release',
                ),
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cwdController,
                decoration: const InputDecoration(
                  labelText: 'Working directory (optional)',
                  hintText: '/workspace/app',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Templates: {{trigger.changedPath}}, {{trigger.path}}, {{previous.stdout}}, {{previous.downloadedPath}}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _saveNode() {
    final next = widget.node.copyWith(
      path: _pathController.text.trim(),
      commandText: _commandController.text.trim(),
      cwd: _cwdController.text.trim(),
      directory: _directoryController.text.trim(),
      conditionToken: _conditionTokenController.text.trim(),
      whenTrue: _whenTrue,
      whenFalse: _whenFalse,
    );
    final needsPath =
        next.kind == AutomationNodeKind.watchFileChanged ||
        next.kind == AutomationNodeKind.watchDirectoryChanged ||
        next.kind == AutomationNodeKind.didPathChangeSinceLastRun;
    final needsCommand =
        next.kind == AutomationNodeKind.runCommand ||
        next.kind == AutomationNodeKind.sendMessageToCurrentThread;
    if (needsPath && next.path.isEmpty) {
      _showValidation('An absolute path is required.');
      return;
    }
    if (needsCommand && next.commandText.isEmpty) {
      _showValidation(
        next.kind == AutomationNodeKind.sendMessageToCurrentThread
            ? 'A message is required.'
            : 'A command is required.',
      );
      return;
    }
    Navigator.of(context).pop(next);
  }

  Future<void> _browseForPath(
    AutomationNodeKind kind, {
    bool allowDirectorySelection = false,
    bool allowFileSelection = true,
  }) async {
    final selectedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationPathPickerPage(
            controller: widget.controller,
            allowDirectorySelection: allowDirectorySelection,
            allowFileSelection: allowFileSelection,
            title: allowDirectorySelection && allowFileSelection
                ? 'Select file or folder'
                : kind == AutomationNodeKind.watchDirectoryChanged
                ? 'Select watched folder'
                : 'Select watched file',
            initialPath: _pathController.text.trim(),
          );
        },
      ),
    );
    if (selectedPath == null) {
      return;
    }
    _pathController
      ..text = selectedPath
      ..selection = TextSelection.collapsed(offset: selectedPath.length);
  }

  void _showValidation(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class AutomationPathPickerPage extends StatefulWidget {
  const AutomationPathPickerPage({
    super.key,
    required this.controller,
    required this.allowDirectorySelection,
    required this.allowFileSelection,
    required this.title,
    this.initialPath,
  });

  final AppController controller;
  final bool allowDirectorySelection;
  final bool allowFileSelection;
  final String title;
  final String? initialPath;

  @override
  State<AutomationPathPickerPage> createState() =>
      _AutomationPathPickerPageState();
}

class _AutomationPathPickerPageState extends State<AutomationPathPickerPage> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPath?.trim();
    final initialDirectory = _initialDirectory(initial);
    _pathController = TextEditingController(text: initialDirectory);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.controller.loadDirectory(initialDirectory));
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final controller = widget.controller;
        final theme = Theme.of(context);
        if (_pathController.text != controller.fileBrowserPath &&
            controller.fileBrowserPath.isNotEmpty) {
          _pathController.value = _pathController.value.copyWith(
            text: controller.fileBrowserPath,
            selection: TextSelection.collapsed(
              offset: controller.fileBrowserPath.length,
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            actions: <Widget>[
              if (widget.allowDirectorySelection)
                TextButton(
                  onPressed: controller.fileBrowserPath.trim().isEmpty
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(controller.fileBrowserPath),
                  child: const Text('Select'),
                ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Up',
                        onPressed: controller.fileBrowserPath == '/'
                            ? null
                            : controller.navigateToParentDirectory,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _pathController,
                          decoration: const InputDecoration(
                            labelText: 'Absolute path',
                          ),
                          onSubmitted: controller.loadDirectory,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: controller.isLoadingFiles
                            ? null
                            : () => controller.loadDirectory(
                                _pathController.text,
                              ),
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                  if (controller.fileBrowserError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      controller.fileBrowserError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          controller.isLoadingFiles &&
                              controller.fileBrowserEntries.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: controller.fileBrowserEntries.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (BuildContext context, int index) {
                                final entry =
                                    controller.fileBrowserEntries[index];
                                final fullPath = controller.joinFileBrowserPath(
                                  entry.fileName,
                                );
                                return ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  tileColor:
                                      theme.colorScheme.surfaceContainerLow,
                                  leading: Icon(
                                    entry.isDirectory
                                        ? Icons.folder_outlined
                                        : Icons.insert_drive_file_outlined,
                                  ),
                                  title: Text(
                                    entry.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () async {
                                    if (entry.isDirectory) {
                                      await controller.loadDirectory(fullPath);
                                      return;
                                    }
                                    if (widget.allowFileSelection &&
                                        entry.isFile) {
                                      if (!mounted) {
                                        return;
                                      }
                                      Navigator.of(context).pop(fullPath);
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _initialDirectory(String? initialPath) {
    if (initialPath == null || initialPath.isEmpty) {
      return widget.controller.preferredFileBrowserRoot;
    }
    if (widget.allowDirectorySelection) {
      return initialPath;
    }
    final slashIndex = initialPath.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '/';
    }
    return initialPath.substring(0, slashIndex);
  }
}

String _automationNodeSummary(AutomationNode node) {
  switch (node.kind) {
    case AutomationNodeKind.watchFileChanged:
    case AutomationNodeKind.watchDirectoryChanged:
      return node.path.trim().isEmpty ? 'No path configured' : node.path.trim();
    case AutomationNodeKind.turnCompleted:
      return 'Runs after an LLM turn completes.';
    case AutomationNodeKind.didPathChangeSinceLastRun:
      return node.path.trim().isEmpty
          ? 'Compare a file or folder against the previous automation run'
          : 'Compare ${node.path.trim()} against the previous automation run';
    case AutomationNodeKind.ifElse:
      final condition = node.conditionToken.trim().isEmpty
          ? '{{previous.changed}}'
          : node.conditionToken.trim();
      return 'If $condition → ${_branchOutcomeLabel(node.whenTrue)} / ${_branchOutcomeLabel(node.whenFalse)}';
    case AutomationNodeKind.quit:
      return 'Stop the automation immediately.';
    case AutomationNodeKind.downloadChangedFile:
      return node.directory.trim().isEmpty
          ? 'Download to remembered thread directory'
          : 'Download to ${node.directory.trim()}';
    case AutomationNodeKind.installDownloadedApk:
      return 'Install the APK that was downloaded by an earlier node.';
    case AutomationNodeKind.sendMessageToCurrentThread:
      final message = node.commandText.trim();
      return message.isEmpty ? 'No message configured' : message;
    case AutomationNodeKind.runCommand:
      final command = node.commandText.trim();
      final cwd = node.cwd.trim();
      if (command.isEmpty) {
        return 'No command configured';
      }
      if (cwd.isEmpty) {
        return command;
      }
      return '$command • $cwd';
  }
}

String _branchOutcomeLabel(AutomationBranchOutcome value) {
  return switch (value) {
    AutomationBranchOutcome.continueFlow => 'Continue',
    AutomationBranchOutcome.quitFlow => 'Quit',
  };
}

class _DownloadRecordTile extends StatelessWidget {
  const _DownloadRecordTile({required this.record, this.onOpen, this.onCancel});

  final DownloadRecord record;
  final VoidCallback? onOpen;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = record.status;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_downloadStateIcon(record.state), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  record.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                _downloadStateLabel(record.state),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            record.sourcePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (status != null) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: record.state == DownloadState.running
                  ? status.progress
                  : 1,
            ),
            const SizedBox(height: 6),
            Text(_formatTransferSize(status), style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              record.state == DownloadState.running
                  ? _formatEta(status)
                  : _downloadCompletionText(record),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (record.error != null &&
              record.error!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              record.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (record.targetPath != null && onOpen != null)
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Open'),
                ),
              if (record.state == DownloadState.running &&
                  onCancel != null) ...<Widget>[
                if (record.targetPath != null) const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

IconData _downloadStateIcon(DownloadState state) {
  return switch (state) {
    DownloadState.running => Icons.downloading_rounded,
    DownloadState.completed => Icons.download_done_outlined,
    DownloadState.failed => Icons.error_outline,
    DownloadState.cancelled => Icons.remove_circle_outline,
  };
}

String _downloadStateLabel(DownloadState state) {
  return switch (state) {
    DownloadState.running => 'Downloading',
    DownloadState.completed => 'Completed',
    DownloadState.failed => 'Failed',
    DownloadState.cancelled => 'Cancelled',
  };
}

String _downloadCompletionText(DownloadRecord record) {
  final finishedAt = record.finishedAt;
  if (finishedAt == null) {
    return '';
  }
  final local = finishedAt;
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'Finished at $hour:$minute';
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ConnectionMode _connectionMode;
  late final TextEditingController _serverController;
  late final TextEditingController _websocketBearerTokenController;
  late final TextEditingController _relayUrlController;
  late final TextEditingController _pairingCodeController;
  late ThemePreference _themePreference;
  late SandboxMode _sandboxMode;
  late String _approvalPolicy;
  late bool _allowNetwork;
  bool _isPairing = false;
  String? _pairingError;
  String? _pairingSuccess;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _connectionMode = settings.connectionMode;
    _serverController = TextEditingController(text: settings.serverUrl);
    _websocketBearerTokenController = TextEditingController(
      text: settings.websocketBearerToken,
    );
    _relayUrlController = TextEditingController(text: settings.relayUrl);
    _pairingCodeController = TextEditingController();
    _themePreference = settings.themePreference;
    _sandboxMode = settings.sandboxMode;
    _approvalPolicy = settings.approvalPolicy;
    _allowNetwork = settings.allowNetwork;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _websocketBearerTokenController.dispose();
    _relayUrlController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DropdownButtonFormField<ConnectionMode>(
                initialValue: _connectionMode,
                decoration: const InputDecoration(labelText: 'Connection mode'),
                items: ConnectionMode.values.map((ConnectionMode value) {
                  return DropdownMenuItem<ConnectionMode>(
                    value: value,
                    child: Text(value.name),
                  );
                }).toList(),
                onChanged: (ConnectionMode? value) {
                  if (value != null) {
                    setState(() {
                      _connectionMode = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_connectionMode == ConnectionMode.direct) ...<Widget>[
                TextField(
                  controller: _serverController,
                  decoration: const InputDecoration(
                    labelText: 'Websocket URL',
                    hintText: 'ws://192.168.1.20:8080',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _websocketBearerTokenController,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Websocket bearer token',
                    hintText: 'Optional Authorization: Bearer token',
                    helperText:
                        'Sent during the websocket handshake when app-server auth is enabled.',
                  ),
                ),
              ] else ...<Widget>[
                TextField(
                  controller: _relayUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Relay URL',
                    hintText: 'https://relay.example.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pairingCodeController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Pairing code',
                    hintText: 'crp1....',
                    helperText:
                        'Paste the pairing code or scan the QR shown by codex-remote-cli.',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isPairing ? null : _scanRelayQrCode,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR code'),
                  ),
                ),
                if (widget.controller.settings.relayDeviceId.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Paired bridge: ${widget.controller.settings.relayBridgeLabel.isEmpty ? widget.controller.settings.relayDeviceId : widget.controller.settings.relayBridgeLabel}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (_pairingError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _pairingError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                if (_pairingSuccess != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _pairingSuccess!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isPairing ? null : _pairRelayDevice,
                        child: Text(_isPairing ? 'Pairing...' : 'Pair device'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            widget.controller.settings.relayDeviceId.isEmpty
                            ? null
                            : _clearRelayPairing,
                        child: const Text('Clear pairing'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<ThemePreference>(
                initialValue: _themePreference,
                decoration: const InputDecoration(labelText: 'Theme'),
                items: ThemePreference.values.map((item) {
                  return DropdownMenuItem<ThemePreference>(
                    value: item,
                    child: Text(item.name),
                  );
                }).toList(),
                onChanged: (ThemePreference? value) {
                  if (value != null) {
                    setState(() => _themePreference = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SandboxMode>(
                initialValue: _sandboxMode,
                decoration: const InputDecoration(labelText: 'Sandbox'),
                items: SandboxMode.values.map((item) {
                  return DropdownMenuItem<SandboxMode>(
                    value: item,
                    child: Text(item.name),
                  );
                }).toList(),
                onChanged: (SandboxMode? value) {
                  if (value != null) {
                    setState(() => _sandboxMode = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _approvalPolicy,
                decoration: const InputDecoration(labelText: 'Approval policy'),
                items:
                    const <String>[
                      'untrusted',
                      'on-request',
                      'on-failure',
                      'never',
                    ].map((item) {
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      );
                    }).toList(),
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _approvalPolicy = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _allowNetwork,
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow network in workspace-write mode'),
                onChanged: (bool value) {
                  setState(() => _allowNetwork = value);
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Last thread: ${widget.controller.settings.resumeThreadId.isEmpty ? 'none' : widget.controller.settings.resumeThreadId}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final nextSettings = widget.controller.settings.copyWith(
      connectionMode: _connectionMode,
      serverUrl: _serverController.text.trim(),
      websocketBearerToken: _websocketBearerTokenController.text.trim(),
      relayUrl: _relayUrlController.text.trim(),
      themePreference: _themePreference,
      sandboxMode: _sandboxMode,
      approvalPolicy: _approvalPolicy,
      allowNetwork: _allowNetwork,
    );
    await widget.controller.reconnectWithSettings(nextSettings);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pairRelayDevice() async {
    await _pairRelayDeviceWithCode(_pairingCodeController.text);
  }

  Future<void> _pairRelayDeviceWithCode(String pairingCode) async {
    setState(() {
      _isPairing = true;
      _pairingError = null;
      _pairingSuccess = null;
    });
    try {
      await widget.controller.pairRelayDevice(pairingCode: pairingCode);
      _relayUrlController.text = widget.controller.settings.relayUrl;
      _pairingCodeController.clear();
      setState(() {
        _pairingSuccess = 'Device paired successfully.';
        _connectionMode = ConnectionMode.relay;
      });
    } catch (error) {
      setState(() {
        _pairingError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPairing = false;
        });
      }
    }
  }

  Future<void> _scanRelayQrCode() async {
    final scannedCode = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const _RelayPairingQrScannerPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || scannedCode == null || scannedCode.isEmpty) {
      return;
    }
    _pairingCodeController.text = scannedCode;
    await _pairRelayDeviceWithCode(scannedCode);
  }

  Future<void> _clearRelayPairing() async {
    await widget.controller.clearRelayPairing();
    _relayUrlController.clear();
    setState(() {
      _pairingError = null;
      _pairingSuccess = null;
      _connectionMode = ConnectionMode.direct;
    });
  }
}

class _RelayPairingQrScannerPage extends StatefulWidget {
  const _RelayPairingQrScannerPage();

  @override
  State<_RelayPairingQrScannerPage> createState() =>
      _RelayPairingQrScannerPageState();
}

class _RelayPairingQrScannerPageState
    extends State<_RelayPairingQrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handledCode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Pairing QR')),
      body: Stack(
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: (BarcodeCapture capture) {
              if (_handledCode) {
                return;
              }
              for (final barcode in capture.barcodes) {
                final rawValue = barcode.rawValue?.trim() ?? '';
                if (!rawValue.startsWith('crp1.')) {
                  continue;
                }
                _handledCode = true;
                _controller.stop();
                Navigator.of(context).pop(rawValue);
                return;
              }
            },
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Point the camera at the relay pairing QR code.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EventLogSheet extends StatelessWidget {
  const EventLogSheet({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Event log', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: ListView.separated(
              itemCount: controller.eventLog.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final entry = controller.eventLog[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(entry.method, style: theme.textTheme.titleMedium),
                      if (entry.summary.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        SelectableText(
                          entry.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CommandCenterPage extends StatefulWidget {
  const CommandCenterPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<CommandCenterPage> createState() => _CommandCenterPageState();
}

class _CommandCenterPageState extends State<CommandCenterPage> {
  late final TextEditingController _commandController;
  late final TextEditingController _cwdController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _outputCapController;
  late SandboxMode _sandboxMode;
  late bool _allowNetwork;
  bool _disableTimeout = false;
  bool _disableOutputCap = true;
  int _lastRows = 0;
  int _lastCols = 0;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    final settings = controller.settings;
    _commandController = TextEditingController();
    _cwdController = TextEditingController(
      text: controller.preferredCommandCwd,
    );
    _timeoutController = TextEditingController(text: '60000');
    _outputCapController = TextEditingController(text: '32768');
    _sandboxMode = settings.sandboxMode;
    _allowNetwork = settings.allowNetwork;
  }

  @override
  void dispose() {
    _commandController.dispose();
    _cwdController.dispose();
    _timeoutController.dispose();
    _outputCapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final activeSession = widget.controller.activeCommandSession;
        final preferredCwd = widget.controller.preferredCommandCwd;
        if (_commandController.text.isEmpty &&
            _cwdController.text.trim().isEmpty &&
            preferredCwd.isNotEmpty) {
          _cwdController.text = preferredCwd;
        }
        final hasRunningCommand = widget.controller.commandSessions.any(
          (session) => session.isRunning,
        );
        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Command settings',
              onPressed: _openSettingsModal,
              icon: const Icon(Icons.settings_outlined),
            ),
            title: const Text('Command Center'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final shellHeight = constraints.maxHeight * 0.6;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        height: shellHeight,
                        child: _CommandSessionView(
                          session: activeSession,
                          commandController: _commandController,
                          onSubmit: _submitShellInput,
                          onTerminate: activeSession == null
                              ? null
                              : () => widget.controller.terminateCommandSession(
                                  activeSession.id,
                                ),
                          onResize: activeSession == null
                              ? null
                              : (int rows, int cols) {
                                  if (_lastRows == rows && _lastCols == cols) {
                                    return;
                                  }
                                  _lastRows = rows;
                                  _lastCols = cols;
                                  widget.controller.resizeCommandSession(
                                    activeSession.id,
                                    rows: rows,
                                    cols: cols,
                                  );
                                },
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: _CommandHistoryPanel(
                          controller: widget.controller,
                          canRepeat:
                              _commandController.text.trim().isEmpty &&
                              !hasRunningCommand,
                          onRepeat: _repeatCommandFromHistory,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _runCommand() async {
    final timeoutMs = int.tryParse(_timeoutController.text.trim()) ?? 0;
    final outputCap = int.tryParse(_outputCapController.text.trim()) ?? 0;
    await widget.controller.startCommandExecution(
      commandText: _commandController.text,
      cwd: _cwdController.text,
      sandboxMode: _sandboxMode,
      allowNetwork: _allowNetwork,
      mode: CommandSessionMode.interactive,
      timeoutMs: timeoutMs,
      disableTimeout: _disableTimeout,
      outputBytesCap: outputCap,
      disableOutputCap: _disableOutputCap,
      rows: 24,
      cols: 96,
    );
    _commandController.clear();
  }

  Future<void> _sendCommandInput(CommandSession session) async {
    final text = _commandController.text;
    _commandController.clear();
    await widget.controller.writeToCommandSession(session.id, '$text\n');
  }

  Future<void> _submitShellInput() async {
    final session = widget.controller.activeCommandSession;
    final canSendToInteractive =
        session != null &&
        session.isInteractive &&
        session.isRunning &&
        !session.stdinClosed;
    if (canSendToInteractive) {
      await _sendCommandInput(session);
      return;
    }
    await _runCommand();
  }

  void _applyRecentCommand(RecentCommand recent) {
    _commandController.text = recent.commandText;
    _cwdController.text = recent.cwd;
    _timeoutController.text = recent.timeoutMs.toString();
    _outputCapController.text = recent.outputBytesCap.toString();
    setState(() {
      _sandboxMode = recent.sandboxMode;
      _allowNetwork = recent.allowNetwork;
      _disableTimeout = recent.disableTimeout;
      _disableOutputCap = recent.disableOutputCap;
    });
  }

  void _repeatCommandFromHistory(CommandSession session) {
    if (_commandController.text.trim().isNotEmpty) {
      return;
    }
    if (widget.controller.commandSessions.any((item) => item.isRunning)) {
      return;
    }
    final command = session.commandDisplay.trim();
    if (command.isEmpty) {
      return;
    }
    _commandController
      ..text = command
      ..selection = TextSelection.collapsed(offset: command.length);
  }

  Future<void> _openSettingsModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.82,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.viewInsetsOf(context).bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _CommandForm(
                        cwdController: _cwdController,
                        timeoutController: _timeoutController,
                        outputCapController: _outputCapController,
                        sandboxMode: _sandboxMode,
                        allowNetwork: _allowNetwork,
                        disableTimeout: _disableTimeout,
                        disableOutputCap: _disableOutputCap,
                        onSandboxChanged: (SandboxMode value) {
                          setState(() => _sandboxMode = value);
                          setModalState(() {});
                        },
                        onAllowNetworkChanged: (bool value) {
                          setState(() => _allowNetwork = value);
                          setModalState(() {});
                        },
                        onDisableTimeoutChanged: (bool value) {
                          setState(() => _disableTimeout = value);
                          setModalState(() {});
                        },
                        onDisableOutputCapChanged: (bool value) {
                          setState(() => _disableOutputCap = value);
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      _SavedCommandPanel(
                        controller: widget.controller,
                        onTapCommand: (RecentCommand recent) {
                          _applyRecentCommand(recent);
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CommandForm extends StatelessWidget {
  const _CommandForm({
    required this.cwdController,
    required this.timeoutController,
    required this.outputCapController,
    required this.sandboxMode,
    required this.allowNetwork,
    required this.disableTimeout,
    required this.disableOutputCap,
    required this.onSandboxChanged,
    required this.onAllowNetworkChanged,
    required this.onDisableTimeoutChanged,
    required this.onDisableOutputCapChanged,
  });

  final TextEditingController cwdController;
  final TextEditingController timeoutController;
  final TextEditingController outputCapController;
  final SandboxMode sandboxMode;
  final bool allowNetwork;
  final bool disableTimeout;
  final bool disableOutputCap;
  final ValueChanged<SandboxMode> onSandboxChanged;
  final ValueChanged<bool> onAllowNetworkChanged;
  final ValueChanged<bool> onDisableTimeoutChanged;
  final ValueChanged<bool> onDisableOutputCapChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Setup', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.terminal_outlined),
            title: const Text('Interactive shell'),
            subtitle: const Text('Commands always run in interactive mode.'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: cwdController,
            decoration: const InputDecoration(labelText: 'Working directory'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SandboxMode>(
            initialValue: sandboxMode,
            decoration: const InputDecoration(labelText: 'Sandbox'),
            items: SandboxMode.values
                .map(
                  (SandboxMode item) => DropdownMenuItem<SandboxMode>(
                    value: item,
                    child: Text(item.name),
                  ),
                )
                .toList(),
            onChanged: (SandboxMode? value) {
              if (value != null) {
                onSandboxChanged(value);
              }
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Network'),
            value: allowNetwork,
            onChanged: onAllowNetworkChanged,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disable timeout'),
            value: disableTimeout,
            onChanged: onDisableTimeoutChanged,
          ),
          if (!disableTimeout) ...<Widget>[
            TextField(
              controller: timeoutController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Timeout ms'),
            ),
            const SizedBox(height: 8),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disable output cap'),
            value: disableOutputCap,
            onChanged: onDisableOutputCapChanged,
          ),
          if (!disableOutputCap) ...<Widget>[
            TextField(
              controller: outputCapController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Output cap bytes'),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CommandSessionCard extends StatelessWidget {
  const _CommandSessionCard({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.canRepeat,
    required this.onRepeat,
  });

  final CommandSession session;
  final bool selected;
  final VoidCallback onTap;
  final bool canRepeat;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IconButton(
              tooltip: 'Repeat',
              onPressed: canRepeat ? onRepeat : null,
              visualDensity: const VisualDensity(
                horizontal: -4,
                vertical: -4,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              splashRadius: 16,
              icon: const Icon(Icons.replay, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    session.commandDisplay,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session.statusLabel,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (session.cwd.isNotEmpty)
                    Text(
                      session.cwd,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentCommandCard extends StatelessWidget {
  const _RecentCommandCard({
    required this.command,
    required this.onTap,
    required this.onRemove,
  });

  final RecentCommand command;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    command.commandText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    command.sandboxMode.name,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (command.cwd.isNotEmpty)
                    Text(
                      command.cwd,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove saved command',
              onPressed: onRemove,
              visualDensity: const VisualDensity(
                horizontal: -4,
                vertical: -4,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              splashRadius: 16,
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandSessionView extends StatefulWidget {
  const _CommandSessionView({
    required this.session,
    required this.commandController,
    required this.onSubmit,
    required this.onTerminate,
    required this.onResize,
  });

  final CommandSession? session;
  final TextEditingController commandController;
  final Future<void> Function() onSubmit;
  final VoidCallback? onTerminate;
  final void Function(int rows, int cols)? onResize;

  @override
  State<_CommandSessionView> createState() => _CommandSessionViewState();
}

class _CommandSessionViewState extends State<_CommandSessionView> {
  final ScrollController _verticalOutputController = ScrollController();
  final ScrollController _horizontalOutputController = ScrollController();

  @override
  void dispose() {
    _verticalOutputController.dispose();
    _horizontalOutputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final interactiveInput =
        session != null &&
        session.isInteractive &&
        session.isRunning &&
        !session.stdinClosed;
    return Container(
      key: const ValueKey<String>('command-shell-panel'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        session?.commandDisplay ?? 'Shell',
                        key: const ValueKey<String>('command-shell-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session?.cwd.isNotEmpty == true
                            ? session!.cwd
                            : 'Terminal ready',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onTerminate != null)
                  IconButton(
                    tooltip: 'Terminate',
                    onPressed: session?.isRunning == true
                        ? widget.onTerminate
                        : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final rows = (constraints.maxHeight / 18).floor().clamp(10, 60);
                final cols = (constraints.maxWidth / 8).floor().clamp(40, 160);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (session != null &&
                      session.isInteractive &&
                      session.usesTty &&
                      session.isRunning &&
                      widget.onResize != null) {
                    widget.onResize!(rows, cols);
                  }
                });
                return Scrollbar(
                  controller: _verticalOutputController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalOutputController,
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Scrollbar(
                      controller: _horizontalOutputController,
                      thumbVisibility: true,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _horizontalOutputController,
                        primary: false,
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth - 24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (session != null &&
                                  session.stdout.isNotEmpty)
                                _MonospaceOutputView(
                                  text: session.stdout,
                                  scrollable: false,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    height: 1.2,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              if (session == null)
                                Text(
                                  '\$ Enter a command below to start a shell session.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              if (session != null &&
                                  session.stdout.isEmpty &&
                                  session.stderr.isEmpty)
                                Text(
                                  session.isRunning
                                      ? 'Waiting for output...'
                                      : 'Command produced no output.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              if (session != null &&
                                  session.outputCapReached) ...<Widget>[
                                const SizedBox(height: 10),
                                Text(
                                  'Output cap reached',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: scheme.secondary,
                                  ),
                                ),
                              ],
                              if (session != null &&
                                  session.stderr.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 10),
                                _MonospaceOutputView(
                                  text: session.stderr,
                                  scrollable: false,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: scheme.error,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '\$',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('command-shell-input'),
                    controller: widget.commandController,
                    onSubmitted: (_) => widget.onSubmit(),
                    textInputAction: TextInputAction.send,
                    maxLines: 1,
                    cursorColor: scheme.primary,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: interactiveInput
                          ? 'stdin to active process'
                          : 'type a command and press Enter',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: scheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurface,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandHistoryPanel extends StatelessWidget {
  const _CommandHistoryPanel({
    required this.controller,
    required this.canRepeat,
    required this.onRepeat,
  });

  final AppController controller;
  final bool canRepeat;
  final ValueChanged<CommandSession> onRepeat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFinishedSessions = controller.commandSessions.any(
      (session) => !session.isRunning,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Shell history', style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: 'Clear finished runs',
                onPressed: hasFinishedSessions
                    ? controller.clearFinishedCommandSessions
                    : null,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                icon: const Icon(Icons.delete_outline),
              ),
              if (controller.commandSessions.isNotEmpty)
                Text(
                  '${controller.commandSessions.length}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: controller.commandSessions.isEmpty
                ? Center(
                    child: Text(
                      'No shell commands yet.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    itemCount: controller.commandSessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final session = controller.commandSessions[index];
                      final selected =
                          controller.activeCommandSession?.id == session.id;
                      return _CommandSessionCard(
                        session: session,
                        selected: selected,
                        canRepeat: canRepeat,
                        onRepeat: () => onRepeat(session),
                        onTap: () => controller.selectCommandSession(session.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SavedCommandPanel extends StatelessWidget {
  const _SavedCommandPanel({
    required this.controller,
    required this.onTapCommand,
  });

  final AppController controller;
  final ValueChanged<RecentCommand> onTapCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Saved', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (controller.recentCommands.isNotEmpty)
                Text(
                  '${controller.recentCommands.length}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (controller.recentCommands.isEmpty)
            Text(
              'Saved commands appear here after you run them.',
              style: theme.textTheme.bodySmall,
            )
          else
            ...controller.recentCommands.map((recent) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecentCommandCard(
                  command: recent,
                  onTap: () => onTapCommand(recent),
                  onRemove: () => controller.removeRecentCommand(recent),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class ThreadHistorySheet extends StatelessWidget {
  const ThreadHistorySheet({
    super.key,
    required this.controller,
    required this.onCreateThread,
  });

  final AppController controller;
  final Future<void> Function() onCreateThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Container(
          margin: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(22),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom:
                    MediaQuery.paddingOf(context).bottom +
                    MediaQuery.viewInsetsOf(context).bottom +
                    20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Threads',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'New thread',
                        onPressed: onCreateThread,
                        icon: const Icon(Icons.add),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: controller.isLoadingHistory
                            ? null
                            : () => controller.loadThreadHistory(reset: true),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (controller.threadHistoryError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      controller.threadHistoryError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.7,
                    child:
                        controller.threadHistory.isEmpty &&
                            controller.isLoadingHistory
                        ? const Center(child: CircularProgressIndicator())
                        : controller.threadHistory.isEmpty
                        ? Center(
                            child: Text(
                              'No saved threads were returned by the server.',
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount:
                                controller.threadHistory.length +
                                (controller.hasMoreThreadHistory ? 1 : 0),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (BuildContext context, int index) {
                              if (index >= controller.threadHistory.length) {
                                return OutlinedButton(
                                  onPressed: controller.isLoadingHistory
                                      ? null
                                      : controller.loadThreadHistory,
                                  child: Text(
                                    controller.isLoadingHistory
                                        ? 'Loading'
                                        : 'Load more',
                                  ),
                                );
                              }

                              final thread = controller.threadHistory[index];
                              return _ThreadTile(
                                controller: controller,
                                thread: thread,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FileBrowserSheet extends StatefulWidget {
  const FileBrowserSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<FileBrowserSheet> createState() => _FileBrowserSheetState();
}

class _FileBrowserSheetState extends State<FileBrowserSheet> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(
      text: widget.controller.fileBrowserPath,
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final controller = widget.controller;
        if (_pathController.text != controller.fileBrowserPath) {
          _pathController.value = _pathController.value.copyWith(
            text: controller.fileBrowserPath,
            selection: TextSelection.collapsed(
              offset: controller.fileBrowserPath.length,
            ),
          );
        }
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            margin: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(22),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
                ),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Files',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Up',
                            onPressed: controller.fileBrowserPath == '/'
                                ? null
                                : controller.navigateToParentDirectory,
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _pathController,
                              decoration: const InputDecoration(
                                labelText: 'Absolute path',
                              ),
                              onSubmitted: controller.loadDirectory,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: controller.isLoadingFiles
                                ? null
                                : () => controller.loadDirectory(
                                    _pathController.text,
                                  ),
                            child: const Text('Open'),
                          ),
                        ],
                      ),
                      if (controller.fileBrowserError != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          controller.fileBrowserError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Expanded(child: _buildFileList(theme, controller)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadFile(BuildContext context, String filePath) async {
    try {
      await widget.controller.saveFileToDevice(filePath);
    } catch (error) {
      // Download errors are shown in the download center.
    }
  }

  Future<void> _cancelDownload(String filePath) async {
    await widget.controller.cancelFileDownload(filePath);
  }

  Future<void> _openPreviewForFile(String filePath, {int? line}) async {
    await widget.controller.openFile(filePath, highlightedLine: line);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return FilePreviewPage(
            controller: widget.controller,
            onDownload: _downloadFile,
            onCancelDownload: _cancelDownload,
          );
        },
      ),
    );
  }

  Widget _buildFileList(ThemeData theme, AppController controller) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: controller.isLoadingFiles && controller.fileBrowserEntries.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: controller.fileBrowserEntries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final entry = controller.fileBrowserEntries[index];
                final fullPath = controller.joinFileBrowserPath(entry.fileName);
                return _FileEntryTile(
                  controller: controller,
                  entry: entry,
                  isDownloading: controller.isFileDownloading(fullPath),
                  downloadStatus: controller.fileDownloadStatus(fullPath),
                  onOpenFile: entry.isFile
                      ? () => _openPreviewForFile(fullPath)
                      : null,
                  onDownload: entry.isFile
                      ? () => _downloadFile(context, fullPath)
                      : null,
                  onCancelDownload: entry.isFile
                      ? () => _cancelDownload(fullPath)
                      : null,
                );
              },
            ),
    );
  }
}

class FilePreviewPage extends StatefulWidget {
  const FilePreviewPage({
    super.key,
    required this.controller,
    required this.onDownload,
    required this.onCancelDownload,
  });

  final AppController controller;
  final Future<void> Function(BuildContext context, String filePath) onDownload;
  final Future<void> Function(String filePath) onCancelDownload;

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  late final TextEditingController _editorController = TextEditingController();
  String? _editingPath;
  bool _isEditing = false;

  @override
  void dispose() {
    _editorController.dispose();
    super.dispose();
  }

  void _syncEditorFromController() {
    final controller = widget.controller;
    final path = controller.selectedFilePath;
    if (!_isEditing &&
        controller.selectedFileIsHumanReadable &&
        path != null &&
        path.isNotEmpty &&
        _editingPath != path) {
      _editingPath = path;
      _editorController.text = controller.selectedFileContent ?? '';
    }
    if (!_isEditing && !controller.selectedFileIsHumanReadable) {
      _editingPath = null;
      _editorController.clear();
    }
  }

  Future<void> _saveFile(BuildContext context) async {
    try {
      await widget.controller.saveOpenedFileContent(_editorController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _isEditing = false;
      });
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      final message = widget.controller.filePreviewSaveError?.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            message == null || message.isEmpty
                ? 'Unable to save the file.'
                : message,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        _syncEditorFromController();
        final controller = widget.controller;
        final filePath = controller.selectedFilePath;
        final canEdit =
            controller.selectedFileIsHumanReadable &&
            filePath != null &&
            filePath.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              filePath == null || filePath.isEmpty ? 'File preview' : filePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: <Widget>[
              if (canEdit)
                TextButton(
                  onPressed: controller.isSavingFilePreview
                      ? null
                      : () {
                          if (_isEditing) {
                            _saveFile(context);
                          } else {
                            setState(() {
                              _isEditing = true;
                              _editingPath = filePath;
                              _editorController.text =
                                  controller.selectedFileContent ?? '';
                            });
                          }
                        },
                  child: Text(_isEditing ? 'Save' : 'Edit'),
                ),
              if (canEdit && _isEditing)
                TextButton(
                  onPressed: controller.isSavingFilePreview
                      ? null
                      : () {
                          setState(() {
                            _isEditing = false;
                            _editorController.text =
                                controller.selectedFileContent ?? '';
                          });
                        },
                  child: const Text('Cancel'),
                ),
              if (filePath != null && filePath.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: controller.isFileDownloading(filePath)
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: _DownloadProgressPanel(
                            status: controller.fileDownloadStatus(filePath),
                            onCancel: () => widget.onCancelDownload(filePath),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: controller.selectedFileBytes == null
                              ? null
                              : () => widget.onDownload(context, filePath),
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Download'),
                        ),
                ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              child: _FilePreviewBody(
                controller: controller,
                isEditing: _isEditing,
                editorController: _editorController,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FilePreviewBody extends StatefulWidget {
  const _FilePreviewBody({
    required this.controller,
    required this.isEditing,
    required this.editorController,
  });

  final AppController controller;
  final bool isEditing;
  final TextEditingController editorController;

  @override
  State<_FilePreviewBody> createState() => _FilePreviewBodyState();
}

class _FilePreviewBodyState extends State<_FilePreviewBody> {
  static const double _lineHeight = 22;
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  int? _lastScrolledLine;

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    if (controller.isLoadingFilePreview) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.selectedFilePath == null) {
      return Center(
        child: Text(
          'Select a file to preview it.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    if (controller.selectedFileIsHumanReadable) {
      if (widget.isEditing) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (controller.filePreviewSaveError != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Text(
                  controller.filePreviewSaveError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
            Expanded(
              child: TextField(
                controller: widget.editorController,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                  hintText: 'Edit file contents',
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        );
      }
      final lines = (controller.selectedFileContent ?? '').split('\n');
      final highlightedLine = controller.selectedFileHighlightedLine;
      if (highlightedLine != null &&
          highlightedLine > 0 &&
          highlightedLine <= lines.length &&
          _lastScrolledLine != highlightedLine) {
        _lastScrolledLine = highlightedLine;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_verticalController.hasClients) {
            return;
          }
          final targetOffset = ((highlightedLine - 1) * _lineHeight) - 80;
          _verticalController.animateTo(
            targetOffset.clamp(0, _verticalController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        });
      }
      return Scrollbar(
        controller: _horizontalController,
        thumbVisibility: true,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 720,
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _verticalController,
                itemCount: lines.length,
                itemBuilder: (BuildContext context, int index) {
                  final lineNumber = index + 1;
                  final isHighlighted = highlightedLine == lineNumber;
                  return Container(
                    key: isHighlighted
                        ? const ValueKey<String>('highlighted-file-line')
                        : null,
                    height: _lineHeight,
                    color: isHighlighted
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : null,
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 56,
                          child: Text(
                            '$lineNumber',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: isHighlighted
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SelectableText(
                            lines[index],
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.3,
                              color: isHighlighted
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.insert_drive_file_outlined,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'This file is not previewed as text.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Use Download to save it locally and open it with an appropriate app.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (controller.selectedFileBytes != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                '${controller.selectedFileBytes!.length} bytes',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FileEntryTile extends StatelessWidget {
  const _FileEntryTile({
    required this.controller,
    required this.entry,
    required this.isDownloading,
    required this.downloadStatus,
    this.onOpenFile,
    this.onDownload,
    this.onCancelDownload,
  });

  final AppController controller;
  final FileSystemEntry entry;
  final bool isDownloading;
  final FileDownloadStatus? downloadStatus;
  final VoidCallback? onOpenFile;
  final VoidCallback? onDownload;
  final VoidCallback? onCancelDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullPath = controller.joinFileBrowserPath(entry.fileName);
    final selected = controller.selectedFilePath == fullPath;
    return InkWell(
      onTap: () {
        if (entry.isDirectory) {
          controller.loadDirectory(fullPath);
        } else if (entry.isFile) {
          onOpenFile?.call();
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  entry.isDirectory
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (entry.isFile && onDownload != null) ...<Widget>[
                  const SizedBox(width: 8),
                  isDownloading
                      ? IconButton(
                          tooltip: 'Cancel download',
                          onPressed: onCancelDownload,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                        )
                      : IconButton(
                          tooltip: 'Download',
                          onPressed: onDownload,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.download_outlined, size: 18),
                        ),
                ],
              ],
            ),
            if (isDownloading && downloadStatus != null) ...<Widget>[
              const SizedBox(height: 8),
              _DownloadProgressDetails(status: downloadStatus!),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadProgressPanel extends StatelessWidget {
  const _DownloadProgressPanel({required this.status, required this.onCancel});

  final FileDownloadStatus? status;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: _DownloadProgressDetails(status: status)),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Cancel download',
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _DownloadProgressDetails extends StatelessWidget {
  const _DownloadProgressDetails({required this.status});

  final FileDownloadStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (status?.progress ?? 0).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 6),
        Text(_formatTransferSize(status), style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          _formatEta(status),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _formatTransferSize(FileDownloadStatus? status) {
  final received = _formatMegabytes(status?.receivedBytes ?? 0);
  final totalBytes = status?.totalBytes;
  final total = totalBytes == null ? '--' : _formatMegabytes(totalBytes);
  return '$received MB / $total MB';
}

String _formatEta(FileDownloadStatus? status) {
  final eta = status?.eta;
  if (eta == null) {
    return 'Estimating time remaining...';
  }
  if (eta == Duration.zero) {
    return 'Almost done';
  }
  final seconds = eta.inSeconds;
  if (seconds < 60) {
    return '${seconds}s remaining';
  }
  final minutes = eta.inMinutes;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return '${minutes}m ${remainingSeconds}s remaining';
  }
  final hours = eta.inHours;
  final remainingMinutes = minutes % 60;
  return '${hours}h ${remainingMinutes}m remaining';
}

String _formatMegabytes(int bytes) {
  final megabytes = bytes / (1024 * 1024);
  return megabytes.toStringAsFixed(megabytes >= 10 ? 0 : 1);
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.controller, required this.thread});

  final AppController controller;
  final ThreadSummary thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpening = controller.openingThreadId == thread.id;
    final isFavorite = controller.isThreadFavorite(thread.id);
    final hasActiveTurn = controller.threadHasActiveTurn(thread.id);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    if (hasActiveTurn)
                      Container(
                        key: ValueKey<String>('thread-active-turn-${thread.id}'),
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        thread.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isFavorite ? 'Unfavorite thread' : 'Favorite thread',
                onPressed: () => controller.toggleFavoriteThread(thread.id),
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  color: isFavorite ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            thread.preview.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (thread.updatedAt != null)
                _ThreadMeta(
                  label: 'Updated',
                  value: _formatDate(thread.updatedAt!),
                ),
              if (thread.cwd.isNotEmpty)
                _ThreadMeta(label: 'Cwd', value: thread.cwd),
              if (thread.agentNickname != null &&
                  thread.agentNickname!.isNotEmpty)
                _ThreadMeta(label: 'Agent', value: thread.agentNickname!),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isOpening
                  ? null
                  : () async {
                      await controller.resumeThreadFromHistory(thread.id);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
              child: Text(isOpening ? 'Opening' : 'Open thread'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value;
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String two(int n) {
    return n.toString().padLeft(2, '0');
  }
}

class _ThreadMeta extends StatelessWidget {
  const _ThreadMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
