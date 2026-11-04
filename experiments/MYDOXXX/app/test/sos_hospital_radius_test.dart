import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/sos_service.dart';

Map<String, dynamic> requestAgo(int seconds) => {
      'createdAt':
          DateTime.now().subtract(Duration(seconds: seconds)).toIso8601String(),
    };

void main() {
  test('SOS hospitals: 4 km first, 6 km after a minute, 8 km after two', () {
    expect(SosService.hospitalRadius(requestAgo(5)), 4);
    expect(SosService.hospitalRadius(requestAgo(59)), 4);
    expect(SosService.hospitalRadius(requestAgo(65)), 6);
    expect(SosService.hospitalRadius(requestAgo(125)), 8);
    expect(SosService.hospitalRadius(requestAgo(290)), 8); // never beyond 8 km
  });
}
