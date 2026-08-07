import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:super_clipboard/super_clipboard.dart';

import '../../../app_controller.dart';
import '../../../models.dart';
import '../../automations/presentation/automation_pages.dart';
import '../../commands/presentation/command_center_page.dart';
import '../../downloads/presentation/download_center_page.dart';
import '../../files/presentation/file_pages.dart';
import '../../settings/presentation/settings_page.dart';
import '../../threads/presentation/thread_history_sheet.dart';

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
  bool _isOpeningThreadHistory = false;

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
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                18,
                                16,
                                24,
                              ),
                              itemBuilder: (BuildContext context, int index) {
                                final entry =
                                    controller.entries[controller
                                            .entries
                                            .length -
                                        1 -
                                        index];
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
                                  onPressed: () =>
                                      _pickReasoningEffort(context, controller),
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
                                    controller.isSteering
                                        ? 'Steering...'
                                        : 'Steer',
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    ElevatedButton(
                                      onPressed: () => _sendPrompt(controller),
                                      child: Text(
                                        controller.hasActiveTurn
                                            ? 'Queue'
                                            : 'Send',
                                      ),
                                    ),
                                    if (controller.composerMetaLeftText !=
                                            null ||
                                        controller.composerMetaRightText !=
                                            null) ...<Widget>[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: Builder(
                                              builder: (BuildContext context) {
                                                final text = Text(
                                                  controller
                                                          .composerMetaLeftText ??
                                                      '',
                                                  key: const ValueKey<String>(
                                                    'composer-meta-left-text',
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.left,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
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
                                                  onTap: () =>
                                                      _showRateLimitMenu(
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
                                          if (controller
                                                      .composerMetaRightText !=
                                                  null &&
                                              controller
                                                  .composerMetaRightText!
                                                  .isNotEmpty) ...<Widget>[
                                            const SizedBox(width: 8),
                                            if (controller
                                                    .contextUsagePercent !=
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
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.right,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
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
                                                controller
                                                    .composerMetaRightText!,
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
    if (_isOpeningThreadHistory) {
      return;
    }
    _isOpeningThreadHistory = true;
    _dismissComposerFocus();
    try {
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
    } finally {
      _isOpeningThreadHistory = false;
    }
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
  const _MonospaceOutputView({required this.text, required this.style});

  final String text;
  final TextStyle? style;

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
