import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Tables that take part in sync, in an order that respects references
/// (members before transactions, transactions before attachments).
const syncedTables = <String>[
  'members',
  'categories',
  'transactions',
  'settlements',
  'budgets',
  'goals',
  'goal_contributions',
  'quick_adds',
  'attachments',
];

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 1;

  /// Opens (or creates) the database. Pass [factory] + [path] in tests to use
  /// an in-memory sqflite_common_ffi database.
  static Future<AppDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'duo_finance.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = OFF'),
        onCreate: (db, _) => _createSchema(db),
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');

    batch.execute('''
      CREATE TABLE members (
        ${SyncMeta.columnsSql},
        name TEXT NOT NULL,
        color TEXT NOT NULL
      )''');

    batch.execute('''
      CREATE TABLE categories (
        ${SyncMeta.columnsSql},
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color TEXT NOT NULL,
        kind TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');

    batch.execute('''
      CREATE TABLE transactions (
        ${SyncMeta.columnsSql},
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        category_id TEXT,
        title TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        merchant TEXT,
        occurred_at INTEGER NOT NULL,
        paid_by TEXT NOT NULL,
        is_shared INTEGER NOT NULL DEFAULT 0,
        payer_share INTEGER NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'manual',
        sms_ref TEXT
      )''');
    batch.execute('CREATE INDEX idx_txn_occurred ON transactions(occurred_at)');
    batch.execute('CREATE INDEX idx_txn_sms_ref ON transactions(sms_ref)');

    batch.execute('''
      CREATE TABLE settlements (
        ${SyncMeta.columnsSql},
        from_member TEXT NOT NULL,
        to_member TEXT NOT NULL,
        amount INTEGER NOT NULL,
        occurred_at INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )''');

    batch.execute('''
      CREATE TABLE budgets (
        ${SyncMeta.columnsSql},
        category_id TEXT,
        amount INTEGER NOT NULL
      )''');

    batch.execute('''
      CREATE TABLE goals (
        ${SyncMeta.columnsSql},
        name TEXT NOT NULL,
        target INTEGER NOT NULL,
        deadline INTEGER,
        icon TEXT NOT NULL DEFAULT 'savings',
        color TEXT NOT NULL DEFAULT '#0E7C7B'
      )''');

    batch.execute('''
      CREATE TABLE goal_contributions (
        ${SyncMeta.columnsSql},
        goal_id TEXT NOT NULL,
        member_id TEXT NOT NULL,
        amount INTEGER NOT NULL,
        occurred_at INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )''');

    batch.execute('''
      CREATE TABLE quick_adds (
        ${SyncMeta.columnsSql},
        label TEXT NOT NULL,
        amount INTEGER NOT NULL DEFAULT 0,
        category_id TEXT,
        is_shared INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');

    batch.execute('''
      CREATE TABLE attachments (
        ${SyncMeta.columnsSql},
        txn_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime TEXT NOT NULL,
        size INTEGER NOT NULL,
        sha256 TEXT NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_att_txn ON attachments(txn_id)');

    // Highest sequence number seen from each device, whether or not the row
    // was applied. Lets us ask a peer only for what is genuinely new.
    batch.execute('''
      CREATE TABLE seen_vector (
        origin_device TEXT PRIMARY KEY,
        seq INTEGER NOT NULL
      )''');

    // ---- local-only tables ----
    batch.execute('''
      CREATE TABLE sms_inbox (
        id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        body_hash TEXT NOT NULL UNIQUE,
        received_at INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        direction TEXT NOT NULL,
        merchant TEXT,
        account_tail TEXT,
        reference TEXT,
        status TEXT NOT NULL,
        txn_id TEXT
      )''');

    batch.execute('''
      CREATE TABLE peers (
        device_id TEXT PRIMARY KEY,
        member_id TEXT NOT NULL,
        name TEXT NOT NULL,
        last_address TEXT,
        last_seen_at INTEGER,
        last_sync_at INTEGER,
        paired_at INTEGER NOT NULL
      )''');

    batch.execute('''
      CREATE TABLE sync_log (
        id TEXT PRIMARY KEY,
        peer_name TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        finished_at INTEGER,
        method TEXT NOT NULL,
        outcome TEXT NOT NULL,
        sent INTEGER NOT NULL DEFAULT 0,
        received INTEGER NOT NULL DEFAULT 0,
        att_sent INTEGER NOT NULL DEFAULT 0,
        att_received INTEGER NOT NULL DEFAULT 0,
        detail TEXT
      )''');

    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();
}
