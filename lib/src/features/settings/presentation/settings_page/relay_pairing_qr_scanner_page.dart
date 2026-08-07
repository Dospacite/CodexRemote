part of settings_page;

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
