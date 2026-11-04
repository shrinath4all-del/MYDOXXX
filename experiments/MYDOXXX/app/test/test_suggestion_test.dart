import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/test_suggestion_service.dart';

void main() {
  final now = DateTime(2026, 10, 26, 10);

  group('Book later schedule', () {
    test('1st later: next day', () {
      final r = TestSuggestionService.onBookLater(0, now: now);
      expect(r.result, LaterResult.scheduled);
      expect(r.remindAt, now.add(const Duration(days: 1)));
    });

    test('2nd and 3rd later: every 2 days', () {
      expect(TestSuggestionService.onBookLater(1, now: now).remindAt,
          now.add(const Duration(days: 2)));
      expect(TestSuggestionService.onBookLater(2, now: now).remindAt,
          now.add(const Duration(days: 2)));
    });

    test('after the 3rd reminder the other options are shown, then it stops',
        () {
      final r = TestSuggestionService.onBookLater(3, now: now);
      expect(r.result, LaterResult.showOtherOptions);
      expect(r.remindAt, isNull);
    });
  });

  group('When a reminder is due', () {
    test('postponed: only once its time has come', () {
      final s = {
        'status': 'later',
        'remindAt': now.add(const Duration(hours: 2)).toIso8601String(),
      };
      expect(TestSuggestionService.isDue(s, now: now), isFalse);
      expect(
          TestSuggestionService.isDue(s,
              now: now.add(const Duration(hours: 3))),
          isTrue);
    });

    test('never answered: reminded after a day', () {
      final s = {'status': 'suggested', 'createdAt': now.toIso8601String()};
      expect(TestSuggestionService.isDue(s, now: now), isFalse);
      expect(
          TestSuggestionService.isDue(s, now: now.add(const Duration(days: 1))),
          isTrue);
    });

    test('booked or closed: never', () {
      for (final status in ['booked', 'closed']) {
        final s = {
          'status': status,
          'createdAt': '2020-01-01T00:00:00',
          'remindAt': '2020-01-01T00:00:00',
        };
        expect(TestSuggestionService.isDue(s, now: now), isFalse);
        expect(TestSuggestionService.isOpen(s), isFalse);
      }
    });
  });
}
