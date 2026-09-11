import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'features/lock/lock_service.dart';
import 'features/shared/app_data.dart';
import 'sms/notifications.dart';
import 'sms/sms_service.dart';
import 'sync/attachment_store.dart';
import 'sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await AppDatabase.open();
  final repo = Repository(db);
  await repo.load();
  await repo.loadColumnInfo();
  final prefs = await SharedPreferences.getInstance();

  final attachments = AttachmentStore(repo);
  final sync = SyncService(repo: repo, attachments: attachments, prefs: prefs);
  await sync.init();
  final sms = SmsService(repo: repo, prefs: prefs);
  final lock = LockService(prefs);
  final data = AppData(repo);
  if (repo.isSetUp) await data.reload();

  await Notifications.init(onBackgroundTap: notificationBackgroundTap);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: repo),
        ChangeNotifierProvider.value(value: data),
        ChangeNotifierProvider.value(value: sync),
        ChangeNotifierProvider.value(value: sms),
        ChangeNotifierProvider.value(value: lock),
        Provider.value(value: attachments),
        Provider.value(value: prefs),
      ],
      child: const DuoApp(),
    ),
  );
}
