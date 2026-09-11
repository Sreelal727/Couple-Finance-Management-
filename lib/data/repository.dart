import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;
import 'package:sqflite/sqflite.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import 'database.dart';
import 'default_categories.dart';
import 'models.dart';

/// Who this phone is.
class Identity {
  final String deviceId;
  final String memberId;
  const Identity({required this.deviceId, required this.memberId});
}

/// Rows grouped by table, as exchanged during sync.
typedef RowBatch = Map<String, List<Map<String, Object?>>>;

/// Shared balance between the two partners.
class Balance {
  /// Positive: [partnerId] owes [meId]. Negative: I owe partner.
  final int netPaise;
  final String meId;
  final String? partnerId;
  const Balance({required this.netPaise, required this.meId, required this.partnerId});
  bool get settled => netPaise == 0;
}

/// All reads and writes go through here. It is a [ChangeNotifier] so the UI
/// can reload after any local write or after a sync applied incoming rows.
class Repository extends ChangeNotifier {
  Repository(this._db);

  final AppDatabase _db;
  Database get db => _db.db;

  Identity? _identity;
  Identity get identity => _identity!;
  bool get isSetUp => _identity != null;

  int _lastUpdatedAt = 0;

  // ------------------------------------------------------------------ setup

  Future<void> load() async {
    final rows = await db.query('meta');
    final map = {for (final r in rows) r['key'] as String: r['value'] as String?};
    final deviceId = map['device_id'];
    final memberId = map['member_id'];
    if (deviceId != null && memberId != null) {
      _identity = Identity(deviceId: deviceId, memberId: memberId);
    }
  }

  /// First-launch setup: creates this phone's identity and the "me" member,
  /// seeds default categories.
  Future<void> setUp({required String myName, required String colorHex}) async {
    final deviceId = newId();
    final memberId = newId();
    await db.transaction((txn) async {
      await txn.insert('meta', {'key': 'device_id', 'value': deviceId});
      await txn.insert('meta', {'key': 'member_id', 'value': memberId});
      await txn.insert('meta', {'key': 'seq', 'value': '0'});
    });
    _identity = Identity(deviceId: deviceId, memberId: memberId);
    await save(Member(meta: _newMeta(memberId), name: myName, colorHex: colorHex));
    var order = 0;
    for (final c in defaultCategories) {
      await save(Category(
        meta: _newMeta(c.id),
        name: c.name,
        icon: c.icon,
        colorHex: c.colorHex,
        kind: c.kind,
        sortOrder: order++,
      ));
    }
    notifyListeners();
  }

  Future<String?> getMeta(String key) async {
    final r = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) async {
    await db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------------------------------------------------ sync meta

  SyncMeta _newMeta(String id) {
    final now = _monotonicNow();
    return SyncMeta(
      id: id,
      authorId: identity.memberId,
      originDevice: identity.deviceId,
      seq: 0, // assigned at write time
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Fresh metadata for a brand-new record authored on this phone.
  SyncMeta newMeta() => _newMeta(newId());

  int _monotonicNow() {
    var now = Dates.nowMs();
    if (now <= _lastUpdatedAt) now = _lastUpdatedAt + 1;
    _lastUpdatedAt = now;
    return now;
  }

  Future<int> _nextSeq(Transaction txn) async {
    final r = await txn.query('meta', where: 'key = ?', whereArgs: ['seq']);
    final current = int.tryParse((r.isEmpty ? null : r.first['value'] as String?) ?? '0') ?? 0;
    final next = current + 1;
    await txn.insert('meta', {'key': 'seq', 'value': '$next'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert('seen_vector', {'origin_device': identity.deviceId, 'seq': next},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  }

  /// Writes a record authored/edited on this phone: stamps it with this
  /// device as origin, the next sequence number and a fresh updated_at.
  Future<void> save(SyncedRecord record, {bool notify = true}) async {
    await _write(record.table, record.toMap());
    if (notify) notifyListeners();
  }

  Future<void> _write(String table, Map<String, Object?> map) async {
    await db.transaction((txn) async {
      final seq = await _nextSeq(txn);
      final row = {
        ...map,
        'origin_device': identity.deviceId,
        'seq': seq,
        'updated_at': _monotonicNow(),
      };
      await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> softDelete(String table, String id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    await _write(table, {...rows.first, 'deleted': 1});
    if (table == 'transactions') {
      final atts = await db.query('attachments',
          where: 'txn_id = ? AND deleted = 0', whereArgs: [id]);
      for (final a in atts) {
        await _write('attachments', {...a, 'deleted': 1});
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ members

  Future<List<Member>> members() async {
    final rows = await db.query('members', where: 'deleted = 0', orderBy: 'created_at');
    return rows.map(Member.fromMap).toList();
  }

  Future<Member?> memberById(String id) async {
    final rows = await db.query('members', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Member.fromMap(rows.first);
  }

  Future<Member> me() async => (await memberById(identity.memberId))!;

  Future<Member?> partner() async {
    final all = await members();
    for (final m in all) {
      if (m.id != identity.memberId) return m;
    }
    return null;
  }

  // --------------------------------------------------------- categories

  Future<List<Category>> categories({CategoryKind? kind}) async {
    final rows = await db.query(
      'categories',
      where: kind == null ? 'deleted = 0' : 'deleted = 0 AND kind = ?',
      whereArgs: kind == null ? null : [kind.name],
      orderBy: 'sort_order, name',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<Category?> categoryById(String? id) async {
    if (id == null) return null;
    final rows = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Category.fromMap(rows.first);
  }

  /// The category most often used for [merchant] in the past, if any.
  Future<String?> suggestCategoryForMerchant(String? merchant) async {
    if (merchant == null || merchant.trim().isEmpty) return null;
    final rows = await db.rawQuery('''
      SELECT category_id, COUNT(*) AS n FROM transactions
      WHERE deleted = 0 AND category_id IS NOT NULL AND LOWER(merchant) = LOWER(?)
      GROUP BY category_id ORDER BY n DESC LIMIT 1''', [merchant.trim()]);
    return rows.isEmpty ? null : rows.first['category_id'] as String?;
  }

  /// Most recently used title for [merchant], so one-tap add can prefill.
  Future<String?> lastTitleForMerchant(String? merchant) async {
    if (merchant == null || merchant.trim().isEmpty) return null;
    final rows = await db.query('transactions',
        columns: ['title'],
        where: "deleted = 0 AND title != '' AND LOWER(merchant) = LOWER(?)",
        whereArgs: [merchant.trim()],
        orderBy: 'occurred_at DESC',
        limit: 1);
    return rows.isEmpty ? null : rows.first['title'] as String?;
  }

  // ------------------------------------------------------- transactions

  Future<List<Txn>> txnsInRange(DateTime start, DateTime end) async {
    final rows = await db.query(
      'transactions',
      where: 'deleted = 0 AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'occurred_at DESC, created_at DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<List<Txn>> txnsForMonth(DateTime month) =>
      txnsInRange(Dates.monthStart(month), Dates.nextMonthStart(month));

  Future<List<Txn>> recentTxns({int limit = 8}) async {
    final rows = await db.query('transactions',
        where: 'deleted = 0', orderBy: 'occurred_at DESC, created_at DESC', limit: limit);
    return rows.map(Txn.fromMap).toList();
  }

  Future<List<Txn>> searchTxns(String query, {int limit = 200}) async {
    final q = '%${query.toLowerCase()}%';
    final rows = await db.query('transactions',
        where:
            'deleted = 0 AND (LOWER(title) LIKE ? OR LOWER(note) LIKE ? OR LOWER(merchant) LIKE ?)',
        whereArgs: [q, q, q],
        orderBy: 'occurred_at DESC',
        limit: limit);
    return rows.map(Txn.fromMap).toList();
  }

  Future<Txn?> txnById(String id) async {
    final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Txn.fromMap(rows.first);
  }

  Future<bool> txnExistsForSms(String smsRef) async {
    final rows = await db.query('transactions',
        columns: ['id'], where: 'sms_ref = ? AND deleted = 0', whereArgs: [smsRef], limit: 1);
    return rows.isNotEmpty;
  }

  /// Distinct titles used before, for autocomplete.
  Future<List<String>> recentTitles({int limit = 30}) async {
    final rows = await db.rawQuery('''
      SELECT title, MAX(occurred_at) AS t FROM transactions
      WHERE deleted = 0 AND title != '' GROUP BY LOWER(title)
      ORDER BY t DESC LIMIT ?''', [limit]);
    return rows.map((r) => r['title'] as String).toList();
  }

  // --------------------------------------------------- balance / settle

  Future<Balance> balance() async {
    final meId = identity.memberId;
    final other = await partner();
    // What each payer is owed from shared expenses.
    final owed = await db.rawQuery('''
      SELECT paid_by, SUM(amount - payer_share) AS owed FROM transactions
      WHERE deleted = 0 AND type = 'expense' AND is_shared = 1 GROUP BY paid_by''');
    var net = 0; // positive = partner owes me
    for (final r in owed) {
      final v = (r['owed'] as num? ?? 0).toInt();
      if (r['paid_by'] == meId) {
        net += v;
      } else {
        net -= v;
      }
    }
    final settles = await db.query('settlements', where: 'deleted = 0');
    for (final r in settles) {
      final s = Settlement.fromMap(r);
      // Money moving from me to partner reduces what I owe (raises net).
      if (s.fromMember == meId) {
        net += s.amountPaise;
      } else if (s.toMember == meId) {
        net -= s.amountPaise;
      }
    }
    return Balance(netPaise: net, meId: meId, partnerId: other?.id);
  }

  Future<List<Settlement>> settlements() async {
    final rows = await db.query('settlements', where: 'deleted = 0', orderBy: 'occurred_at DESC');
    return rows.map(Settlement.fromMap).toList();
  }

  // ------------------------------------------------------------ budgets

  Future<List<Budget>> budgets() async {
    final rows = await db.query('budgets', where: 'deleted = 0');
    return rows.map(Budget.fromMap).toList();
  }

  Future<Budget?> budgetFor(String? categoryId) async {
    final rows = await db.query('budgets',
        where: categoryId == null
            ? 'deleted = 0 AND category_id IS NULL'
            : 'deleted = 0 AND category_id = ?',
        whereArgs: categoryId == null ? null : [categoryId]);
    return rows.isEmpty ? null : Budget.fromMap(rows.first);
  }

  // -------------------------------------------------------------- goals

  Future<List<Goal>> goals() async {
    final rows = await db.query('goals', where: 'deleted = 0', orderBy: 'created_at');
    return rows.map(Goal.fromMap).toList();
  }

  Future<Goal?> goalById(String id) async {
    final rows = await db.query('goals', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Goal.fromMap(rows.first);
  }

  Future<List<GoalContribution>> contributions(String goalId) async {
    final rows = await db.query('goal_contributions',
        where: 'deleted = 0 AND goal_id = ?', whereArgs: [goalId], orderBy: 'occurred_at DESC');
    return rows.map(GoalContribution.fromMap).toList();
  }

  /// goal id -> total saved (paise)
  Future<Map<String, int>> goalTotals() async {
    final rows = await db.rawQuery('''
      SELECT goal_id, SUM(amount) AS total FROM goal_contributions
      WHERE deleted = 0 GROUP BY goal_id''');
    return {for (final r in rows) r['goal_id'] as String: (r['total'] as num? ?? 0).toInt()};
  }

  /// goal id -> member id -> saved
  Future<Map<String, Map<String, int>>> goalTotalsByMember() async {
    final rows = await db.rawQuery('''
      SELECT goal_id, member_id, SUM(amount) AS total FROM goal_contributions
      WHERE deleted = 0 GROUP BY goal_id, member_id''');
    final out = <String, Map<String, int>>{};
    for (final r in rows) {
      out.putIfAbsent(r['goal_id'] as String, () => {})[r['member_id'] as String] =
          (r['total'] as num? ?? 0).toInt();
    }
    return out;
  }

  // --------------------------------------------------------- quick adds

  Future<List<QuickAdd>> quickAdds() async {
    final rows = await db.query('quick_adds', where: 'deleted = 0', orderBy: 'sort_order, created_at');
    return rows.map(QuickAdd.fromMap).toList();
  }

  // -------------------------------------------------------- attachments

  Future<List<Attachment>> attachmentsFor(String txnId) async {
    final rows = await db.query('attachments',
        where: 'deleted = 0 AND txn_id = ?', whereArgs: [txnId], orderBy: 'created_at');
    return rows.map(Attachment.fromMap).toList();
  }

  Future<Attachment?> attachmentById(String id) async {
    final rows = await db.query('attachments', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Attachment.fromMap(rows.first);
  }

  Future<List<Attachment>> allAttachments() async {
    final rows = await db.query('attachments', where: 'deleted = 0');
    return rows.map(Attachment.fromMap).toList();
  }

  // ---------------------------------------------------------- sms inbox

  Future<bool> insertSms(SmsItem item) async {
    final n = await db.insert('sms_inbox', item.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    if (n != 0) notifyListeners();
    return n != 0;
  }

  Future<List<SmsItem>> smsItems({SmsStatus? status, int limit = 200}) async {
    final rows = await db.query('sms_inbox',
        where: status == null ? null : 'status = ?',
        whereArgs: status == null ? null : [status.name],
        orderBy: 'received_at DESC',
        limit: limit);
    return rows.map(SmsItem.fromMap).toList();
  }

  Future<SmsItem?> smsById(String id) async {
    final rows = await db.query('sms_inbox', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : SmsItem.fromMap(rows.first);
  }

  Future<int> pendingSmsCount() async {
    final r = await db.rawQuery("SELECT COUNT(*) AS n FROM sms_inbox WHERE status = 'pending'");
    return (r.first['n'] as num).toInt();
  }

  Future<void> updateSms(SmsItem item) async {
    await db.update('sms_inbox', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
    notifyListeners();
  }

  Future<void> deleteSms(String id) async {
    await db.delete('sms_inbox', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  // -------------------------------------------------------------- peers

  Future<List<Peer>> peers() async {
    final rows = await db.query('peers', orderBy: 'paired_at');
    return rows.map(Peer.fromMap).toList();
  }

  Future<Peer?> peerByDevice(String deviceId) async {
    final rows = await db.query('peers', where: 'device_id = ?', whereArgs: [deviceId]);
    return rows.isEmpty ? null : Peer.fromMap(rows.first);
  }

  Future<void> upsertPeer(Peer peer) async {
    await db.insert('peers', peer.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> removePeer(String deviceId) async {
    await db.delete('peers', where: 'device_id = ?', whereArgs: [deviceId]);
    notifyListeners();
  }

  // ----------------------------------------------------------- sync log

  Future<void> addSyncLog(SyncLogEntry e) async {
    await db.insert('sync_log', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    // Keep the log bounded.
    await db.rawDelete('''
      DELETE FROM sync_log WHERE id NOT IN (
        SELECT id FROM sync_log ORDER BY started_at DESC LIMIT 200)''');
    notifyListeners();
  }

  Future<List<SyncLogEntry>> syncLog({int limit = 50}) async {
    final rows = await db.query('sync_log', orderBy: 'started_at DESC', limit: limit);
    return rows.map(SyncLogEntry.fromMap).toList();
  }

  Future<SyncLogEntry?> lastSuccessfulSync() async {
    final rows = await db.query('sync_log',
        where: 'outcome = ?', whereArgs: ['ok'], orderBy: 'started_at DESC', limit: 1);
    return rows.isEmpty ? null : SyncLogEntry.fromMap(rows.first);
  }

  // ------------------------------------------------------------- sync core

  /// origin device -> highest sequence number this phone has seen.
  Future<Map<String, int>> vector() async {
    final out = <String, int>{};
    final seen = await db.query('seen_vector');
    for (final r in seen) {
      out[r['origin_device'] as String] = (r['seq'] as num).toInt();
    }
    // Belt and braces: also derive from the rows themselves.
    for (final table in syncedTables) {
      final rows = await db.rawQuery(
          'SELECT origin_device, MAX(seq) AS s FROM $table GROUP BY origin_device');
      for (final r in rows) {
        final d = r['origin_device'] as String;
        final s = (r['s'] as num).toInt();
        if ((out[d] ?? 0) < s) out[d] = s;
      }
    }
    return out;
  }

  /// Every row whose (origin, seq) is newer than [known].
  Future<RowBatch> rowsSince(Map<String, int> known) async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final table in syncedTables) {
      final origins = (await db.rawQuery('SELECT DISTINCT origin_device FROM $table'))
          .map((r) => r['origin_device'] as String)
          .toList();
      if (origins.isEmpty) continue;
      final clauses = <String>[];
      final args = <Object?>[];
      for (final o in origins) {
        clauses.add('(origin_device = ? AND seq > ?)');
        args.add(o);
        args.add(known[o] ?? 0);
      }
      final rows = await db.query(table,
          where: clauses.join(' OR '), whereArgs: args, orderBy: 'seq');
      if (rows.isNotEmpty) out[table] = rows.map((r) => Map<String, Object?>.from(r)).toList();
    }
    return out;
  }

  /// Merges rows received from a peer. Newest [updated_at] wins; ties are
  /// broken by origin device id so both phones converge on the same answer.
  /// Returns the number of rows that changed local state.
  Future<int> applyIncoming(RowBatch batch) async {
    var applied = 0;
    await db.transaction((txn) async {
      for (final table in syncedTables) {
        final rows = batch[table];
        if (rows == null) continue;
        for (final incoming in rows) {
          final id = incoming['id'] as String;
          final origin = incoming['origin_device'] as String;
          final seq = (incoming['seq'] as num).toInt();
          final existing = await txn.query(table, where: 'id = ?', whereArgs: [id]);
          var take = existing.isEmpty;
          if (!take) {
            final local = existing.first;
            final li = (local['updated_at'] as num).toInt();
            final ii = (incoming['updated_at'] as num).toInt();
            final lo = local['origin_device'] as String;
            take = ii > li || (ii == li && origin.compareTo(lo) > 0);
          }
          if (take) {
            await txn.insert(table, _sanitize(table, incoming),
                conflictAlgorithm: ConflictAlgorithm.replace);
            applied++;
          }
          final seen = await txn.query('seen_vector',
              where: 'origin_device = ?', whereArgs: [origin]);
          final cur = seen.isEmpty ? 0 : (seen.first['seq'] as num).toInt();
          if (seq > cur) {
            await txn.insert('seen_vector', {'origin_device': origin, 'seq': seq},
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
    });
    if (applied > 0) notifyListeners();
    return applied;
  }

  static final _columns = <String, Set<String>>{};

  /// Drops unknown keys so a newer app version on the other phone cannot
  /// break inserts here.
  Map<String, Object?> _sanitize(String table, Map<String, Object?> row) {
    final cols = _columns[table];
    if (cols == null) return row; // filled lazily below
    return {for (final e in row.entries) if (cols.contains(e.key)) e.key: e.value};
  }

  Future<void> loadColumnInfo() async {
    for (final t in syncedTables) {
      final info = await db.rawQuery('PRAGMA table_info($t)');
      _columns[t] = info.map((r) => r['name'] as String).toSet();
    }
  }

  /// Full export of every synced row (for backups and full bundles).
  Future<RowBatch> exportAll() => rowsSince(const {});

  /// Counts for the settings screen.
  Future<Map<String, int>> tableCounts() async {
    final out = <String, int>{};
    for (final t in syncedTables) {
      final r = await db.rawQuery('SELECT COUNT(*) AS n FROM $t WHERE deleted = 0');
      out[t] = (r.first['n'] as num).toInt();
    }
    return out;
  }

  /// Remembered vector of a peer (what they had last time we talked), used to
  /// build an offline bundle without asking them.
  Future<Map<String, int>> peerVector(String deviceId) async {
    final raw = await getMeta('peer_vector_$deviceId');
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<void> savePeerVector(String deviceId, Map<String, int> v) =>
      setMeta('peer_vector_$deviceId', jsonEncode(v));

  /// Called by services that changed state outside of [save].
  void bump() => notifyListeners();
}
