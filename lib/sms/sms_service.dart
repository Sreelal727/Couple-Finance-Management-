import 'package:another_telephony/telephony.dart' hide SmsStatus;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'notifications.dart';
import 'sms_parser.dart';

/// Runs in the background isolate when an SMS arrives and the app is not in
/// the foreground. Opens its own database handle, parses, stores and notifies.
@pragma('vm:entry-point')
Future<void> smsBackgroundHandler(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = await AppDatabase.open();
    final repo = Repository(db);
    await repo.load();
    if (repo.isSetUp) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(SmsService.enabledKey) ?? false) {
        await Notifications.init(onBackgroundTap: notificationBackgroundTap);
        await SmsService.ingest(
          repo,
          message.address ?? '',
          message.body ?? '',
          receivedAt: message.date ?? Dates.nowMs(),
          notify: true,
        );
      }
    }
    await db.close();
  } catch (e, st) {
    debugPrint('sms background handler failed: $e\n$st');
  }
}

/// Handles the "Not an expense" notification action without opening the app.
@pragma('vm:entry-point')
Future<void> notificationBackgroundTap(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  final payload = response.payload;
  if (response.actionId != Notifications.actionDismiss || payload == null || !payload.startsWith('sms:')) return;
  try {
    final db = await AppDatabase.open();
    final repo = Repository(db);
    await repo.load();
    final item = await repo.smsById(payload.substring(4));
    if (item != null) await repo.updateSms(item.copyWith(status: SmsStatus.dismissed));
    await db.close();
  } catch (e) {
    debugPrint('dismiss failed: $e');
  }
}

class SmsService extends ChangeNotifier {
  SmsService({required this.repo, required this.prefs});

  final Repository repo;
  final SharedPreferences prefs;
  final Telephony _telephony = Telephony.instance;

  static const enabledKey = 'sms_capture_enabled';
  bool _listening = false;

  bool get enabled => prefs.getBool(enabledKey) ?? false;

  Future<bool> hasPermission() async {
    try {
      return await _telephony.requestSmsPermissions ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Turns capture on: asks for SMS + notification permission, starts the
  /// listener, and does a first scan of the last [scanDays] days.
  Future<bool> enable({int scanDays = 30}) async {
    final ok = await hasPermission();
    if (!ok) return false;
    await Notifications.requestPermission();
    await prefs.setBool(enabledKey, true);
    startListening();
    await scanInbox(days: scanDays);
    notifyListeners();
    return true;
  }

  Future<void> disable() async {
    await prefs.setBool(enabledKey, false);
    notifyListeners();
  }

  void startListening() {
    if (_listening || !enabled) return;
    _listening = true;
    _telephony.listenIncomingSms(
      onNewMessage: (msg) =>
          ingest(repo, msg.address ?? '', msg.body ?? '', receivedAt: msg.date ?? Dates.nowMs(), notify: true),
      onBackgroundMessage: smsBackgroundHandler,
      listenInBackground: true,
    );
  }

  /// Reads the inbox and turns every bank alert from the last [days] days
  /// into a pending item (deduplicated, no notifications). Returns how many
  /// new items were added.
  Future<int> scanInbox({int days = 30}) async {
    final since = Dates.nowMs() - days * 24 * 3600 * 1000;
    List<SmsMessage> messages;
    try {
      messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.DATE).greaterThan('$since'),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );
    } catch (_) {
      return 0;
    }
    var added = 0;
    for (final m in messages) {
      final inserted = await ingest(repo, m.address ?? '', m.body ?? '', receivedAt: m.date ?? since, notify: false);
      if (inserted) added++;
    }
    notifyListeners();
    return added;
  }

  /// Shared by foreground, background and inbox scan. Returns true if a new
  /// pending item was stored.
  static Future<bool> ingest(
    Repository repo,
    String sender,
    String body, {
    required int receivedAt,
    required bool notify,
  }) async {
    final parsed = SmsParser.parse(sender, body);
    if (parsed == null) return false;
    final h = SmsParser.hash(sender, body);
    if (await repo.txnExistsForSms(h)) return false;
    final item = SmsItem(
      id: newId(),
      sender: sender,
      body: SmsParser.normalize(body),
      bodyHash: h,
      receivedAt: receivedAt,
      amountPaise: parsed.amountPaise,
      direction: parsed.direction,
      merchant: parsed.merchant,
      accountTail: parsed.accountTail,
      reference: parsed.reference,
      status: SmsStatus.pending,
      txnId: null,
    );
    final inserted = await repo.insertSms(item);
    if (inserted && notify) {
      final what = parsed.direction == SmsDirection.debit ? 'paid' : 'received';
      final who = parsed.merchant == null
          ? ''
          : (parsed.direction == SmsDirection.debit ? ' to ${parsed.merchant}' : ' from ${parsed.merchant}');
      await Notifications.showSmsCandidate(
        smsId: item.id,
        title: '${Money.format(parsed.amountPaise)} $what$who',
        body: 'Tap to add it with a name and purpose',
      );
    }
    return inserted;
  }
}
