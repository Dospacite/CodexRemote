library workspace_home_page;

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

part 'home_page/action_bar.dart';
part 'home_page/agent_markdown_message.dart';
part 'home_page/approval_panel.dart';
part 'home_page/composer_attachment_bar.dart';
part 'home_page/entry_tile.dart';
part 'home_page/expandable_entry_body.dart';
part 'home_page/git_diff_view.dart';
part 'home_page/message_content_text.dart';
part 'home_page/message_reference_support.dart';
part 'home_page/monospace_output_view.dart';
part 'home_page/pending_message_sheen.dart';
part 'home_page/prepared_image_attachment.dart';
part 'home_page/queued_prompt_bar.dart';
part 'home_page/top_bar_title.dart';

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
