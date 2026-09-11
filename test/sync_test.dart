import 'dart:io';
import 'dart:typed_data';

import 'package:duo_finance/data/database.dart';
import 'package:duo_finance/data/models.dart';
import 'package:duo_finance/data/repository.dart';
import 'package:duo_finance/sync/attachment_store.dart';
import 'package:duo_finance/sync/protocol.dart';
import 'package:duo_finance/sync/sync_bundle.dart';
import 'package:duo_finance/sync/sync_client.dart';
import 'package:duo_finance/sync/sync_crypto.dart';
import 'package:duo_finance/sync/sync_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One simulated phone.
class Phone {
  late Repository repo;
  late AttachmentStore store;
  late Directory dir;
  late DeviceInfo info;
  SyncServer? server;

  static Future<Phone> create(String name) async {
    final p = Phone();
    p.dir = await Directory.systemTemp.createTemp('duo_$name');
    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: '${p.dir.path}/db.sqlite');
    p.repo = Repository(db);
    await p.repo.load();
    await p.repo.setUp(myName: name, colorHex: '#000000');
    await p.repo.loadColumnInfo();
    p.store = AttachmentStore(p.repo, dir: p.dir);
    p.info = DeviceInfo(deviceId: p.repo.identity.deviceId, memberId: p.repo.identity.memberId, name: name);
    return p;
  }

  Future<Txn> addExpense(int paise, String title, {bool shared = true}) async {
    final t = Txn(
      meta: repo.newMeta(),
      type: TxnType.expense,
      amountPaise: paise,
      categoryId: 'cat-groceries',
      title: title,
      note: '',
      merchant: null,
      occurredAt: DateTime.now().millisecondsSinceEpoch,
      paidBy: repo.identity.memberId,
      isShared: shared,
      payerSharePaise: shared ? paise ~/ 2 : paise,
      source: TxnSource.manual,
      smsRef: null,
    );
    await repo.save(t);
    return t;
  }

  Future<void> startServer(SyncCrypto crypto) async {
    server = SyncServer(repo: repo, attachments: store, self: info, crypto: () => crypto, onPeerSeen: (_, _) async {});
    await server!.start();
  }

  Future<void> dispose() async {
    await server?.stop();
    await repo.db.close();
    await dir.delete(recursive: true);
  }
}

void main() {
  sqfliteFfiInit();

  late Phone a;
  late Phone b;
  late SyncCrypto crypto;

  setUp(() async {
    a = await Phone.create('Sreelal');
    b = await Phone.create('Sreelakshmi');
    crypto = await SyncCrypto.fromSecret(SyncCrypto.newSecret());
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test('default categories seed with identical ids on both phones', () async {
    final ca = await a.repo.categories();
    final cb = await b.repo.categories();
    expect(ca.map((c) => c.id).toSet(), cb.map((c) => c.id).toSet());
  });

  test('LAN sync exchanges rows both ways and converges', () async {
    await a.addExpense(45000, 'Groceries');
    await b.addExpense(12000, 'Auto');
    await b.startServer(crypto);

    final client = SyncClient(repo: a.repo, attachments: a.store, self: a.info, crypto: crypto);
    final r = await client.sync('127.0.0.1', b.server!.port);
    expect(r.received, greaterThan(0));
    expect(r.sent, greaterThan(0));

    final txA = await a.repo.recentTxns();
    final txB = await b.repo.recentTxns();
    expect(txA.map((t) => t.title).toSet(), {'Groceries', 'Auto'});
    expect(txB.map((t) => t.title).toSet(), {'Groceries', 'Auto'});

    // Both know both members now.
    expect((await a.repo.members()).length, 2);
    expect((await b.repo.members()).length, 2);
    expect((await a.repo.partner())!.name, 'Sreelakshmi');
    expect((await b.repo.partner())!.name, 'Sreelal');

    // Second sync is a no-op.
    final r2 = await client.sync('127.0.0.1', b.server!.port);
    expect(r2.nothingChanged, isTrue);

    // Vectors agree.
    expect(await a.repo.vector(), await b.repo.vector());
  });

  test('edits and deletes propagate, newest wins', () async {
    final t = await a.addExpense(45000, 'Groceries');
    await b.startServer(crypto);
    final client = SyncClient(repo: a.repo, attachments: a.store, self: a.info, crypto: crypto);
    await client.sync('127.0.0.1', b.server!.port);

    // B edits the title, A deletes later; A's later write should win.
    await b.repo.save((await b.repo.txnById(t.id))!.copyWith(title: 'Groceries at Lulu'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await a.repo.softDelete('transactions', t.id);
    await client.sync('127.0.0.1', b.server!.port);

    expect((await a.repo.recentTxns()), isEmpty);
    expect((await b.repo.recentTxns()), isEmpty);
    final rowB = await b.repo.txnById(t.id);
    expect(rowB!.meta.deleted, isTrue);
  });

  test('shared balance is symmetric after sync', () async {
    await a.addExpense(100000, 'Rent'); // A paid, B owes 500
    await b.addExpense(20000, 'Dinner'); // B paid, A owes 100
    await b.startServer(crypto);
    final client = SyncClient(repo: a.repo, attachments: a.store, self: a.info, crypto: crypto);
    await client.sync('127.0.0.1', b.server!.port);

    final balA = await a.repo.balance();
    final balB = await b.repo.balance();
    expect(balA.netPaise, 40000); // B owes A 400
    expect(balB.netPaise, -40000);

    // B settles 400 to A.
    await b.repo.save(
      Settlement(
        meta: b.repo.newMeta(),
        fromMember: b.repo.identity.memberId,
        toMember: a.repo.identity.memberId,
        amountPaise: 40000,
        occurredAt: DateTime.now().millisecondsSinceEpoch,
        note: '',
      ),
    );
    await client.sync('127.0.0.1', b.server!.port);
    expect((await a.repo.balance()).netPaise, 0);
    expect((await b.repo.balance()).netPaise, 0);
  });

  test('attachments travel in both directions', () async {
    final ta = await a.addExpense(1000, 'A receipt');
    final tb = await b.addExpense(2000, 'B receipt');
    await a.store.add(ta.id, Uint8List.fromList(List.generate(5000, (i) => i % 251)));
    await b.store.add(tb.id, Uint8List.fromList(List.generate(3000, (i) => (i * 7) % 253)), mime: 'image/png');
    await b.startServer(crypto);

    final client = SyncClient(repo: a.repo, attachments: a.store, self: a.info, crypto: crypto);
    final r = await client.sync('127.0.0.1', b.server!.port);
    expect(r.attachmentsReceived, 1);
    expect(r.attachmentsSent, 1);
    expect(await a.store.missingBytes(), isEmpty);
    expect(await b.store.missingBytes(), isEmpty);
    final got = await a.store.read((await a.repo.attachmentsFor(tb.id)).single);
    expect(got!.length, 3000);
  });

  test('wrong secret is rejected', () async {
    await a.addExpense(1000, 'x');
    await b.startServer(crypto);
    final wrong = await SyncCrypto.fromSecret(SyncCrypto.newSecret());
    final client = SyncClient(repo: a.repo, attachments: a.store, self: a.info, crypto: wrong);
    expect(() => client.sync('127.0.0.1', b.server!.port), throwsA(isA<SyncException>()));
    expect((await b.repo.recentTxns()), isEmpty);
  });

  test('offline bundle round trip', () async {
    final t = await a.addExpense(7000, 'Bundle test');
    await a.store.add(t.id, Uint8List.fromList(List.filled(100, 9)));
    final bundle = SyncBundle(repo: a.repo, attachments: a.store, self: a.info, crypto: crypto);
    final bytes = await bundle.create();
    expect(String.fromCharCodes(bytes.sublist(0, 8)), SyncProtocol.bundleMagic);

    final importer = SyncBundle(repo: b.repo, attachments: b.store, self: b.info, crypto: crypto);
    final r = await importer.import(bytes);
    expect(r.applied, greaterThan(0));
    expect(r.attachments, 1);
    expect((await b.repo.recentTxns()).single.title, 'Bundle test');

    // Importing again changes nothing.
    final r2 = await importer.import(bytes);
    expect(r2.applied, 0);

    // A now remembers what B has, so the next bundle for B is small.
    await a.repo.savePeerVector(b.info.deviceId, await b.repo.vector());
    await a.addExpense(100, 'new');
    final delta = await bundle.create(peerDeviceId: b.info.deviceId);
    expect(delta.length, lessThan(bytes.length));
    final r3 = await importer.import(delta);
    expect(r3.applied, 1);
  });

  test('crypto round trip', () async {
    final sealed = await crypto.sealJson({'a': 1, 'b': 'x'});
    expect(await crypto.openJson(sealed), {'a': 1, 'b': 'x'});
  });
}
