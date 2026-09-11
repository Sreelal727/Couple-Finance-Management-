import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/models.dart';

/// What we could extract from a bank / UPI alert.
class ParsedSms {
  final int amountPaise;
  final SmsDirection direction;
  final String? merchant;
  final String? accountTail;
  final String? reference;
  const ParsedSms({
    required this.amountPaise,
    required this.direction,
    required this.merchant,
    required this.accountTail,
    required this.reference,
  });

  @override
  String toString() => 'ParsedSms($amountPaise ${direction.name} merchant=$merchant acct=$accountTail ref=$reference)';
}

/// Pure-Dart parser for Indian bank transaction SMS (SBI, HDFC, ICICI, Axis,
/// Kotak, Federal, SIB, Canara, BoB, IDFC, Paytm and most others). It is
/// intentionally conservative: anything that looks like an OTP, a request, a
/// failed transaction or a promotion is ignored.
class SmsParser {
  SmsParser._();

  static final _ws = RegExp(r'\s+');

  static final _ignore = RegExp(
    r'\b(otp|one[- ]time password|verification code|has requested|payment request|requested (?:rs|inr|money)|'
    r'will be (?:debited|deducted|charged)|is due|due on|auto[- ]?pay|e-?mandate|mandate|standing instruction|'
    r'declined|failed|unsuccessful|could not be processed|not processed|insufficient|'
    r'apply now|pre-?approved|offer|emi of|cashback of up to|loan of|win |congratulations|'
    r'statement|password|login|kyc|block(?:ed)? your|expire)\b',
    caseSensitive: false,
  );

  static final _debit = RegExp(
    r'\b(debited|debit(?:ed)?\b|spent|sent|paid|payment of|withdrawn|purchase(?:d)?|txn of|'
    r'transaction of|transferred|charged|deducted|dr\b)',
    caseSensitive: false,
  );
  static final _credit = RegExp(
    r'\b(credited|credit(?:ed)?\b|received|deposited|refund(?:ed)?|reversed|reversal|cashback|cr\b)',
    caseSensitive: false,
  );

  static const _num = r'[0-9]+(?:,[0-9]+)*(?:\.[0-9]{1,2})?';
  static final _amount = RegExp(
    '(?:(?:INR|Rs\\.?|₹|MRP)\\s*:?\\s*($_num))'
    '|(?:($_num)\\s*(?:INR|Rs\\.?|rupees))'
    '|(?:debited by\\s+($_num))',
    caseSensitive: false,
  );

  static final _balanceWord = RegExp(r'\b(avl|available|avail|bal|balance|limit)\b', caseSensitive: false);

  static final _accountTail = RegExp(
    r'(?:a/?c|acct|account|card|ac|xx|ending)\s*(?:no\.?\s*)?[Xx*]*\s*[Xx*]*([0-9]{3,6})\b',
    caseSensitive: false,
  );

  static final _reference = RegExp(
    r'(?:ref(?:erence)?(?:\s*no)?\.?|refno|utr|txn\s*(?:id|no)|transaction\s*(?:id|no)|upi(?:\s*ref)?(?:\s*no)?)[:\s./-]*([0-9]{6,})',
    caseSensitive: false,
  );
  static final _upiSlashRef = RegExp(r'UPI[/:-]\s*(?:P2[MA][/:-])?\s*([0-9]{9,})', caseSensitive: false);

  static final _merchantPatterns = <RegExp>[
    // "to VPA swiggy.upi@icici" / "to VPA rajesh@okaxis"
    RegExp(r'\b(?:to|at|towards|for)\s+VPA\s+([\w.\-]+)@[\w.\-]+', caseSensitive: false),
    // "UPI/P2M/525012345678/Uber India" (Axis)
    RegExp(r'UPI/(?:P2[MA])/[0-9]+/([^/.;\n]+?)(?:/|\.|;|\s+Not\b|$)', caseSensitive: false),
    // "towards UPI/525012345678/Lulu Hypermarket" (Federal), "UPI-5250-BIG BAZAAR" (SIB)
    RegExp(r'UPI[/-][0-9]{6,}[/-]([^/.;\n]+?)(?:\.|;|/|\s+Avl\b|\s+Bal\b|$)', caseSensitive: false),
    // "trf to SWIGGY Refno" (SBI UPI)
    RegExp(r'\btrf to\s+(.+?)\s+Ref', caseSensitive: false),
    // "Transfer to Mr RAJESH KUMAR." (SBI NEFT/IMPS)
    RegExp(r'\btransfer to\s+([^.;\n]+?)(?:\.|;|\s+Avl\b|$)', caseSensitive: false),
    // "; RAJESH KUMAR credited." (ICICI)
    RegExp(r';\s*([^;.\n]+?)\s+credited', caseSensitive: false),
    // "from SALARY", "from RAJESH" (credits)
    RegExp(
      r"\bfrom\s+(?!your\b|a/?c\b|account\b|acct\b|hdfc\b|icici\b|sbi\b|axis\b|kotak\b|federal\b|paytm\b)([A-Za-z][A-Za-z0-9 &'.\-]{2,40}?)(?:\s+on\b|\s+Ref\b|\s+UPI\b|\s+\(|\.|,|;|$)",
      caseSensitive: false,
    ),
    // "To ZOMATO On", "at AMAZON on", "to q2@ybl on", "towards Lulu on"
    RegExp(
      r"\b(?:to|at|towards)\s+(?!VPA\b|your\b|a/?c\b|account\b)([A-Za-z0-9][A-Za-z0-9 &'.@\-]{1,40}?)(?:\s+on\b|\s+Ref\b|\s+UPI\b|\s+via\b|\s+from\b|\s+\(|\.\s|\.$|,|;|$)",
      caseSensitive: false,
    ),
    // "Info: UPI/DR/..."; "Info: ZOMATO"
    RegExp(r'\bInfo:\s*(?:UPI/(?:DR|CR)/[0-9]+/)?([^/.;\n]+)', caseSensitive: false),
  ];

  static final _senderIsPerson = RegExp(r'^\+?[0-9]{10,}$');

  /// Stable hash of the body used for deduplication across re-scans.
  static String hash(String sender, String body) =>
      sha256.convert(utf8.encode('${sender.trim().toUpperCase()}|${normalize(body)}')).toString();

  static String normalize(String body) => body.replaceAll(_ws, ' ').trim();

  static ParsedSms? parse(String sender, String rawBody) {
    if (_senderIsPerson.hasMatch(sender.trim())) return null;
    final body = normalize(rawBody);
    if (body.length < 15) return null;
    if (_ignore.hasMatch(body)) return null;

    final debitMatch = _debit.firstMatch(body);
    final creditMatch = _credit.firstMatch(body);
    if (debitMatch == null && creditMatch == null) return null;

    SmsDirection direction;
    if (debitMatch != null && creditMatch != null) {
      // ICICI style: "Acct XX123 debited for Rs 300; RAJESH credited" — the
      // first keyword describes what happened to *our* account.
      direction = debitMatch.start <= creditMatch.start ? SmsDirection.debit : SmsDirection.credit;
      // "refund"/"reversal" anywhere means money came back.
      if (RegExp(r'\b(refund|revers)', caseSensitive: false).hasMatch(body)) direction = SmsDirection.credit;
    } else {
      direction = debitMatch != null ? SmsDirection.debit : SmsDirection.credit;
    }

    final amount = _extractAmount(body);
    if (amount == null || amount <= 0) return null;

    return ParsedSms(
      amountPaise: amount,
      direction: direction,
      merchant: _extractMerchant(body),
      accountTail: _accountTail.firstMatch(body)?.group(1)?.let((s) => s.length > 4 ? s.substring(s.length - 4) : s),
      reference: _reference.firstMatch(body)?.group(1) ?? _upiSlashRef.firstMatch(body)?.group(1),
    );
  }

  static int? _extractAmount(String body) {
    for (final m in _amount.allMatches(body)) {
      final raw = m.group(1) ?? m.group(2) ?? m.group(3);
      if (raw == null) continue;
      // Skip balances: "Avl Bal Rs 5,000" / "Bal: Rs.1200"
      final before = body.substring(m.start < 18 ? 0 : m.start - 18, m.start);
      if (_balanceWord.hasMatch(before)) continue;
      final value = double.tryParse(raw.replaceAll(',', ''));
      if (value == null) continue;
      return (value * 100).round();
    }
    return null;
  }

  static String? _extractMerchant(String body) {
    for (final p in _merchantPatterns) {
      final m = p.firstMatch(body);
      if (m == null) continue;
      final cleaned = _cleanMerchant(m.group(1)!);
      if (cleaned != null) return cleaned;
    }
    return null;
  }

  static String? _cleanMerchant(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'\s+(on|ref|refno|upi|via|info)$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'[.,;:\-\s]+$'), '').replaceAll(RegExp(r'^[.,;:\-\s]+'), '');
    // Drop pure numbers / dates / ids.
    if (s.isEmpty || RegExp(r'^[0-9/\-: ]+$').hasMatch(s)) return null;
    if (s.length < 2 || s.length > 48) return null;
    if (RegExp(r'^(your|you|the|a|an|this|that|mr|ms|mrs)$', caseSensitive: false).hasMatch(s)) return null;
    // UPI handle: keep the part before '@'
    if (s.contains('@')) s = s.split('@').first;
    s = s.replaceAll(RegExp(r'[._]+'), ' ').trim();
    // SHOUTING (or mostly shouting, "Mr RAJESH KUMAR") → Title Case
    final upper = RegExp(r'[A-Z]').allMatches(s).length;
    final lower = RegExp(r'[a-z]').allMatches(s).length;
    if (upper > lower && s.length > 3) {
      s = s.toLowerCase().split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    }
    return s;
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
