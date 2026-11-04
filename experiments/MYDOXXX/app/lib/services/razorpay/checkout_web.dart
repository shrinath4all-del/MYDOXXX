import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'checkout_result.dart';

/// Razorpay Standard Checkout (checkout.js, loaded in web/index.html).
@JS('Razorpay')
extension type _Razorpay._(JSObject _) implements JSObject {
  external factory _Razorpay(JSObject options);
  external void open();
  external void on(String event, JSFunction handler);
}

String _str(JSObject? o, String key) {
  final v = o?.getProperty<JSAny?>(key.toJS);
  return v.isA<JSString>() ? (v as JSString).toDart : '';
}

/// Web: Razorpay's checkout popup.
Future<CheckoutResult> openRazorpayCheckout(Map<String, dynamic> options) {
  final completer = Completer<CheckoutResult>();
  void finish(CheckoutResult r) {
    if (!completer.isCompleted) completer.complete(r);
  }

  if (!globalContext.has('Razorpay')) {
    finish(const CheckoutResult.failed(
        'Payment screen could not load. Check your internet and try again.'));
    return completer.future;
  }

  final jsOptions = options.jsify() as JSObject;
  jsOptions.setProperty(
      'handler'.toJS,
      ((JSObject r) {
        finish(CheckoutResult.success(
          paymentId: _str(r, 'razorpay_payment_id'),
          orderId: _str(r, 'razorpay_order_id'),
          signature: _str(r, 'razorpay_signature'),
        ));
      }).toJS);
  final modal = JSObject();
  modal.setProperty('ondismiss'.toJS,
      (() => finish(const CheckoutResult.cancelled())).toJS);
  jsOptions.setProperty('modal'.toJS, modal);

  try {
    final checkout = _Razorpay(jsOptions);
    checkout.on(
        'payment.failed',
        ((JSObject r) {
          final error = r.getProperty<JSObject?>('error'.toJS);
          final text = _str(error, 'description');
          finish(CheckoutResult.failed(text.isNotEmpty ? text : 'Payment failed.'));
        }).toJS);
    checkout.open();
  } catch (_) {
    finish(const CheckoutResult.failed('Payment screen could not open.'));
  }
  return completer.future;
}
