import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../sync/sync_service.dart';
import '../shared/widgets.dart';
import 'sync_page.dart';

class PairShowPage extends StatelessWidget {
  const PairShowPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairShowPage()));

  @override
  Widget build(BuildContext context) {
    final sync = context.read<SyncService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Pairing code')),
      body: FutureBuilder<String>(
        future: sync.pairingPayload(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final payload = snap.data!;
          final code = base64Url.encode(utf8.encode(payload));
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'On your partner\'s phone open Sync › Scan partner\'s code and point it here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: QrImageView(data: payload, size: 260, backgroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'This code contains the secret key that encrypts all sync traffic. Only share it with your partner.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy as text (if the camera won\'t work)'),
                onPressed: () => copyToClipboard(context, code),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PairScanPage extends StatefulWidget {
  const PairScanPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairScanPage()));

  @override
  State<PairScanPage> createState() => _PairScanPageState();
}

class _PairScanPageState extends State<PairScanPage> {
  final _controller = MobileScannerController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    if (_busy) return;
    setState(() => _busy = true);
    final sync = context.read<SyncService>();
    try {
      var payload = raw.trim();
      if (!payload.startsWith('{')) {
        payload = utf8.decode(base64Url.decode(base64Url.normalize(payload)));
      }
      final r = await sync.completePairing(payload);
      if (!mounted) return;
      showSnack(
        context,
        r == null
            ? 'Paired! Sync will run when both phones are on the same network.'
            : 'Paired and synced: ${r.summary}',
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showSnack(context, e.toString());
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan pairing code'),
        actions: [
          TextButton(
            onPressed: () async {
              final v = await askText(context, 'Paste pairing code', okLabel: 'Pair');
              if (v != null && v.isNotEmpty) _handle(v);
            },
            child: const Text('Paste'),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final v = capture.barcodes.firstOrNull?.rawValue;
              if (v != null) _handle(v);
            },
            errorBuilder: (ctx, error) => EmptyState(
              icon: Icons.no_photography_rounded,
              title: 'Camera not available',
              subtitle: 'Use Paste instead: copy the code as text on the other phone and send it here.',
            ),
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Text(
              'Point at the QR code on your partner\'s phone',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4, color: Colors.black.withValues(alpha: 0.6))],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
