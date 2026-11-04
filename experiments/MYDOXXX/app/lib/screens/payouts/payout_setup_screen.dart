import 'package:flutter/material.dart';
import '../../utils/form_utils.dart';
import 'package:flutter/services.dart';

import '../../services/payment_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/validators.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

/// Provider's bank details for online payments. Each booking payment is
/// split: 10% to the app, 90% to this bank account (through Razorpay),
/// paid out after the visit is completed.
class PayoutSetupScreen extends StatefulWidget {
  /// Provider profile document (doctors / nurses / technicians / therapists)
  final Map<String, dynamic> provider;
  final String defaultEmail;
  final String defaultPhone;
  final String defaultName;

  const PayoutSetupScreen({
    super.key,
    required this.provider,
    this.defaultEmail = '',
    this.defaultPhone = '',
    this.defaultName = '',
  });

  @override
  State<PayoutSetupScreen> createState() => _PayoutSetupScreenState();
}

class _PayoutSetupScreenState extends State<PayoutSetupScreen> {

  // Razorpay needs the 2-letter state code
  static const Map<String, String> _states = {
    'AN': 'Andaman and Nicobar', 'AP': 'Andhra Pradesh', 'AR': 'Arunachal Pradesh',
    'AS': 'Assam', 'BR': 'Bihar', 'CH': 'Chandigarh', 'CG': 'Chhattisgarh',
    'DN': 'Dadra, Nagar Haveli, Daman and Diu', 'DL': 'Delhi', 'GA': 'Goa',
    'GJ': 'Gujarat', 'HR': 'Haryana', 'HP': 'Himachal Pradesh',
    'JK': 'Jammu and Kashmir', 'JH': 'Jharkhand', 'KA': 'Karnataka',
    'KL': 'Kerala', 'LA': 'Ladakh', 'LD': 'Lakshadweep', 'MP': 'Madhya Pradesh',
    'MH': 'Maharashtra', 'MN': 'Manipur', 'ML': 'Meghalaya', 'MZ': 'Mizoram',
    'NL': 'Nagaland', 'OR': 'Odisha', 'PY': 'Puducherry', 'PB': 'Punjab',
    'RJ': 'Rajasthan', 'SK': 'Sikkim', 'TN': 'Tamil Nadu', 'TS': 'Telangana',
    'TR': 'Tripura', 'UP': 'Uttar Pradesh', 'UK': 'Uttarakhand',
    'WB': 'West Bengal',
  };

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
      text: (widget.provider['payoutName'] ?? widget.defaultName).toString());
  late final _email = TextEditingController(text: widget.defaultEmail);
  late final _phone = TextEditingController(text: widget.defaultPhone);
  final _pan = TextEditingController();
  final _account = TextEditingController();
  final _accountAgain = TextEditingController();
  late final _ifsc = TextEditingController(
      text: (widget.provider['payoutIfsc'] ?? '').toString());
  final _street = TextEditingController();
  late final _city = TextEditingController(
      text: (widget.provider['city'] ?? '').toString());
  final _pin = TextEditingController();
  String? _state = 'MH';
  bool _saving = false;
  bool _checking = false;
  late Map<String, dynamic> _provider = widget.provider;

  @override
  void dispose() {
    for (final c in [
      _name, _email, _phone, _pan, _account, _accountAgain, _ifsc, _street,
      _city, _pin,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.successDark,
    ));
  }

  Future<void> _save() async {
    if (!FormUtils.validate(_formKey)) return;
    setState(() => _saving = true);
    try {
      final status = await PaymentService.setupPayouts({
        'legalName': _name.text.trim(),
        'beneficiaryName': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'pan': _pan.text.trim().toUpperCase(),
        'accountNumber': _account.text.replaceAll(' ', ''),
        'ifsc': _ifsc.text.trim().toUpperCase(),
        'street': _street.text.trim(),
        'city': _city.text.trim(),
        'state': _state ?? '',
        'postalCode': _pin.text.trim(),
      });
      setState(() => _provider = {
            ..._provider,
            'payoutStatus': status,
            'payoutBankLast4': _account.text.replaceAll(' ', '').length >= 4
                ? _account.text.replaceAll(' ', '').substring(
                    _account.text.replaceAll(' ', '').length - 4)
                : '',
          });
      _snack(status == 'activated'
          ? 'Payouts are active. You can now receive online payments.'
          : 'Bank details sent. Razorpay is verifying them; this usually takes 1–2 working days.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'save your bank details'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final status = await PaymentService.refreshPayoutStatus();
      setState(() => _provider = {..._provider, 'payoutStatus': status});
      _snack(PaymentService.payoutStatusLabel(_provider));
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'check the status'), error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    final status = (_provider['payoutStatus'] ?? '').toString();
    final active = PaymentService.payoutsActive(_provider);
    final started = status.isNotEmpty;
    final last4 = (_provider['payoutBankLast4'] ?? '').toString();
    final fix = status == 'needs_clarification';

    return ResponsiveCenter(child: Scaffold(
      appBar: AppBar(title: const Text('Payout bank account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Patients pay online through Razorpay. For every booking you '
                  'receive 90% of the fee in this bank account; the app keeps '
                  '${PaymentService.platformCommissionPct}%. Your share is paid '
                  'out after the visit is completed.',
                  style: TextStyle(fontSize: 13, color: AppColors.primaryDark),
                ),
              ),
              const SizedBox(height: 14),
              if (started)
                Card(
                  child: ListTile(
                    leading: Icon(
                      active
                          ? Icons.verified_rounded
                          : (fix ? Icons.error_outline : Icons.hourglass_top_rounded),
                      color: active
                          ? AppColors.successDark
                          : (fix ? AppColors.danger : AppColors.orange),
                    ),
                    title: Text(PaymentService.payoutStatusLabel(_provider),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text([
                      if (last4.isNotEmpty) 'Account ending $last4',
                      if ((_provider['payoutIfsc'] ?? '').toString().isNotEmpty)
                        'IFSC ${_provider['payoutIfsc']}',
                      if (fix)
                        'Razorpay could not verify some details. Check and submit again.',
                    ].join(' · ')),
                    trailing: active
                        ? null
                        : TextButton(
                            onPressed: _checking ? null : _check,
                            child: Text(_checking ? 'Checking…' : 'Check status'),
                          ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(started ? 'Update bank details' : 'Add bank details',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                validator: (v) => Validators.personName(v, label: 'name as on PAN'),
                decoration: _dec('Full name (as on PAN and bank account)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pan,
                validator: Validators.pan,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: _dec('PAN', hint: 'ABCPA1234Z'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _account,
                validator: Validators.bankAccount,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: Validators.digitsInput(18),
                decoration: _dec('Bank account number'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountAgain,
                validator: (v) => v?.trim() != _account.text.trim()
                    ? 'Account numbers do not match'
                    : null,
                keyboardType: TextInputType.number,
                inputFormatters: Validators.digitsInput(18),
                decoration: _dec('Re-enter account number'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ifsc,
                validator: Validators.ifsc,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: _dec('IFSC code', hint: 'HDFC0001234'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                validator: Validators.email,
                keyboardType: TextInputType.emailAddress,
                decoration: _dec('Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                validator: Validators.mobile,
                keyboardType: TextInputType.phone,
                inputFormatters: Validators.phoneInput,
                decoration: _dec('Mobile number'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _street,
                validator: (v) => (v ?? '').trim().length < 10
                    ? 'Enter your full address (at least 10 characters)'
                    : null,
                decoration: _dec('Address (house, street, area)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _city,
                      validator: Validators.city,
                      decoration: _dec('City'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _pin,
                      validator: Validators.pincode,
                      keyboardType: TextInputType.number,
                      inputFormatters: Validators.digitsInput(6),
                      decoration: _dec('PIN code'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                menuMaxHeight: 320,
                value: _state,
                isExpanded: true,
                decoration: _dec('State'),
                items: [
                  for (final e in _states.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _state = v),
                validator: (v) => v == null ? 'Select your state' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(_saving ? 'Sending to Razorpay…' : 'Save bank details'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your full account number is sent securely to Razorpay and is '
                'not stored in the app. Only the last 4 digits are shown here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
