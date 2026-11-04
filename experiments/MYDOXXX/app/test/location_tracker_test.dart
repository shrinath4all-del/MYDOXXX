import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/location_tracker.dart';

void main() {
  final t0 = DateTime(2026, 10, 16, 10);

  test('the first position is always saved', () {
    expect(LocationTracker.shouldSave(now: t0), isTrue);
  });

  test('standing still: saved at most every 30 s', () {
    expect(
        LocationTracker.shouldSave(
            now: t0.add(const Duration(seconds: 20)),
            lastSavedAt: t0,
            movedMetres: 40),
        isFalse);
    expect(
        LocationTracker.shouldSave(
            now: t0.add(const Duration(seconds: 30)),
            lastSavedAt: t0,
            movedMetres: 0),
        isTrue);
  });

  test('moving fast (ambulance): saved every 10 s once 100 m away', () {
    expect(
        LocationTracker.shouldSave(
            now: t0.add(const Duration(seconds: 12)),
            lastSavedAt: t0,
            movedMetres: 150),
        isTrue);
    expect(
        LocationTracker.shouldSave(
            now: t0.add(const Duration(seconds: 5)),
            lastSavedAt: t0,
            movedMetres: 400),
        isFalse,
        reason: 'not more often than every 10 s');
  });

  test('not tracked in tests / on web or desktop', () async {
    expect(await LocationTracker.start(collection: 'doctors', uid: 'd1'),
        isFalse);
    expect(LocationTracker.isRunning, isFalse);
  });
}
