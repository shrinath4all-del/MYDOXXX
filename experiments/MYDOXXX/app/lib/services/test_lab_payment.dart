import 'package:firebase_auth/firebase_auth.dart';
import '../config/test_lab_config.dart';
import 'app_database.dart';
import 'razorpay/checkout_result.dart';

/// Advances synthetic booking tests only. No payment gateway, wallet, cash,
/// commission, provider payout or live Cloud Function is contacted.
class TestLabPayment {
  static bool canSimulate(Map<String, dynamic> b, String uid) =>
      uid.startsWith('mdxtest') &&
      b['patientUid'] == uid &&
      b['status'] == 'Confirmed' &&
      b['paymentStatus'] == 'pending';

  static Future<CheckoutResult> payBooking(String id) async {
    if (!TestLabConfig.enabled) throw StateError('Test payments are disabled.');
    TestLabConfig.requireLocal(Uri.base);
    final user = FirebaseAuth.instance.currentUser;
    final claims = (await user?.getIdTokenResult())?.claims ?? {};
    if (user == null ||
        claims['mydoxTest'] != true ||
        claims['testDatabase'] != TestLabConfig.databaseId) {
      return const CheckoutResult.failed(
          'Only a signed-in synthetic test patient can simulate payment.');
    }
    final ref = AppDatabase.instance.collection('appointments').doc(id);
    try {
      await AppDatabase.instance.runTransaction((tx) async {
        final data = (await tx.get(ref)).data();
        if (data == null || !canSimulate(data, user.uid)) {
          throw StateError(
              'The accepted test booking is not awaiting your payment.');
        }
        tx.update(ref, {
          'paymentStatus': 'paid',
          'paymentMode': 'test_simulation',
          'testPayment': true,
          'testPaymentId': 'lab_$id',
          'paidAt': DateTime.now().toIso8601String(),
        });
      });
      return CheckoutResult.success(
          paymentId: 'lab_$id', orderId: '', signature: '');
    } catch (_) {
      return const CheckoutResult.failed(
          'Test payment could not be recorded. Refresh the booking and retry.');
    }
  }
}
