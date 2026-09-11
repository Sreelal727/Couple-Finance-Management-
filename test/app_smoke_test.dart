import 'dart:io';

import 'package:duo_finance/app.dart';
import 'package:duo_finance/data/database.dart';
import 'package:duo_finance/data/repository.dart';
import 'package:duo_finance/features/lock/lock_service.dart';
import 'package:duo_finance/features/shared/app_data.dart';
import 'package:duo_finance/sms/sms_service.dart';
import 'package:duo_finance/sync/attachment_store.dart';
import 'package:duo_finance/sync/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pumps frames with real wall-clock gaps so database and socket futures
/// (which run outside the test's fake async zone) get a chance to complete.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100)); // advances animations too
  }
}

void main() {
  sqfliteFfiInit();

  testWidgets('onboard, add an expense, browse every tab', (tester) async {
    // Real I/O (sqlite, sockets) needs runAsync in widget tests.
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('duo_smoke');
      final db = await AppDatabase.open(factory: databaseFactoryFfiNoIsolate, path: '${dir.path}/db.sqlite');
      final repo = Repository(db);
      await repo.load();
      await repo.loadColumnInfo();
      final prefs = await SharedPreferences.getInstance();
      final attachments = AttachmentStore(repo, dir: dir);
      final sync = SyncService(repo: repo, attachments: attachments, prefs: prefs);
      await sync.init();
      final sms = SmsService(repo: repo, prefs: prefs);
      final lock = LockService(prefs);
      final data = AppData(repo);

      await tester.pumpWidget(
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
      await settle(tester);

      // Onboarding
      expect(find.text('Get started'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Sreelal');
      await tester.tap(find.text('Get started'));
      await settle(tester);
      expect(repo.isSetUp, isTrue);
      expect(find.textContaining(', Sreelal'), findsOneWidget);

      // Add an expense
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      expect(find.text('Add expense'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '0'), '450');
      await tester.enterText(find.byType(TextField).at(1), 'Groceries at Lulu');
      await tester.pump();
      await tester.tap(find.text('Groceries'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await settle(tester);
      final txns = await repo.recentTxns();
      expect(txns.single.title, 'Groceries at Lulu');
      expect(txns.single.amountPaise, 45000);
      expect(txns.single.isShared, isTrue);
      expect(txns.single.categoryId, 'cat-groceries');
      expect(find.text('Groceries at Lulu'), findsWidgets);

      // Tabs
      for (final label in ['History', 'Reports', 'Goals', 'Settings', 'Home']) {
        await tester.tap(find.text(label).last);
        await settle(tester);
      }
      expect(find.text('Spent this month'), findsOneWidget);

      await sync.stopNetwork();
      await db.close();
      await dir.delete(recursive: true);
    });
  });
}
