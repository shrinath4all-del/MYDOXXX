/// Outcome of the Razorpay checkout screen.
class CheckoutResult {
  final bool success;
  final bool cancelled;
  final String paymentId;
  final String orderId;
  final String signature;
  final String message;

  const CheckoutResult._({
    this.success = false,
    this.cancelled = false,
    this.paymentId = '',
    this.orderId = '',
    this.signature = '',
    this.message = '',
  });

  const CheckoutResult.success({
    required String paymentId,
    required String orderId,
    required String signature,
  }) : this._(
          success: true,
          paymentId: paymentId,
          orderId: orderId,
          signature: signature,
        );

  const CheckoutResult.cancelled() : this._(cancelled: true);

  const CheckoutResult.failed(String message) : this._(message: message);
}
