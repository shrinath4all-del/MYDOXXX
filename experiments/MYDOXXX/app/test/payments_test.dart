import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/firestore_service.dart';
import 'package:mydox/services/payment_service.dart';
import 'package:mydox/utils/validators.dart';
import 'package:mydox/utils/ist_clock.dart';

void main() {
  group('bank detail checks', () {
    test('PAN must be a personal PAN', () {
      expect(Validators.pan('ABCPA1234Z'), isNull);
      expect(Validators.pan('abcpa1234z'), isNull);
      expect(Validators.pan('ABCCA1234Z'), isNotNull); // company PAN
      expect(Validators.pan('ABCPA12345'), isNotNull);
      expect(Validators.pan(''), isNotNull);
    });

    test('IFSC, account number and PIN code', () {
      expect(Validators.ifsc('HDFC0001234'), isNull);
      expect(Validators.ifsc('HDFC1001234'), isNotNull); // 5th char must be 0
      expect(Validators.bankAccount('123456789012'), isNull);
      expect(Validators.bankAccount('12345678'), isNotNull);
      expect(Validators.bankAccount('12345abc901'), isNotNull);
      expect(Validators.pincode('411005'), isNull);
      expect(Validators.pincode('011005'), isNotNull);
    });
  });

  group('payment states', () {
    test('patient can pay only an accepted, unpaid booking', () {
      expect(
          PaymentService.canPayNow(
              {'status': 'Confirmed', 'paymentStatus': 'pending'}),
          isTrue);
      expect(
          PaymentService.canPayNow(
              {'status': 'Pending Home Visit', 'paymentStatus': 'pending'}),
          isFalse);
      expect(
          PaymentService.canPayNow(
              {'status': 'Confirmed', 'paymentStatus': 'paid'}),
          isFalse);
      // bookings from before online payment are not affected
      expect(PaymentService.canPayNow({'status': 'Confirmed'}), isFalse);
    });

    test('provider payout status', () {
      expect(PaymentService.payoutsActive({'payoutStatus': 'activated'}), isTrue);
      expect(PaymentService.payoutsActive({'payoutStatus': 'under_review'}),
          isFalse);
      expect(PaymentService.payoutStatusLabel({}), 'Payouts not set up');
      expect(
          PaymentService.payoutStatusLabel(
              {'payoutStatus': 'needs_clarification'}),
          'Bank details need correction');
    });

    test('provider earnings count their 90% share of online payments', () {
      final now = IstClock.now().toIso8601String();
      final bookings = [
        // paid online: ₹1000, provider gets ₹900
        {
          'doctorUid': 'p1',
          'status': 'Completed',
          'completedAt': now,
          'price': 1000,
          'providerShare': 900,
        },
        // older booking without online payment: full price
        {'doctorUid': 'p1', 'status': 'Completed', 'completedAt': now, 'price': 500},
        // not completed / someone else's
        {'doctorUid': 'p1', 'status': 'Confirmed', 'price': 700},
        {'doctorUid': 'p2', 'status': 'Completed', 'completedAt': now, 'price': 300},
      ];
      expect(FirestoreService.earningsLast30Days(bookings, 'p1'), 1400);
    });
  });
}
