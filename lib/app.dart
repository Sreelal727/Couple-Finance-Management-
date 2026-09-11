import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/theme.dart';
import 'data/models.dart';
import 'data/repository.dart';
import 'features/home/shell.dart';
import 'features/lock/lock_screen.dart';
import 'features/lock/lock_service.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/shared/app_data.dart';
import 'features/shared/attachment_picker.dart';
import 'features/shared/widgets.dart';
import 'features/sms_inbox/sms_inbox_page.dart';
import 'features/transactions/add_txn_page.dart';
import 'sms/notifications.dart';
import 'sms/sms_parser.dart';
import 'sms/sms_service.dart';
import 'sync/sync_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class DuoApp extends StatefulWidget {
  const DuoApp({super.key});

  @override
  State<DuoApp> createState() => _DuoAppState();
}

class _DuoAppState extends State<DuoApp> with WidgetsBindingObserver {
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Notifications.onTap = _onNotificationTap;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfReady());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    super.dispose();
  }

  /// Everything that needs a set-up identity: network, SMS listener, intents.
  Future<void> _startIfReady() async {
    final repo = context.read<Repository>();
    if (_started || !repo.isSetUp) return;
    _started = true;
    final sync = context.read<SyncService>();
    final sms = context.read<SmsService>();
    await sync.startNetwork();
    sms.startListening();

    // Notification tapped while the app was closed.
    try {
      final launch = await Notifications.plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _onNotificationTap(launch!.notificationResponse);
      }
    } catch (_) {}

    // Screenshots / text / sync files shared into the app.
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        await _onShared(initial);
        await ReceiveSharingIntent.instance.reset();
      }
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(_onShared);
    } catch (_) {}

    // Long-press launcher shortcut.
    try {
      const quick = QuickActions();
      await quick.initialize((type) {
        if (type == 'add_expense') _openAdd(const TxnPrefill());
      });
      await quick.setShortcutItems(const [
        ShortcutItem(type: 'add_expense', localizedTitle: 'Add expense', icon: 'ic_launcher'),
      ]);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<LockService>();
    final sync = context.read<SyncService>();
    final data = context.read<AppData>();
    switch (state) {
      case AppLifecycleState.resumed:
        lock.onForeground();
        if (_started) {
          sync.startNetwork().then((_) => sync.announce());
          data.reload();
        }
      case AppLifecycleState.paused:
        lock.onBackground();
      default:
        break;
    }
  }

  // --------------------------------------------------------------- intents

  void _onNotificationTap(NotificationResponse? r) {
    final payload = r?.payload;
    if (payload == null || !payload.startsWith('sms:')) return;
    if (r?.actionId == Notifications.actionDismiss) return;
    _openSms(payload.substring(4));
  }

  Future<void> _openSms(String smsId) async {
    final repo = context.read<Repository>();
    final item = await repo.smsById(smsId);
    final ctx = navigatorKey.currentContext;
    if (item == null || ctx == null || !ctx.mounted) return;
    if (item.status != SmsStatus.pending) {
      showSnack(ctx, 'That transaction was already handled');
      return;
    }
    await addFromSms(ctx, item);
  }

  Future<void> _onShared(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final sync = context.read<SyncService>();
    final images = <PendingImage>[];
    String? text;
    for (final f in files) {
      switch (f.type) {
        case SharedMediaType.image:
          try {
            final bytes = await File(f.path).readAsBytes();
            images.add(
              PendingImage(
                bytes,
                mime: (f.mimeType == 'image/png' || f.path.toLowerCase().endsWith('.png')) ? 'image/png' : 'image/jpeg',
              ),
            );
          } catch (_) {}
        case SharedMediaType.text:
        case SharedMediaType.url:
          text = f.message ?? f.path;
        case SharedMediaType.file:
          if (f.path.endsWith('.duosync') || (f.mimeType ?? '').contains('octet-stream')) {
            final ctx = navigatorKey.currentContext;
            try {
              final r = await sync.importBundle(await File(f.path).readAsBytes());
              if (ctx != null && ctx.mounted) showSnack(ctx, 'Imported ${r.applied} changes from ${r.from.name}');
            } catch (e) {
              if (ctx != null && ctx.mounted) showSnack(ctx, e.toString());
            }
            return;
          }
        case SharedMediaType.video:
          break;
      }
    }
    if (images.isEmpty && text == null) return;
    // A pasted UPI confirmation often parses like a bank SMS.
    final parsed = text == null ? null : SmsParser.parse('SHARE', text);
    if (!mounted) return;
    _openAdd(
      TxnPrefill(
        type: parsed?.direction == SmsDirection.credit ? TxnType.income : TxnType.expense,
        amountPaise: parsed?.amountPaise,
        merchant: parsed?.merchant,
        title: parsed == null ? (text != null && text.length <= 60 ? text : null) : null,
        source: TxnSource.share,
        images: images,
      ),
    );
  }

  void _openAdd(TxnPrefill prefill) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    AddTxnPage.open(ctx, prefill: prefill);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    return MaterialApp(
      title: 'Duo Finance',
      navigatorKey: navigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: repo.isSetUp
          ? const LockGate(child: Shell())
          : OnboardingPage(
              onDone: () {
                setState(() {});
                _startIfReady();
              },
            ),
    );
  }
}
