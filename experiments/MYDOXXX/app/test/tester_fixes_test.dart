import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/models/user_model.dart';
import 'package:mydox/services/care_physician_service.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/utils/validators.dart';
import 'package:mydox/widgets/booked_care_physicians_card.dart';

void main() {
  final now = DateTime(2026, 10, 19, 10);
  final today = CarePhysicianService.dateKey(now);
  final tomorrow = CarePhysicianService.dateKey(now.add(const Duration(days: 1)));
  final yesterday =
      CarePhysicianService.dateKey(now.subtract(const Duration(days: 1)));

  Map<String, dynamic> shift(String status, String date,
          {String doctor = 'Dr. Asha'}) =>
      {
        'status': status,
        'date': date,
        'start': '20:00',
        'end': '08:00',
        'dutyType': 'icu',
        'claimedByName': doctor,
        'claimedByPhone': '9876543210',
        'claimedAgencyName': 'Pune Care Partners',
      };

  test('booked care physicians: claimed / on duty, today and later', () {
    final list = BookedCarePhysiciansCard.booked([
      shift('claimed', tomorrow, doctor: 'B'),
      shift('on_duty', today, doctor: 'A'),
      shift('open', tomorrow, doctor: 'not booked'),
      shift('completed', today, doctor: 'done'),
      shift('claimed', CarePhysicianService.dateKey(
          now.subtract(const Duration(days: 3))), doctor: 'past'),
      shift('claimed', yesterday, doctor: 'night shift still running'),
    ], now);
    expect(list.map((s) => s['claimedByName']),
        ['night shift still running', 'A', 'B']);
  });

  for (final width in [320.0, 412.0]) {
    testWidgets('booked care physicians card fits at ${width.toInt()}',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: BookedCarePhysiciansCard(
              now: now,
              onOpenAll: () {},
              shifts: [
                shift('claimed', tomorrow,
                    doctor: 'Dr. Venkatanarasimharajuvaripeta Subramanian'),
                shift('on_duty', today),
              ],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Booked Care Physicians (2)'), findsOneWidget);
      expect(find.text('On duty'), findsOneWidget);
      expect(find.byIcon(Icons.call_rounded), findsNWidgets(2));
    });
  }

  test('saving a profile keeps a verified provider verified', () {
    final before = UserModel.fromMap({
      'role': 'technician',
      'name': 'Rahul Test',
      'isVerified': true,
      'rating': 4.5,
    }, 'tech1');
    // what the edit screen saves, merged as the screens now hand it back
    final saved = {
      'name': 'Rahul T',
      'experience': '12',
      'offeredTests': ['ECG Technician'],
    };
    final after = UserModel.fromMap({...before.toMap(), ...saved}, 'tech1');
    expect(after.isVerified, isTrue);
    expect(after.rating, 4.5);
    expect(after.name, 'Rahul T');
    expect(after.experience, '12');
  });

  test('mobile numbers stop at 10 digits (12 with 91); 10 or 91 + 10 are valid', () {
    TextEditingValue type(String text) {
      var value = TextEditingValue.empty;
      for (final ch in text.split('')) {
        var next = TextEditingValue(text: value.text + ch);
        for (final f in Validators.phoneInput) {
          next = f.formatEditUpdate(value, next);
        }
        value = next;
      }
      return value;
    }

    expect(type('9011361799777777').text, '9011361799',
        reason: 'no 11th digit on a plain mobile number');
    expect(type('91901136179977').text, '919011361799',
        reason: 'up to 12 digits with the 91 country code');
    expect(type('+91 90113 61799 7').text, '+91 90113 61799 ');
    expect(type('090113617999').text, '09011361799');
    expect(Validators.mobile('9011361799'), isNull);
    expect(Validators.mobile('919011361799'), isNull);
    expect(Validators.mobile('901136179977'),
        'Enter a valid mobile number: 10 digits, or 12 starting with 91');
  });
}
