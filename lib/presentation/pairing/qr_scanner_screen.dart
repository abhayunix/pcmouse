import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final _ipController = TextEditingController(text: '192.168.1.100');
  final _portController = TextEditingController(text: '8443');
  final _codeController = TextEditingController();
  bool _isManual = false;

  @override
  void dispose() {
    _controller.dispose();
    _ipController.dispose();
    _portController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final String raw = barcode.rawValue!;
        // Expected format: pcmouse://pair?ip=192.168.1.100&port=8443&code=123456&token=...
        if (raw.startsWith('pcmouse://pair')) {
          final uri = Uri.parse(raw);
          final ip = uri.queryParameters['ip'] ?? '';
          final port = int.tryParse(uri.queryParameters['port'] ?? '8443') ?? 8443;
          final code = uri.queryParameters['code'] ?? '';

          _controller.stop();
          Navigator.pop(context, {
            'ip': ip,
            'port': port,
            'code': code,
          });
          break;
        }
      }
    }
  }

  void _submitManual() {
    if (_ipController.text.isNotEmpty && _codeController.text.isNotEmpty) {
      Navigator.pop(context, {
        'ip': _ipController.text.trim(),
        'port': int.tryParse(_portController.text.trim()) ?? 8443,
        'code': _codeController.text.trim(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isManual ? 'Manual Pairing' : 'Scan PC QR Code'),
        actions: [
          IconButton(
            icon: Icon(_isManual ? Icons.qr_code_scanner : Icons.edit),
            tooltip: _isManual ? 'Switch to Camera' : 'Manual Entry',
            onPressed: () {
              setState(() {
                _isManual = !_isManual;
              });
            },
          ),
        ],
      ),
      body: _isManual ? _buildManualForm() : _buildScannerView(),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00E5FF), width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(180),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Point camera at QR code on PC Mouse Agent window',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualForm() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'PC IP Address',
              prefixIcon: Icon(Icons.wifi),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.datetime,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port',
              prefixIcon: Icon(Icons.settings_ethernet),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: '6-Digit Pairing PIN',
              prefixIcon: Icon(Icons.pin),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            onPressed: _submitManual,
            icon: const Icon(Icons.link),
            label: const Text('Connect & Authorize', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
