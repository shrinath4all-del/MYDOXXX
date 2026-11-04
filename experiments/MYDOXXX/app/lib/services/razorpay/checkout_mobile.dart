import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'checkout_result.dart';

/// Android / iOS: Razorpay's native checkout.
Future<CheckoutResult> openRazorpayCheckout(Map<String, dynamic> options) {
  // Razorpay's native checkout exists only on Android and iOS
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return Future.value(const CheckoutResult.failed(
        'Online payment is not available in this app. Please pay from the MyDox website or the mobile app.'));
  }
  final completer = Completer<CheckoutResult>();
  final razorpay = Razorpay();

  void finish(CheckoutResult result) {
    if (completer.isCompleted) return;
    completer.complete(result);
    razorpay.clear();
  }

  razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
    finish(CheckoutResult.success(
      paymentId: r.paymentId ?? '',
      orderId: r.orderId ?? '',
      signature: r.signature ?? '',
    ));
  });
  razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
    finish(r.code == Razorpay.PAYMENT_CANCELLED
        ? const CheckoutResult.cancelled()
        : CheckoutResult.failed(
            (r.message ?? '').isNotEmpty ? r.message! : 'Payment failed.'));
  });
  razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
    finish(CheckoutResult.failed(
        'Please complete the payment in ${r.walletName ?? 'your wallet'}. '
        'Your booking updates once Razorpay confirms it.'));
  });

  try {
    razorpay.open(options);
  } catch (e) {
    finish(const CheckoutResult.failed('Payment screen could not open.'));
  }
  return completer.future;
}
