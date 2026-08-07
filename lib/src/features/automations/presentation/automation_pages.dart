// ignore_for_file: deprecated_member_use

library automation_pages;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_controller.dart';
import '../../../models.dart';

part 'automation_pages/automation_editor_page.dart';
part 'automation_pages/automation_node_editor_page.dart';
part 'automation_pages/automation_page_views.dart';
part 'automation_pages/automation_path_picker_page.dart';
part 'automation_pages/automation_support.dart';

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
        return Theme(
          data: theme.copyWith(
            splashFactory: InkRipple.splashFactory,
            useMaterial3: false,
          ),
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Automations'),
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showAllAutomations = !_showAllAutomations;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _showAllAutomations ? Icons.list : Icons.filter_alt,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(_showAllAutomations ? 'All' : 'Current'),
                        ],
                      ),
                    ),
                  ),
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
