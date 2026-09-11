import 'models.dart';

class DefaultCategory {
  final String id;
  final String name;
  final String icon;
  final String colorHex;
  final CategoryKind kind;
  const DefaultCategory(this.id, this.name, this.icon, this.colorHex, this.kind);
}

/// Fixed ids so both phones get identical defaults and sync doesn't create
/// duplicates when each phone seeds its own copy.
const defaultCategories = <DefaultCategory>[
  DefaultCategory('cat-rent', 'Rent & Maintenance', 'home', '#3A6EA5', CategoryKind.expense),
  DefaultCategory('cat-groceries', 'Groceries', 'grocery', '#2A9D8F', CategoryKind.expense),
  DefaultCategory('cat-food', 'Eating Out', 'restaurant', '#E76F51', CategoryKind.expense),
  DefaultCategory('cat-transport', 'Transport', 'transport', '#F4A261', CategoryKind.expense),
  DefaultCategory('cat-fuel', 'Fuel', 'fuel', '#8D6E63', CategoryKind.expense),
  DefaultCategory('cat-utilities', 'Electricity & Water', 'bolt', '#EDAE49', CategoryKind.expense),
  DefaultCategory('cat-internet', 'Internet & Mobile', 'wifi', '#6A4C93', CategoryKind.expense),
  DefaultCategory('cat-household', 'Household', 'household', '#588157', CategoryKind.expense),
  DefaultCategory('cat-health', 'Health', 'health', '#D1495B', CategoryKind.expense),
  DefaultCategory('cat-shopping', 'Shopping', 'shopping', '#BC6C25', CategoryKind.expense),
  DefaultCategory('cat-subscriptions', 'Subscriptions', 'subscriptions', '#457B9D', CategoryKind.expense),
  DefaultCategory('cat-entertainment', 'Entertainment', 'movie', '#9B5DE5', CategoryKind.expense),
  DefaultCategory('cat-family', 'Family & Gifts', 'gift', '#F15BB5', CategoryKind.expense),
  DefaultCategory('cat-travel', 'Travel', 'travel', '#00BBF9', CategoryKind.expense),
  DefaultCategory('cat-personal', 'Personal Care', 'spa', '#FF8FAB', CategoryKind.expense),
  DefaultCategory('cat-investment', 'Investments', 'investment', '#0E7C7B', CategoryKind.expense),
  DefaultCategory('cat-other', 'Other', 'other', '#6C757D', CategoryKind.expense),
  DefaultCategory('inc-salary', 'Salary', 'salary', '#0E7C7B', CategoryKind.income),
  DefaultCategory('inc-freelance', 'Freelance', 'work', '#3A6EA5', CategoryKind.income),
  DefaultCategory('inc-interest', 'Interest & Returns', 'interest', '#2A9D8F', CategoryKind.income),
  DefaultCategory('inc-gift', 'Gift Received', 'gift', '#F15BB5', CategoryKind.income),
  DefaultCategory('inc-other', 'Other Income', 'other', '#6C757D', CategoryKind.income),
];
