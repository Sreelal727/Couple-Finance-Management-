import 'package:intl/intl.dart';

class Dates {
  Dates._();

  static int nowMs() => DateTime.now().millisecondsSinceEpoch;

  static DateTime fromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

  static DateTime nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1);

  static String monthLabel(DateTime d) => DateFormat('MMMM yyyy').format(d);

  static String shortMonth(DateTime d) => DateFormat('MMM').format(d);

  static String dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (d.year == now.year) return DateFormat('EEE, d MMM').format(d);
    return DateFormat('d MMM yyyy').format(d);
  }

  static String dateTime(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);

  static String time(DateTime d) => DateFormat('h:mm a').format(d);

  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return DateFormat('d MMM').format(d);
  }
}
