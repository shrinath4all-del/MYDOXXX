import '../config/test_lab_config.dart';
import 'test_lab_payment.dart';
import '../config/experiment_environment.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'razorpay/checkout_result.dart';
import 'razorpay/checkout_mobile.dart'
    if (dart.library.js_interop) 'razorpay/checkout_web.dart';

export 'razorpay/checkout_result.dart';

/// Razorpay payments for bookings. The patient pays after a provider
/// accepts; the provider can start the visit (OTP) only once it is paid.
/// Orders and verification run in Cloud Functions (functions/razorpay.js),
/// so the price comes from the booking and the key secret never reaches
/// the app.
class PaymentService {
  static const String pending = 'pending';
  static const String paid = 'paid';
  static const String cash = 'cash'; // pay the doctor in cash at the visit
  static const String cashCollected = 'cash_collected';

  static bool isCashDue(Map<String, dynamic> booking) =>
      booking['paymentStatus'] == cash;
  static bool isCashCollected(Map<String, dynamic> booking) =>
      booking['cashCollected'] == true ||
      booking['paymentStatus'] == cashCollected;

  /// Needs online payment and is not paid yet. Bookings made before online
  /// payment (no paymentStatus) and SOS emergencies are not affected.
  static bool isAwaitingPayment(Map<String, dynamic> booking) =>
      booking['paymentStatus'] == pending;

  static bool isPaid(Map<String, dynamic> booking) =>
      booking['paymentStatus'] == paid;

  /// Patient can pay now: accepted by a provider and not paid yet.
  static bool canPayNow(Map<String, dynamic> booking) =>
      isAwaitingPayment(booking) && booking['status'] == 'Confirmed';

  // ---------------------------------------------------------- payouts
  // Each payment is split: 10% to the app, 90% to the provider's own
  // Razorpay linked account (held until the visit is completed).

  static const int platformCommissionPct = 10;

  /// Provider can receive online payments (Razorpay activated the account).
  static bool payoutsActive(Map<String, dynamic> provider) =>
      provider['payoutStatus'] == 'activated';

  /// Short text for a provider's payout status.
  static String payoutStatusLabel(Map<String, dynamic> provider) {
    switch ((provider['payoutStatus'] ?? '').toString()) {
      case 'activated':
        return 'Payouts active';
      case 'under_review':
      case 'requested':
        return 'Bank details under review';
      case 'needs_clarification':
        return 'Bank details need correction';
      case 'suspended':
        return 'Payouts suspended';
      default:
        return 'Payouts not set up';
    }
  }

  /// Sends the provider's bank details; Razorpay creates their linked
  /// account. Returns the activation status.
  static Future<String> setupPayouts(Map<String, String> details) async {
    try {
      final res =
          await _fn('setupProviderPayouts').call<Map<String, dynamic>>(details);
      return (res.data['status'] ?? '').toString();
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Payout setup failed. Please try again.');
    }
  }

  static Future<String> refreshPayoutStatus() async {
    try {
      final res = await _fn('refreshProviderPayoutStatus')
          .call<Map<String, dynamic>>();
      return (res.data['status'] ?? '').toString();
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Could not check the status.');
    }
  }

  /// The result of a payment made entirely with MedCoins.
  static const CheckoutResult _paidWithCoins = CheckoutResult.success(
      paymentId: 'medcoins', orderId: '', signature: '');

  static HttpsCallable _fn(String name) {
    ExperimentEnvironment.requireExternalActions();
    return FirebaseFunctions.instance.httpsCallable(name);
  }

  /// Buys a chat recharge plan for [chatId]: opens Razorpay, then confirms
  /// the payment on the server, which adds the days and messages to the chat.
  /// The price comes from the plan in Firestore, never from the phone.
  static Future<CheckoutResult> payForChatRecharge(
      {required String chatId,
      required String planId,
      bool useCoins = false}) async {
    final Map<String, dynamic> order;
    try {
      final res = await _fn('createChatRechargeOrder').call<Map<String, dynamic>>(
          {'chatId': chatId, 'planId': planId, 'useCoins': useCoins});
      order = Map<String, dynamic>.from(res.data);
      // paid fully with MedCoins: there is no checkout
      if (order['paidWithCoins'] == true) return _paidWithCoins;
    } on FirebaseFunctionsException catch (e) {
      return CheckoutResult.failed(
          e.message ?? 'Payment could not be started. Please try again.');
    } catch (_) {
      return const CheckoutResult.failed(
          'Payment could not be started. Check your internet and try again.');
    }

    final result = await openRazorpayCheckout({
      'key': order['keyId'],
      'order_id': order['orderId'],
      'amount': order['amount'],
      'currency': order['currency'] ?? 'INR',
      'name': 'MyDox',
      'description': order['description'] ?? 'Chat recharge',
      'prefill': {
        if ((order['patientName'] ?? '').toString().isNotEmpty)
          'name': order['patientName'],
        if ((order['patientPhone'] ?? '').toString().isNotEmpty)
          'contact': order['patientPhone'],
      },
      'notes': {'type': 'chat_recharge', 'rechargeId': order['rechargeId']},
      'theme': {'color': '#0284C7'},
    });
    if (!result.success) return result;

    try {
      await _fn('verifyChatRechargePayment').call({
        'rechargeId': order['rechargeId'],
        'orderId': result.orderId,
        'paymentId': result.paymentId,
        'signature': result.signature,
      });
      return result;
    } on FirebaseFunctionsException catch (e) {
      return CheckoutResult.failed(
          '${e.message ?? 'Payment could not be verified.'} '
          'If money was deducted, the chat updates shortly or Razorpay refunds it.');
    } catch (_) {
      return const CheckoutResult.failed(
          'Payment received but not confirmed yet. The chat will update shortly.');
    }
  }

  /// Opens Razorpay for [appointmentId] and verifies the payment.
  /// Returns the checkout result; on success the booking is marked paid.
  static Future<CheckoutResult> payForBooking(String appointmentId,
      {bool useCoins = false}) async {
    if (TestLabConfig.enabled) return TestLabPayment.payBooking(appointmentId);
    final Map<String, dynamic> order;
    try {
      final res = await _fn('createRazorpayOrder').call<Map<String, dynamic>>(
          {'appointmentId': appointmentId, 'useCoins': useCoins});
      order = Map<String, dynamic>.from(res.data);
      // paid fully with MedCoins: there is no checkout
      if (order['paidWithCoins'] == true) return _paidWithCoins;
    } on FirebaseFunctionsException catch (e) {
      return CheckoutResult.failed(
          e.message ?? 'Payment could not be started. Please try again.');
    } catch (_) {
      return const CheckoutResult.failed(
          'Payment could not be started. Check your internet and try again.');
    }

    final result = await openRazorpayCheckout({
      'key': order['keyId'],
      'order_id': order['orderId'],
      'amount': order['amount'],
      'currency': order['currency'] ?? 'INR',
      'name': 'MyDox',
      'description': order['description'] ?? 'Booking payment',
      'prefill': {
        if ((order['patientName'] ?? '').toString().isNotEmpty)
          'name': order['patientName'],
        if ((order['patientPhone'] ?? '').toString().isNotEmpty)
          'contact': order['patientPhone'],
      },
      'notes': {'appointmentId': appointmentId},
      'theme': {'color': '#0284C7'},
    });
    if (!result.success) return result;

    try {
      await _fn('verifyRazorpayPayment').call({
        'appointmentId': appointmentId,
        'orderId': result.orderId,
        'paymentId': result.paymentId,
        'signature': result.signature,
      });
      return result;
    } on FirebaseFunctionsException catch (e) {
      return CheckoutResult.failed(
          '${e.message ?? 'Payment could not be verified.'} '
          'If money was deducted, it will update shortly or be refunded by Razorpay.');
    } catch (_) {
      return const CheckoutResult.failed(
          'Payment received but not confirmed yet. It will update shortly.');
    }
  }
}
