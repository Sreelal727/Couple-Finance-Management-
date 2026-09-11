import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'lock_service.dart';

/// Wraps the app; shows the PIN pad whenever [LockService.locked] is true.
class LockGate extends StatelessWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<LockService>();
    return Stack(
      children: [
        child,
        if (lock.locked) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entry = '';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<LockService>().tryBiometric());
  }

  void _press(String d) {
    if (_entry.length >= 6) return;
    setState(() {
      _entry += d;
      _error = false;
    });
    if (_entry.length >= 4) {
      final lock = context.read<LockService>();
      if (lock.verifyPin(_entry)) return;
      if (_entry.length == 6) {
        setState(() {
          _error = true;
          _entry = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lock = context.watch<LockService>();
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Enter PIN', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                6,
                (i) => Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _entry.length
                        ? (_error ? scheme.error : scheme.primary)
                        : scheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 24,
              child: _error ? Text('Wrong PIN', style: TextStyle(color: scheme.error)) : const SizedBox.shrink(),
            ),
            _Pad(
              onDigit: _press,
              onBackspace: () => setState(() {
                if (_entry.isNotEmpty) _entry = _entry.substring(0, _entry.length - 1);
              }),
              onBiometric: lock.biometricEnabled ? () => lock.tryBiometric() : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({required this.onDigit, required this.onBackspace, this.onBiometric});
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap) => SizedBox(
      width: 84,
      height: 72,
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
    final style = Theme.of(context).textTheme.headlineSmall;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in ['123', '456', '789'])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row.split('')) key(Text(d, style: style), () => onDigit(d))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key(Icon(Icons.fingerprint_rounded, color: onBiometric == null ? Colors.transparent : null), onBiometric),
            key(Text('0', style: style), () => onDigit('0')),
            key(const Icon(Icons.backspace_outlined), onBackspace),
          ],
        ),
      ],
    );
  }
}

/// Dialog used from settings to choose a new PIN (asks twice).
Future<String?> askNewPin(BuildContext context) async {
  String? first;
  while (true) {
    final pin = await _askPinOnce(context, first == null ? 'Choose a 4–6 digit PIN' : 'Enter it again');
    if (pin == null) return null;
    if (first == null) {
      first = pin;
      continue;
    }
    if (pin == first) return pin;
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PINs didn't match, try again")));
    first = null;
  }
}

Future<String?> _askPinOnce(BuildContext context, String title) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(hintText: 'PIN'),
        onSubmitted: (v) {
          if (v.length >= 4) Navigator.pop(ctx, v);
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (ctrl.text.length >= 4) Navigator.pop(ctx, ctrl.text);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
