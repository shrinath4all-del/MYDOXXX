import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/screens/shifts/shift_board_screen.dart';

void main() {
  final now = DateTime(2026, 11, 23, 18);
  Map<String, dynamic> team(String status, {List<String> applied = const [], String date = '2026-11-30'}) => {
        'isTeam': true,
        'rotation': true,
        'status': status,
        'date': date,
        'start': '08:00',
        'end': '15:00',
        'applicantUids': applied,
      };

  test('hospital full-time teams: open, applied, closed', () {
    expect(teamFilterOf(team('open'), now), 'open');
    expect(teamFilterOf(team('open', applied: ['cp1']), now), 'applied');
    expect(teamFilterOf(team('filled', applied: ['cp1']), now), 'closed');
    expect(teamFilterOf(team('cancelled'), now), 'closed');
    expect(teamFilterOf(team('unfilled'), now), 'closed');
    // its start day is over without a team
    expect(teamFilterOf(team('open', date: '2026-11-20'), now), 'closed');
    // posted for today: still open today
    expect(teamFilterOf(team('open', date: '2026-11-23'), now), 'open');
  });
}
