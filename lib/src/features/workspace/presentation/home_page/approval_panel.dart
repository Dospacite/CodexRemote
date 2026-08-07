part of workspace_home_page;

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
