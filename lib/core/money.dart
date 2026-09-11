import 'package:intl/intl.dart';

/// All amounts are stored as integer paise to avoid floating point drift.
/// These helpers convert between paise and rupee strings for the UI.
class Money {
  Money._();

  static final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final NumberFormat _inrPaise = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  /// Formats paise as ₹1,23,456 (no paise if the amount is whole rupees).
  static String format(int paise, {bool showPaise = false}) {
    final rupees = paise / 100;
    if (showPaise || paise % 100 != 0) return _inrPaise.format(rupees);
    return _inr.format(rupees);
  }

  /// Formats a signed amount with an explicit +/- prefix.
  static String signed(int paise) {
    if (paise == 0) return format(0);
    return (paise > 0 ? '+' : '-') + format(paise.abs());
  }

  /// Parses user input like "1,250.50" or "₹ 300" into paise. Returns null if
  /// nothing numeric is found.
  static int? parse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return (value * 100).round();
  }

  /// Rupee string for editing (no symbol, no grouping).
  static String editable(int paise) {
    if (paise % 100 == 0) return (paise ~/ 100).toString();
    return (paise / 100).toStringAsFixed(2);
  }
}
