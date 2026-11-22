import 'package:flutter/services.dart';

/// Form field validators shared by the login, registration and profile
/// screens. Each returns an error message, or null when the value is valid.
class Validators {
  Validators._();

  static String _clean(String? v) => (v ?? '').trim();

  static final RegExp _emailRe = RegExp(
      r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$');
  static final RegExp _personNameRe = RegExp(r"^[A-Za-z][A-Za-z .'\-]*$");
  static final RegExp _orgNameRe = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 .,&'()/\-]*$");
  static final RegExp _cityRe = RegExp(r"^[A-Za-z][A-Za-z .'\-]*$");

  /// Allowed while typing a phone number: digits, +, spaces, hyphens, and
  /// no digit past the 10th (12th with the 91 country code, 11th after 0).
  static final List<TextInputFormatter> phoneInput = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
    LengthLimitingTextInputFormatter(16),
    const _PhoneDigitsFormatter(),
  ];

  /// Whole numbers only (age, years of experience).
  static List<TextInputFormatter> digitsInput(int maxLength) => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength),
      ];

  /// Personal PAN: 5 letters, 4 digits, 1 letter; 4th letter P (individual).
  static String? pan(String? v) {
    final p = _clean(v).toUpperCase();
    if (p.isEmpty) return 'Please enter your PAN';
    if (!RegExp(r'^[A-Z]{5}\d{4}[A-Z]$').hasMatch(p)) {
      return 'Enter a valid PAN (e.g. ABCPA1234Z)';
    }
    if (p[3] != 'P') return 'Enter your personal PAN (4th letter is P)';
    return null;
  }

  static String? ifsc(String? v) {
    final s = _clean(v).toUpperCase();
    if (s.isEmpty) return 'Please enter the IFSC code';
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(s)) {
      return 'Enter a valid IFSC code (e.g. HDFC0001234)';
    }
    return null;
  }

  static String? bankAccount(String? v) {
    final s = _clean(v).replaceAll(' ', '');
    if (s.isEmpty) return 'Please enter the bank account number';
    if (!RegExp(r'^\d{9,18}$').hasMatch(s)) {
      return 'Account number must be 9 to 18 digits';
    }
    return null;
  }

  static String? pincode(String? v) {
    final s = _clean(v);
    if (s.isEmpty) return 'Please enter the PIN code';
    if (!RegExp(r'^[1-9]\d{5}$').hasMatch(s)) return 'Enter a valid 6-digit PIN code';
    return null;
  }

  static String? required(String? v, String label) =>
      _clean(v).isEmpty ? 'Please enter $label' : null;

  static String? email(String? v) {
    final s = _clean(v);
    if (s.isEmpty) return 'Please enter email';
    if (s.contains(' ')) return 'Email cannot contain spaces';
    if (s.contains('..') || !_emailRe.hasMatch(s)) {
      return 'Enter a valid email (e.g. name@example.com)';
    }
    return null;
  }

  /// Login: only checks something was typed, so older accounts with
  /// shorter passwords can still sign in.
  static String? loginPassword(String? v) =>
      (v ?? '').isEmpty ? 'Please enter password' : null;

  /// New accounts: 8+ characters with at least one letter and one number.
  static String? newPassword(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Please enter password';
    if (s.contains(' ')) return 'Password cannot contain spaces';
    if (s.length < 8 ||
        !RegExp(r'[A-Za-z]').hasMatch(s) ||
        !RegExp(r'\d').hasMatch(s)) {
      return 'Password must be at least 8 characters with at least one letter '
          'and one number';
    }
    return null;
  }

  /// Person name: letters, spaces, dots, apostrophes, hyphens (2-60 chars).
  static String? personName(String? v, {String label = 'full name'}) {
    final s = _clean(v);
    if (s.isEmpty) return 'Please enter $label';
    if (s.length < 2) return 'Name is too short';
    if (s.length > 60) return 'Name is too long (max 60 characters)';
    if (!_personNameRe.hasMatch(s)) {
      return 'Use letters only (no numbers or symbols)';
    }
    return null;
  }

  /// Hospital / agency / organisation name (3-100 chars).
  static String? orgName(String? v,
      {String label = 'name', bool optional = false}) {
    final s = _clean(v);
    if (s.isEmpty) return optional ? null : 'Please enter $label';
    if (s.length < 3) return 'Name is too short';
    if (s.length > 100) return 'Name is too long (max 100 characters)';
    if (!_orgNameRe.hasMatch(s)) return 'Name contains invalid characters';
    return null;
  }

  static String _digitsOf(String s) => s.replaceAll(RegExp(r'[\s\-()]'), '');

  /// Indian mobile number: 10 digits starting 6-9, with optional +91 / 0.
  static String? mobile(String? v,
      {String label = 'mobile number', bool optional = false}) {
    final raw = _clean(v);
    if (raw.isEmpty) return optional ? null : 'Please enter $label';
    var d = _digitsOf(raw);
    if (d.startsWith('+91')) {
      d = d.substring(3);
    } else if (d.startsWith('91') && d.length == 12) {
      d = d.substring(2);
    } else if (d.startsWith('0') && d.length == 11) {
      d = d.substring(1);
    }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(d)) {
      return 'Enter a valid mobile number: 10 digits, or 12 starting with 91';
    }
    return null;
  }

  /// Mobile or landline with STD code (e.g. +91 20 2616 3391).
  static String? contactNumber(String? v, {String label = 'phone number'}) {
    final raw = _clean(v);
    if (raw.isEmpty) return 'Please enter $label';
    var d = _digitsOf(raw);
    if (d.startsWith('+91')) {
      d = d.substring(3);
    } else if (d.startsWith('91') && d.length == 12) {
      d = d.substring(2);
    }
    if (d.startsWith('0')) d = d.substring(1);
    if (!RegExp(r'^[1-9]\d{9}$').hasMatch(d)) {
      return 'Enter a valid 10-digit phone number with area code';
    }
    return null;
  }

  static String? city(String? v) {
    final s = _clean(v);
    if (s.isEmpty) return 'Please enter city';
    if (s.length < 2 || s.length > 50 || !_cityRe.hasMatch(s)) {
      return 'Enter a valid city name';
    }
    return null;
  }

  static String? address(String? v,
      {String label = 'address', bool optional = false}) {
    final s = _clean(v);
    if (s.isEmpty) return optional ? null : 'Please enter $label';
    if (s.length < 10) return 'Please enter the full $label';
    if (s.length > 250) return 'Address is too long (max 250 characters)';
    return null;
  }

  /// Years of experience 0-60. Accepts "8" or older values like "8 years".
  static String? experience(String? v) {
    final s = _clean(v);
    if (s.isEmpty) return 'Please enter experience';
    final m = RegExp(r'^(\d{1,2})(\s*(years?|yrs?)\.?)?$', caseSensitive: false)
        .firstMatch(s);
    if (m == null) return 'Enter years as a number (e.g. 5)';
    if (int.parse(m.group(1)!) > 60) return 'Enter a realistic experience (0-60)';
    return null;
  }

  static String? age(String? v) {
    final s = _clean(v);
    if (s.isEmpty) return 'Please enter age';
    final n = int.tryParse(s);
    if (n == null) return 'Enter age as a number';
    if (n < 0 || n > 120) return 'Enter a valid age';
    return null;
  }

  /// Optional body weight in kg ("68" or "68 kg").
  static String? weight(String? v) {
    final s = _clean(v);
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{1,3}(\.\d)?)\s*(kg|kgs)?$', caseSensitive: false)
        .firstMatch(s);
    if (m == null) return 'Enter weight in kg (e.g. 68)';
    final n = double.parse(m.group(1)!);
    if (n < 1 || n > 350) return 'Enter a valid weight (1-350 kg)';
    return null;
  }

  /// Vehicle registration, e.g. MH12AB1234 / MH-12-AMB-108.
  static String? vehicleNumber(String? v) {
    final s = _clean(v);
    if (s.isEmpty) return 'Please enter vehicle number';
    final compact = s.replaceAll(RegExp(r'[\s\-]'), '');
    if (!RegExp(r'^[A-Za-z0-9]{6,12}$').hasMatch(compact) ||
        !RegExp(r'[A-Za-z]').hasMatch(compact) ||
        !RegExp(r'\d').hasMatch(compact)) {
      return 'Enter a valid vehicle number (e.g. MH12AB1234)';
    }
    return null;
  }

  /// Optional professional registration number (letters, digits, / and -).
  static String? registrationNumber(String? v) {
    final s = _clean(v);
    if (s.isEmpty) return null;
    if (s.length < 3 || s.length > 30 ||
        !RegExp(r'^[A-Za-z0-9/\- ]+$').hasMatch(s)) {
      return 'Enter a valid registration number';
    }
    return null;
  }

  /// Qualification text such as "MBBS, MD" or "B.Sc Nursing".
  static String? qualification(String? v, {bool optional = false}) {
    final s = _clean(v);
    if (s.isEmpty) return optional ? null : 'Please enter qualification';
    if (s.length < 2 || s.length > 100) return 'Enter a valid qualification';
    return null;
  }

  /// Optional free text with a length limit (summary, courses, allergies).
  static String? maxLength(String? v, int max) =>
      _clean(v).length > max ? 'Keep this under $max characters' : null;
}

/// Refuses an edit that would make a phone number longer than it can be:
/// 10 digits, 12 when it starts with the 91 country code, 11 after a 0.
class _PhoneDigitsFormatter extends TextInputFormatter {
  const _PhoneDigitsFormatter();

  static int _maxDigits(String digits) => digits.startsWith('91')
      ? 12
      : digits.startsWith('0')
          ? 11
          : 10;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    return digits.length > _maxDigits(digits) ? oldValue : newValue;
  }
}
