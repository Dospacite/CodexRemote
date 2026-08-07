part of workspace_home_page;

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
