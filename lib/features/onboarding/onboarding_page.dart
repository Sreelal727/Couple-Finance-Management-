import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../sync/sync_service.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _name = TextEditingController();
  String _color = MemberColors.toHex(MemberColors.palette.first);
  bool _busy = false;

  Future<void> _continue() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final repo = context.read<Repository>();
    final data = context.read<AppData>();
    final sync = context.read<SyncService>();
    await repo.setUp(myName: name, colorHex: _color);
    await data.reload();
    await sync.init();
    await sync.startNetwork();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            Icon(Icons.favorite_rounded, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Duo Finance',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your expenses stay on your phone. Your partner\'s stay on theirs. When the two phones are together, they sync directly. No cloud, no account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Your name', hintText: 'Sreelal'),
              onSubmitted: (_) => _continue(),
            ),
            const SizedBox(height: 20),
            Text('Your colour', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ColorPickerRow(selected: _color, onSelected: (c) => setState(() => _color = c)),
            const SizedBox(height: 32),
            FilledButton(onPressed: _busy ? null : _continue, child: const Text('Get started')),
            const SizedBox(height: 12),
            Text(
              'Next, pair with your partner\'s phone from the Sync screen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
