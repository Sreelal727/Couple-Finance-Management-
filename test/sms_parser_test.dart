import 'package:duo_finance/data/models.dart';
import 'package:duo_finance/sms/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmsParser debits', () {
    test('SBI UPI', () {
      final p = SmsParser.parse('VM-SBIUPI',
          'Dear UPI user A/C X1234 debited by 450.0 on date 05Sep25 trf to SWIGGY Refno 525011223344. If not u? call 1800111109. -SBI');
      expect(p, isNotNull);
      expect(p!.amountPaise, 45000);
      expect(p.direction, SmsDirection.debit);
      expect(p.merchant, 'Swiggy');
      expect(p.accountTail, '1234');
      expect(p.reference, '525011223344');
    });

    test('SBI IMPS transfer with balance', () {
      final p = SmsParser.parse('AD-SBIINB',
          'Your A/C XXXXX1234 Debited INR 1,250.00 on 05/09/25 -Transfer to Mr RAJESH KUMAR. Avl Bal INR 12,345.67-SBI');
      expect(p!.amountPaise, 125000);
      expect(p.direction, SmsDirection.debit);
      expect(p.merchant, 'Mr Rajesh Kumar');
    });

    test('HDFC UPI sent', () {
      final p = SmsParser.parse('VM-HDFCBK',
          'Sent Rs.500.00 From HDFC Bank A/C *1234 To ZOMATO On 05/09/25 Ref 525012345678 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808');
      expect(p!.amountPaise, 50000);
      expect(p.direction, SmsDirection.debit);
      expect(p.merchant, 'Zomato');
      expect(p.reference, '525012345678');
      expect(p.accountTail, '1234');
    });

    test('HDFC VPA', () {
      final p = SmsParser.parse('VM-HDFCBK',
          'Rs.1200.00 debited from a/c **1234 on 05-09-25 to VPA lulu.hyper@ybl (UPI Ref No 525012345678). Not you? Call 18002586161');
      expect(p!.amountPaise, 120000);
      expect(p.merchant, 'lulu hyper');
      expect(p.reference, '525012345678');
    });

    test('HDFC card spend', () {
      final p = SmsParser.parse('VM-HDFCBK',
          'Rs 850.00 spent on HDFC Bank Card x1234 at AMAZON on 2025-09-05:14:30:22.Avl bal Rs 50000.00');
      expect(p!.amountPaise, 85000);
      expect(p.direction, SmsDirection.debit);
      expect(p.merchant, 'Amazon');
      expect(p.accountTail, '1234');
    });

    test('ICICI debit with counterparty credited', () {
      final p = SmsParser.parse('JD-ICICIB',
          'ICICI Bank Acct XX123 debited for Rs 300.00 on 05-Sep-25; RAJESH KUMAR credited. UPI:525012345678. Call 18002662 for dispute.');
      expect(p!.amountPaise, 30000);
      expect(p.direction, SmsDirection.debit);
      expect(p.merchant, 'Rajesh Kumar');
      expect(p.reference, '525012345678');
    });

    test('Axis UPI P2M', () {
      final p = SmsParser.parse('AX-AXISBK',
          'INR 240.00 debited A/c no. XX1234 05-09-25 12:30:11 IST UPI/P2M/525012345678/Uber India. Not you? SMS BLOCKUPI Cust ID to 919951860002 - Axis Bank');
      expect(p!.amountPaise, 24000);
      expect(p.merchant, 'Uber India');
      expect(p.accountTail, '1234');
    });

    test('Kotak', () {
      final p = SmsParser.parse('VK-KOTAKB',
          'Sent Rs.120.00 from Kotak Bank AC X1234 to q2tea@ybl on 05-09-25.UPI Ref 525012345678. Not you, kotak.com/fraud');
      expect(p!.amountPaise, 12000);
      expect(p.merchant, 'q2tea');
    });

    test('Federal Bank', () {
      final p = SmsParser.parse('VM-FEDBNK',
          'Rs 1,000.00 debited from your A/c XX1234 on 05-09-2025 towards UPI/525012345678/Lulu Hypermarket. Avl Bal Rs 5,000.00 -Federal Bank');
      expect(p!.amountPaise, 100000);
      expect(p.merchant, 'Lulu Hypermarket');
      expect(p.reference, '525012345678');
    });

    test('South Indian Bank', () {
      final p = SmsParser.parse('VM-SIBSMS',
          'Your A/c XX1234 is debited with Rs.560.00 on 05-09-25 for UPI-525012345678-BIG BAZAAR. Bal: Rs.1200.00. -SIB');
      expect(p!.amountPaise, 56000);
      expect(p.merchant, 'Big Bazaar');
    });

    test('Paytm wallet', () {
      final p = SmsParser.parse('VM-PAYTMB', 'Paid Rs.99 to Jio Prepaid from Paytm Wallet. Txn ID 12345678901');
      expect(p!.amountPaise, 9900);
      expect(p.direction, SmsDirection.debit);
      expect(p.merchant, 'Jio Prepaid');
    });
  });

  group('SmsParser credits', () {
    test('ICICI salary credit', () {
      final p = SmsParser.parse('JD-ICICIB',
          'Dear Customer, Acct XX123 is credited with Rs 50,000.00 on 01-Sep-25 from INFOSYS SALARY. Info: NEFT. Avl Bal Rs 62,345.00');
      expect(p!.amountPaise, 5000000);
      expect(p.direction, SmsDirection.credit);
      expect(p.merchant, 'Infosys Salary');
    });

    test('refund is credit', () {
      final p = SmsParser.parse('VM-HDFCBK',
          'Refund of Rs.450.00 credited to your HDFC Bank A/c 1234 from SWIGGY on 05-09-25. Ref 5250123');
      expect(p!.direction, SmsDirection.credit);
      expect(p.amountPaise, 45000);
    });
  });

  group('SmsParser ignores', () {
    test('OTP', () {
      expect(SmsParser.parse('AD-HDFCBK', '123456 is your OTP for txn of Rs 500 at Amazon. Do not share.'), isNull);
    });
    test('request', () {
      expect(SmsParser.parse('VM-PHONEP', 'Rajesh has requested Rs 500 from you on PhonePe. Pay now'), isNull);
    });
    test('future debit', () {
      expect(SmsParser.parse('AD-SBIINB', 'Rs 1499 will be debited from A/c X1234 on 10-09-25 for Netflix AutoPay'), isNull);
    });
    test('failed', () {
      expect(SmsParser.parse('VM-HDFCBK', 'Your UPI txn of Rs 500 to Zomato has failed. Amount will be reversed.'), isNull);
    });
    test('personal message', () {
      expect(SmsParser.parse('+919876543210', 'I paid Rs 500 for dinner, you owe me'), isNull);
    });
    test('promo', () {
      expect(SmsParser.parse('VM-BAJAJF', 'Pre-approved loan of Rs 5,00,000 for you! Apply now'), isNull);
    });
  });

  test('hash is stable across whitespace', () {
    expect(SmsParser.hash('X', 'a  b\n c'), SmsParser.hash('x', 'a b c '));
  });
}
