import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../sms/notifications.dart';
import '../../sync/attachment_store.dart';
import '../shared/app_data.dart';
import '../shared/attachment_picker.dart';
import '../shared/widgets.dart';

/// Values to pre-populate the form with (from an SMS, a quick-add chip, a
/// shared screenshot, or an existing entry being edited).
class TxnPrefill {
  final TxnType type;
  final int? amountPaise;
  final String? title;
  final String? merchant;
  final String? categoryId;
  final bool? isShared;
  final int? occurredAt;
  final TxnSource source;
  final String? smsRef;
  final String? smsItemId;
  final List<PendingImage> images;

  const TxnPrefill({
    this.type = TxnType.expense,
    this.amountPaise,
    this.title,
    this.merchant,
    this.categoryId,
    this.isShared,
    this.occurredAt,
    this.source = TxnSource.manual,
    this.smsRef,
    this.smsItemId,
    this.images = const [],
  });
}

/// Full-screen add / edit form. Returns the saved [Txn] or null.
class AddTxnPage extends StatefulWidget {
  const AddTxnPage({super.key, this.existing, this.prefill});
  final Txn? existing;
  final TxnPrefill? prefill;

  static Future<Txn?> open(BuildContext context, {Txn? existing, TxnPrefill? prefill}) {
    return Navigator.of(context).push<Txn>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddTxnPage(existing: existing, prefill: prefill),
      ),
    );
  }

  @override
  State<AddTxnPage> createState() => _AddTxnPageState();
}

enum _Split { equal, allPartner, custom }

class _AddTxnPageState extends State<AddTxnPage> {
  late TxnType _type;
  late final TextEditingController _amount;
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _customShare;
  final FocusNode _titleFocus = FocusNode();
  String? _categoryId;
  late DateTime _when;
  late String _paidBy;
  late bool _shared;
  _Split _split = _Split.equal;
  final List<PendingImage> _newImages = [];
  List<Attachment> _existingAtts = const [];
  List<String> _titleSuggestions = const [];
  bool _saving = false;
  bool _suggestedCategory = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<Repository>();
    final e = widget.existing;
    final p = widget.prefill;
    _type = e?.type ?? p?.type ?? TxnType.expense;
    _amount = TextEditingController(
      text: e != null ? Money.editable(e.amountPaise) : (p?.amountPaise != null ? Money.editable(p!.amountPaise!) : ''),
    );
    _title = TextEditingController(text: e?.title ?? p?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _categoryId = e?.categoryId ?? p?.categoryId;
    _when = Dates.fromMs(e?.occurredAt ?? p?.occurredAt ?? Dates.nowMs());
    _paidBy = e?.paidBy ?? repo.identity.memberId;
    _shared = e?.isShared ?? p?.isShared ?? (_type == TxnType.expense);
    _customShare = TextEditingController();
    if (e != null && e.isShared) {
      if (e.payerSharePaise == 0) {
        _split = _Split.allPartner;
      } else if (e.payerSharePaise * 2 == e.amountPaise || (e.payerSharePaise * 2 - e.amountPaise).abs() == 1) {
        _split = _Split.equal;
      } else {
        _split = _Split.custom;
        _customShare.text = Money.editable(e.payerSharePaise);
      }
    }
    _newImages.addAll(p?.images ?? const []);
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<Repository>();
    if (widget.existing != null) {
      _existingAtts = await repo.attachmentsFor(widget.existing!.id);
    }
    _titleSuggestions = await repo.recentTitles();
    final p = widget.prefill;
    if (widget.existing == null && p != null) {
      if (_categoryId == null) {
        _categoryId = await repo.suggestCategoryForMerchant(p.merchant);
        _suggestedCategory = _categoryId != null;
      }
      if (_title.text.isEmpty) {
        _title.text = await repo.lastTitleForMerchant(p.merchant) ?? '';
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _note.dispose();
    _customShare.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  int? get _amountPaise => Money.parse(_amount.text);

  int _payerShare(int amount) {
    if (!_shared || _type != TxnType.expense) return amount;
    switch (_split) {
      case _Split.equal:
        return (amount / 2).round();
      case _Split.allPartner:
        return 0;
      case _Split.custom:
        final v = Money.parse(_customShare.text) ?? (amount / 2).round();
        return v.clamp(0, amount);
    }
  }

  Future<void> _save() async {
    final amount = _amountPaise;
    if (amount == null || amount <= 0) {
      showSnack(context, 'Enter an amount');
      return;
    }
    setState(() => _saving = true);
    final repo = context.read<Repository>();
    final store = context.read<AttachmentStore>();
    final p = widget.prefill;
    final e = widget.existing;
    final txn = Txn(
      meta: e?.meta ?? repo.newMeta(),
      type: _type,
      amountPaise: amount,
      categoryId: _categoryId,
      title: _title.text.trim(),
      note: _note.text.trim(),
      merchant: e?.merchant ?? p?.merchant,
      occurredAt: _when.millisecondsSinceEpoch,
      paidBy: _paidBy,
      isShared: _type == TxnType.expense && _shared,
      payerSharePaise: _payerShare(amount),
      source: e?.source ?? p?.source ?? TxnSource.manual,
      smsRef: e?.smsRef ?? p?.smsRef,
    );
    await repo.save(txn);
    for (final img in _newImages) {
      await store.add(txn.id, img.bytes, mime: img.mime);
    }
    if (p?.smsItemId != null) {
      final item = await repo.smsById(p!.smsItemId!);
      if (item != null) await repo.updateSms(item.copyWith(status: SmsStatus.added, txnId: txn.id));
      await Notifications.cancelFor(p.smsItemId!);
    }
    if (mounted) Navigator.pop(context, txn);
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final scheme = Theme.of(context).colorScheme;
    final isExpense = _type == TxnType.expense;
    final cats = isExpense ? data.expenseCategories : data.incomeCategories;
    final amount = _amountPaise ?? 0;
    final payerName = data.memberName(_paidBy);
    final otherId = data.members.where((m) => m.id != _paidBy).firstOrNull?.id ?? data.peers.firstOrNull?.memberId;
    final otherName = otherId == null ? data.partnerName : data.memberName(otherId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? (isExpense ? 'Add expense' : 'Add income') : 'Edit'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.existing == null)
            SegmentedButton<TxnType>(
              segments: const [
                ButtonSegment(value: TxnType.expense, label: Text('Expense'), icon: Icon(Icons.arrow_upward_rounded)),
                ButtonSegment(value: TxnType.income, label: Text('Income'), icon: Icon(Icons.arrow_downward_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _categoryId = null;
              }),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: widget.existing == null && (widget.prefill?.amountPaise == null),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
            decoration: const InputDecoration(prefixText: '₹ ', hintText: '0', border: InputBorder.none),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.prefill?.merchant != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.sms_rounded, size: 14, color: scheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'From bank SMS · ${widget.prefill!.merchant}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Autocomplete<String>(
            textEditingController: _title,
            focusNode: _titleFocus,
            optionsBuilder: (v) {
              final q = v.text.toLowerCase().trim();
              if (q.isEmpty) return const Iterable<String>.empty();
              return _titleSuggestions.where((t) => t.toLowerCase().contains(q)).take(6);
            },
            onSelected: (v) => _title.text = v,
            fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
              return TextField(
                controller: ctrl,
                focusNode: focus,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: isExpense ? 'What was it for?' : 'Source',
                  hintText: isExpense ? 'e.g. Groceries at Lulu, Auto to office' : 'e.g. September salary',
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Category', style: Theme.of(context).textTheme.titleSmall),
              if (_suggestedCategory) ...[
                const SizedBox(width: 8),
                Text('suggested from past entries', style: TextStyle(color: scheme.outline, fontSize: 12)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in cats)
                ChoiceChip(
                  avatar: CategoryIcon(category: c, size: 22),
                  label: Text(c.name),
                  selected: _categoryId == c.id,
                  onSelected: (_) => setState(() {
                    _categoryId = c.id;
                    _suggestedCategory = false;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(Dates.dayLabel(_when)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _when,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (d != null) setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(Dates.time(_when)),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
                    if (t != null) {
                      setState(() => _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(isExpense ? 'Who paid?' : 'Who received it?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in data.members)
                ChoiceChip(
                  avatar: MemberAvatar(member: m, radius: 10),
                  label: Text(m.name),
                  selected: _paidBy == m.id,
                  onSelected: (_) => setState(() => _paidBy = m.id),
                ),
              if (data.members.length < 2)
                for (final p in data.peers)
                  ChoiceChip(
                    avatar: MemberAvatar(member: null, name: p.name, radius: 10),
                    label: Text(p.name),
                    selected: _paidBy == p.memberId,
                    onSelected: (_) => setState(() => _paidBy = p.memberId),
                  ),
            ],
          ),
          if (isExpense) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shared expense'),
              subtitle: Text(_shared ? 'Counts towards what you owe each other' : 'Personal, only $payerName'),
              value: _shared,
              onChanged: (v) => setState(() => _shared = v),
            ),
            if (_shared) ...[
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Split 50/50'),
                    selected: _split == _Split.equal,
                    onSelected: (_) => setState(() => _split = _Split.equal),
                  ),
                  ChoiceChip(
                    label: Text('$otherName owes all'),
                    selected: _split == _Split.allPartner,
                    onSelected: (_) => setState(() => _split = _Split.allPartner),
                  ),
                  ChoiceChip(
                    label: const Text('Custom'),
                    selected: _split == _Split.custom,
                    onSelected: (_) => setState(() => _split = _Split.custom),
                  ),
                ],
              ),
              if (_split == _Split.custom)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: _customShare,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: "$payerName's share (₹)",
                      helperText: 'The rest is owed by $otherName',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              if (amount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$otherName owes $payerName ${Money.format(amount - _payerShare(amount))}',
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optional)', prefixIcon: Icon(Icons.notes_rounded)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Receipt / screenshot', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                label: const Text('Add'),
                onPressed: () async {
                  final img = await pickAttachment(context);
                  if (img != null) setState(() => _newImages.add(img));
                },
              ),
            ],
          ),
          if (_newImages.isNotEmpty || _existingAtts.isNotEmpty)
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final a in _existingAtts)
                    _ExistingThumb(
                      att: a,
                      onDelete: () async {
                        await context.read<AttachmentStore>().delete(a);
                        setState(() => _existingAtts = _existingAtts.where((x) => x.id != a.id).toList());
                      },
                    ),
                  for (var i = 0; i < _newImages.length; i++)
                    _Thumb(bytes: _newImages[i].bytes, onDelete: () => setState(() => _newImages.removeAt(i))),
                ],
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(widget.existing == null ? 'Add' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.bytes, required this.onDelete});
  final Uint8List bytes;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, width: 96, height: 96, fit: BoxFit.cover),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton.filledTonal(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded),
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExistingThumb extends StatelessWidget {
  const _ExistingThumb({required this.att, required this.onDelete});
  final Attachment att;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AttachmentStore>();
    return FutureBuilder<Uint8List?>(
      future: store.read(att),
      builder: (ctx, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            width: 96,
            height: 96,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_download_outlined),
          );
        }
        return _Thumb(bytes: bytes, onDelete: onDelete);
      },
    );
  }
}
