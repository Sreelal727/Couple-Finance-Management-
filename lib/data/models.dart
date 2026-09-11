// Data models. Every synced record carries [SyncMeta]; local-only records
// (SMS inbox, peers, sync log) do not.

/// Columns shared by every synced table.
///
/// * [originDevice] + [seq] identify *which device last wrote the row* and its
///   position in that device's write sequence. Sync is "give me every row
///   whose (originDevice, seq) I have not seen yet".
/// * [updatedAt] resolves conflicts: newest write wins.
/// * [deleted] is a tombstone so deletes propagate.
class SyncMeta {
  final String id;
  final String authorId; // member who created the record
  final String originDevice; // device that last wrote the record
  final int seq; // that device's write sequence number
  final int createdAt;
  final int updatedAt;
  final bool deleted;

  const SyncMeta({
    required this.id,
    required this.authorId,
    required this.originDevice,
    required this.seq,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'author_id': authorId,
        'origin_device': originDevice,
        'seq': seq,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };

  static SyncMeta fromMap(Map<String, Object?> m) => SyncMeta(
        id: m['id'] as String,
        authorId: m['author_id'] as String,
        originDevice: m['origin_device'] as String,
        seq: (m['seq'] as num).toInt(),
        createdAt: (m['created_at'] as num).toInt(),
        updatedAt: (m['updated_at'] as num).toInt(),
        deleted: (m['deleted'] as num? ?? 0) != 0,
      );

  static const columnsSql = '''
    id TEXT PRIMARY KEY,
    author_id TEXT NOT NULL,
    origin_device TEXT NOT NULL,
    seq INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0''';
}

abstract class SyncedRecord {
  SyncMeta get meta;
  String get table;
  Map<String, Object?> toMap();
}

/// A person using the app (you or your partner).
class Member implements SyncedRecord {
  @override
  final SyncMeta meta;
  final String name;
  final String colorHex;

  const Member({required this.meta, required this.name, required this.colorHex});

  @override
  String get table => 'members';
  String get id => meta.id;

  @override
  Map<String, Object?> toMap() => {...meta.toMap(), 'name': name, 'color': colorHex};

  static Member fromMap(Map<String, Object?> m) => Member(
        meta: SyncMeta.fromMap(m),
        name: m['name'] as String,
        colorHex: m['color'] as String,
      );

  Member copyWith({String? name, String? colorHex, SyncMeta? meta}) => Member(
        meta: meta ?? this.meta,
        name: name ?? this.name,
        colorHex: colorHex ?? this.colorHex,
      );
}

enum CategoryKind { expense, income }

class Category implements SyncedRecord {
  @override
  final SyncMeta meta;
  final String name;
  final String icon; // key into CategoryIcons
  final String colorHex;
  final CategoryKind kind;
  final int sortOrder;

  const Category({
    required this.meta,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.kind,
    required this.sortOrder,
  });

  @override
  String get table => 'categories';
  String get id => meta.id;

  @override
  Map<String, Object?> toMap() => {
        ...meta.toMap(),
        'name': name,
        'icon': icon,
        'color': colorHex,
        'kind': kind.name,
        'sort_order': sortOrder,
      };

  static Category fromMap(Map<String, Object?> m) => Category(
        meta: SyncMeta.fromMap(m),
        name: m['name'] as String,
        icon: m['icon'] as String,
        colorHex: m['color'] as String,
        kind: CategoryKind.values.byName(m['kind'] as String),
        sortOrder: (m['sort_order'] as num).toInt(),
      );

  Category copyWith({
    SyncMeta? meta,
    String? name,
    String? icon,
    String? colorHex,
    CategoryKind? kind,
    int? sortOrder,
  }) =>
      Category(
        meta: meta ?? this.meta,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        colorHex: colorHex ?? this.colorHex,
        kind: kind ?? this.kind,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

enum TxnType { expense, income }

enum TxnSource { manual, sms, share, quick }

/// A single expense or income entry.
///
/// Split model (two people): [paidBy] paid [amountPaise]. If [isShared], the
/// partner owes `amountPaise - payerSharePaise`. If not shared, the whole
/// amount is personal to [paidBy] and nothing is owed.
class Txn implements SyncedRecord {
  @override
  final SyncMeta meta;
  final TxnType type;
  final int amountPaise;
  final String? categoryId;
  final String title; // name / purpose ("Groceries at Lulu", "Auto to office")
  final String note;
  final String? merchant; // raw merchant / payee from SMS or screenshot
  final int occurredAt;
  final String paidBy; // member id (for income: who received it)
  final bool isShared;
  final int payerSharePaise; // only meaningful when isShared
  final TxnSource source;
  final String? smsRef; // hash of the SMS this was created from (dedupe)

  const Txn({
    required this.meta,
    required this.type,
    required this.amountPaise,
    required this.categoryId,
    required this.title,
    required this.note,
    required this.merchant,
    required this.occurredAt,
    required this.paidBy,
    required this.isShared,
    required this.payerSharePaise,
    required this.source,
    required this.smsRef,
  });

  @override
  String get table => 'transactions';
  String get id => meta.id;

  /// How much the *other* person owes [paidBy] for this entry.
  int get partnerOwesPaise =>
      (type == TxnType.expense && isShared) ? amountPaise - payerSharePaise : 0;

  @override
  Map<String, Object?> toMap() => {
        ...meta.toMap(),
        'type': type.name,
        'amount': amountPaise,
        'category_id': categoryId,
        'title': title,
        'note': note,
        'merchant': merchant,
        'occurred_at': occurredAt,
        'paid_by': paidBy,
        'is_shared': isShared ? 1 : 0,
        'payer_share': payerSharePaise,
        'source': source.name,
        'sms_ref': smsRef,
      };

  static Txn fromMap(Map<String, Object?> m) => Txn(
        meta: SyncMeta.fromMap(m),
        type: TxnType.values.byName(m['type'] as String),
        amountPaise: (m['amount'] as num).toInt(),
        categoryId: m['category_id'] as String?,
        title: (m['title'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        merchant: m['merchant'] as String?,
        occurredAt: (m['occurred_at'] as num).toInt(),
        paidBy: m['paid_by'] as String,
        isShared: (m['is_shared'] as num? ?? 0) != 0,
        payerSharePaise: (m['payer_share'] as num? ?? 0).toInt(),
        source: TxnSource.values.byName((m['source'] as String?) ?? 'manual'),
        smsRef: m['sms_ref'] as String?,
      );

  Txn copyWith({
    SyncMeta? meta,
    TxnType? type,
    int? amountPaise,
    String? categoryId,
    bool clearCategory = false,
    String? title,
    String? note,
    String? merchant,
    int? occurredAt,
    String? paidBy,
    bool? isShared,
    int? payerSharePaise,
    TxnSource? source,
    String? smsRef,
  }) =>
      Txn(
        meta: meta ?? this.meta,
        type: type ?? this.type,
        amountPaise: amountPaise ?? this.amountPaise,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        title: title ?? this.title,
        note: note ?? this.note,
        merchant: merchant ?? this.merchant,
        occurredAt: occurredAt ?? this.occurredAt,
        paidBy: paidBy ?? this.paidBy,
        isShared: isShared ?? this.isShared,
        payerSharePaise: payerSharePaise ?? this.payerSharePaise,
        source: source ?? this.source,
        smsRef: smsRef ?? this.smsRef,
      );
}

/// Money handed from one partner to the other to settle the shared balance.
class Settlement implements SyncedRecord {
  @override
  final SyncMeta meta;
  final String fromMember;
  final String toMember;
  final int amountPaise;
  final int occurredAt;
  final String note;

  const Settlement({
    required this.meta,
    required this.fromMember,
    required this.toMember,
    required this.amountPaise,
    required this.occurredAt,
    required this.note,
  });

  @override
  String get table => 'settlements';

  @override
  Map<String, Object?> toMap() => {
        ...meta.toMap(),
        'from_member': fromMember,
        'to_member': toMember,
        'amount': amountPaise,
        'occurred_at': occurredAt,
        'note': note,
      };

  static Settlement fromMap(Map<String, Object?> m) => Settlement(
        meta: SyncMeta.fromMap(m),
        fromMember: m['from_member'] as String,
        toMember: m['to_member'] as String,
        amountPaise: (m['amount'] as num).toInt(),
        occurredAt: (m['occurred_at'] as num).toInt(),
        note: (m['note'] as String?) ?? '',
      );
}

/// Monthly budget. [categoryId] null means the overall monthly budget.
class Budget implements SyncedRecord {
  @override
  final SyncMeta meta;
  final String? categoryId;
  final int amountPaise;

  const Budget({required this.meta, required this.categoryId, required this.amountPaise});

  @override
  String get table => 'budgets';

  @override
  Map<String, Object?> toMap() =>
      {...meta.toMap(), 'category_id': categoryId, 'amount': amountPaise};

  static Budget fromMap(Map<String, Object?> m) => Budget(
        meta: SyncMeta.fromMap(m),
        categoryId: m['category_id'] as String?,
        amountPaise: (m['amount'] as num).toInt(),
      );
}

class Goal implements SyncedRecord {
  @override
  final SyncMeta meta;
  final String name;
  final int targetPaise;
  final int? deadline;
  final String icon;
  final String colorHex;

  const Goal({
    required this.meta,
    required this.name,
    required this.targetPaise,
    required this.deadline,
    required this.icon,
    required this.colorHex,
  });

  @override
  String get table => 'goals';
  String get id => meta.id;

  @override
  Map<String, Object?> toMap() => {
        ...meta.toMap(),
        'name': name,
        'target': targetPaise,
        'deadline': deadline,
        'icon': icon,
        'color': colorHex,
      };

  static Goal fromMap(Map<String, Object?> m) => Goal(
        meta: SyncMeta.fromMap(m),
        name: m['name'] as String,
        targetPaise: (m['target'] as num).toInt(),
        deadline: (m['deadline'] as num?)?.toInt(),
        icon: (m['icon'] as String?) ?? 'savings',
        colorHex: (m['color'] as String?) ?? '#0E7C7B',
      );
}

class GoalContribution implements SyncedRecord {
  @override
  final SyncMeta meta;
  final String goalId;
  final String memberId;
  final int amountPaise; // negative = withdrawal
  final int occurredAt;
  final String note;

  const GoalContribution({
    required this.meta,
    required this.goalId,
    required this.memberId,
    required this.amountPaise,
    required this.occurredAt,
    required this.note,
  });

  @override
  String get table => 'goal_contributions';

  @override
  Map<String, Object?> toMap() => {
        ...meta.toMap(),
        'goal_id': goalId,
        'member_id': memberId,
        'amount': amountPaise,
        'occurred_at': occurredAt,
        'note': note,
      };

  static GoalContribution fromMap(Map<String, Object?> m) => GoalContribution(
        meta: SyncMeta.fromMap(m),
        goalId: m['goal_id'] as String,
        memberId: m['member_id'] as String,
        amountPaise: (m['amount'] as num).toInt(),
        occurredAt: (m['occurred_at'] as num).toInt(),
        note: (m['note'] as String?) ?? '',
      );
}

/// A one-tap template shown on the home screen ("Auto ₹40", "Tea ₹15").
class QuickAdd implements SyncedRecord {
  @override
  final SyncMeta meta;
  final String label;
  final int amountPaise; // 0 = ask for amount
  final String? categoryId;
  final bool isShared;
  final int sortOrder;

  const QuickAdd({
    required this.meta,
    required this.label,
    required this.amountPaise,
    required this.categoryId,
    required this.isShared,
    required this.sortOrder,
  });

  @override
  String get table => 'quick_adds';
  String get id => meta.id;

  @override
  Map<String, Object?> toMap() => {
        ...meta.toMap(),
        'label': label,
        'amount': amountPaise,
        'category_id': categoryId,
        'is_shared': isShared ? 1 : 0,
        'sort_order': sortOrder,
      };

  static QuickAdd fromMap(Map<String, Object?> m) => QuickAdd(
        meta: SyncMeta.fromMap(m),
        label: m['label'] as String,
        amountPaise: (m['amount'] as num).toInt(),
        categoryId: m['category_id'] as String?,
        isShared: (m['is_shared'] as num? ?? 0) != 0,
        sortOrder: (m['sort_order'] as num? ?? 0).toInt(),
      );
}

/// A receipt photo or screenshot attached to a transaction. The row syncs with
/// everything else; the bytes live in the app's documents dir and are fetched
/// separately during sync.
class Attachment implements SyncedRecord {
  @override
  final SyncMeta meta;
  final String txnId;
  final String fileName; // "<id>.jpg"
  final String mime;
  final int size;
  final String sha256;

  const Attachment({
    required this.meta,
    required this.txnId,
    required this.fileName,
    required this.mime,
    required this.size,
    required this.sha256,
  });

  @override
  String get table => 'attachments';
  String get id => meta.id;

  @override
  Map<String, Object?> toMap() => {
        ...meta.toMap(),
        'txn_id': txnId,
        'file_name': fileName,
        'mime': mime,
        'size': size,
        'sha256': sha256,
      };

  static Attachment fromMap(Map<String, Object?> m) => Attachment(
        meta: SyncMeta.fromMap(m),
        txnId: m['txn_id'] as String,
        fileName: m['file_name'] as String,
        mime: m['mime'] as String,
        size: (m['size'] as num).toInt(),
        sha256: m['sha256'] as String,
      );
}

// ---------------------------------------------------------------------------
// Local-only records (never leave this phone)
// ---------------------------------------------------------------------------

enum SmsDirection { debit, credit }

enum SmsStatus { pending, added, dismissed }

/// A bank/UPI SMS that was parsed into a candidate transaction.
class SmsItem {
  final String id;
  final String sender;
  final String body;
  final String bodyHash;
  final int receivedAt;
  final int amountPaise;
  final SmsDirection direction;
  final String? merchant;
  final String? accountTail;
  final String? reference;
  final SmsStatus status;
  final String? txnId;

  const SmsItem({
    required this.id,
    required this.sender,
    required this.body,
    required this.bodyHash,
    required this.receivedAt,
    required this.amountPaise,
    required this.direction,
    required this.merchant,
    required this.accountTail,
    required this.reference,
    required this.status,
    required this.txnId,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'sender': sender,
        'body': body,
        'body_hash': bodyHash,
        'received_at': receivedAt,
        'amount': amountPaise,
        'direction': direction.name,
        'merchant': merchant,
        'account_tail': accountTail,
        'reference': reference,
        'status': status.name,
        'txn_id': txnId,
      };

  static SmsItem fromMap(Map<String, Object?> m) => SmsItem(
        id: m['id'] as String,
        sender: m['sender'] as String,
        body: m['body'] as String,
        bodyHash: m['body_hash'] as String,
        receivedAt: (m['received_at'] as num).toInt(),
        amountPaise: (m['amount'] as num).toInt(),
        direction: SmsDirection.values.byName(m['direction'] as String),
        merchant: m['merchant'] as String?,
        accountTail: m['account_tail'] as String?,
        reference: m['reference'] as String?,
        status: SmsStatus.values.byName(m['status'] as String),
        txnId: m['txn_id'] as String?,
      );

  SmsItem copyWith({SmsStatus? status, String? txnId}) => SmsItem(
        id: id,
        sender: sender,
        body: body,
        bodyHash: bodyHash,
        receivedAt: receivedAt,
        amountPaise: amountPaise,
        direction: direction,
        merchant: merchant,
        accountTail: accountTail,
        reference: reference,
        status: status ?? this.status,
        txnId: txnId ?? this.txnId,
      );
}

/// A paired device (the partner's phone). One row per device.
class Peer {
  final String deviceId;
  final String memberId;
  final String name;
  final String? lastAddress; // "192.168.1.23:47470"
  final int? lastSeenAt;
  final int? lastSyncAt;
  final int pairedAt;

  const Peer({
    required this.deviceId,
    required this.memberId,
    required this.name,
    required this.lastAddress,
    required this.lastSeenAt,
    required this.lastSyncAt,
    required this.pairedAt,
  });

  Map<String, Object?> toMap() => {
        'device_id': deviceId,
        'member_id': memberId,
        'name': name,
        'last_address': lastAddress,
        'last_seen_at': lastSeenAt,
        'last_sync_at': lastSyncAt,
        'paired_at': pairedAt,
      };

  static Peer fromMap(Map<String, Object?> m) => Peer(
        deviceId: m['device_id'] as String,
        memberId: m['member_id'] as String,
        name: m['name'] as String,
        lastAddress: m['last_address'] as String?,
        lastSeenAt: (m['last_seen_at'] as num?)?.toInt(),
        lastSyncAt: (m['last_sync_at'] as num?)?.toInt(),
        pairedAt: (m['paired_at'] as num).toInt(),
      );

  Peer copyWith({String? name, String? lastAddress, int? lastSeenAt, int? lastSyncAt}) =>
      Peer(
        deviceId: deviceId,
        memberId: memberId,
        name: name ?? this.name,
        lastAddress: lastAddress ?? this.lastAddress,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        pairedAt: pairedAt,
      );
}

enum SyncMethod { lan, bundleOut, bundleIn }

enum SyncOutcome { ok, failed }

class SyncLogEntry {
  final String id;
  final String peerName;
  final int startedAt;
  final int? finishedAt;
  final SyncMethod method;
  final SyncOutcome outcome;
  final int sent;
  final int received;
  final int attachmentsSent;
  final int attachmentsReceived;
  final String? detail;

  const SyncLogEntry({
    required this.id,
    required this.peerName,
    required this.startedAt,
    required this.finishedAt,
    required this.method,
    required this.outcome,
    required this.sent,
    required this.received,
    required this.attachmentsSent,
    required this.attachmentsReceived,
    required this.detail,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'peer_name': peerName,
        'started_at': startedAt,
        'finished_at': finishedAt,
        'method': method.name,
        'outcome': outcome.name,
        'sent': sent,
        'received': received,
        'att_sent': attachmentsSent,
        'att_received': attachmentsReceived,
        'detail': detail,
      };

  static SyncLogEntry fromMap(Map<String, Object?> m) => SyncLogEntry(
        id: m['id'] as String,
        peerName: m['peer_name'] as String,
        startedAt: (m['started_at'] as num).toInt(),
        finishedAt: (m['finished_at'] as num?)?.toInt(),
        method: SyncMethod.values.byName(m['method'] as String),
        outcome: SyncOutcome.values.byName(m['outcome'] as String),
        sent: (m['sent'] as num).toInt(),
        received: (m['received'] as num).toInt(),
        attachmentsSent: (m['att_sent'] as num? ?? 0).toInt(),
        attachmentsReceived: (m['att_received'] as num? ?? 0).toInt(),
        detail: m['detail'] as String?,
      );
}
