part of automation_pages;

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
