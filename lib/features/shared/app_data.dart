import 'package:flutter/foundation.dart' hide Category;

import '../../data/models.dart';
import '../../data/repository.dart';

/// Small, hot data every screen needs synchronously (members, categories,
/// budgets, balance…). Reloads whenever the repository reports a change.
class AppData extends ChangeNotifier {
  AppData(this.repo) {
    repo.addListener(_scheduleReload);
  }

  final Repository repo;

  List<Member> members = const [];
  Member? me;
  Member? partner;
  Map<String, Category> categories = const {};
  List<Category> expenseCategories = const [];
  List<Category> incomeCategories = const [];
  List<QuickAdd> quickAdds = const [];
  List<Budget> budgets = const [];
  Balance? balance;
  int pendingSms = 0;
  List<Peer> peers = const [];
  bool loaded = false;

  bool _reloading = false;
  bool _again = false;

  void _scheduleReload() => reload();

  Future<void> reload() async {
    if (!repo.isSetUp) return;
    if (_reloading) {
      _again = true;
      return;
    }
    _reloading = true;
    try {
      members = await repo.members();
      me = members.where((m) => m.id == repo.identity.memberId).firstOrNull;
      partner = members.where((m) => m.id != repo.identity.memberId).firstOrNull;
      final cats = await repo.categories();
      categories = {for (final c in cats) c.id: c};
      expenseCategories = cats.where((c) => c.kind == CategoryKind.expense).toList();
      incomeCategories = cats.where((c) => c.kind == CategoryKind.income).toList();
      quickAdds = await repo.quickAdds();
      budgets = await repo.budgets();
      balance = await repo.balance();
      pendingSms = await repo.pendingSmsCount();
      peers = await repo.peers();
      loaded = true;
    } finally {
      _reloading = false;
    }
    notifyListeners();
    if (_again) {
      _again = false;
      await reload();
    }
  }

  Member? member(String id) => members.where((m) => m.id == id).firstOrNull;

  String memberName(String id) =>
      member(id)?.name ?? peers.where((p) => p.memberId == id).firstOrNull?.name ?? 'Partner';

  /// Partner name even before the first sync (from the paired peer record).
  String get partnerName => partner?.name ?? peers.firstOrNull?.name ?? 'Partner';

  Category? category(String? id) => id == null ? null : categories[id];

  @override
  void dispose() {
    repo.removeListener(_scheduleReload);
    super.dispose();
  }
}
