import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/utils/duty_request_status.dart';

void main() {
  final legacy = <String, dynamic>{
    'id': 'old-request',
    'type': 'leave',
    'status': 'awaiting_hospital',
    'agencyId': 'agency-a',
    'requesterUid': 'worker-a',
    'sourceKey': '2099-01-01|morning',
  };

  test(
    'existing pending leave is visible and actionable only in its agency',
    () {
      expect(DutyRequestStatus.legacyForApprover(legacy, 'agency-a'), isTrue);
      expect(DutyRequestStatus.canDecide(legacy, 'agency-a'), isTrue);
      expect(DutyRequestStatus.legacyForApprover(legacy, 'agency-b'), isFalse);
      expect(DutyRequestStatus.canDecide(legacy, 'agency-b'), isFalse);
      expect(
        legacy.containsKey('approverId'),
        isFalse,
      ); // reading does not migrate
    },
  );

  test(
    'legacy platform leave and an explicit new approver retain correct scope',
    () {
      final freelancer = {...legacy, 'agencyId': ''};
      expect(DutyRequestStatus.canDecide(freelancer, 'platform'), isTrue);
      expect(DutyRequestStatus.canDecide(freelancer, 'agency-a'), isFalse);
      final redirected = {
        ...legacy,
        'approverId': 'agency-b',
        'status': 'awaiting_agency',
      };
      expect(DutyRequestStatus.canDecide(redirected, 'agency-b'), isTrue);
      expect(DutyRequestStatus.canDecide(redirected, 'agency-a'), isFalse);
      expect(
        DutyRequestStatus.legacyForApprover(redirected, 'agency-a'),
        isFalse,
      );
    },
  );

  test(
    'old and new pending leave both prevent conflicting duties and allow owner withdrawal',
    () {
      for (final status in [
        'awaiting_hospital',
        'awaiting_agency',
        'pending',
      ]) {
        final request = {...legacy, 'status': status};
        expect(
          DutyRequestStatus.blocksDuty(request, ['2099-01-01|morning']),
          isTrue,
        );
        expect(
          DutyRequestStatus.blocksDuty(request, ['2099-01-02|morning']),
          isFalse,
        );
        expect(DutyRequestStatus.canWithdraw(request, 'worker-a'), isTrue);
        expect(DutyRequestStatus.canWithdraw(request, 'worker-b'), isFalse);
      }
    },
  );

  test('closed leave and swaps cannot re-enter the approval path', () {
    for (final status in ['pending', 'accepted', 'declined', 'withdrawn']) {
      expect(
        DutyRequestStatus.canDecide({...legacy, 'status': status}, 'agency-a'),
        isFalse,
      );
    }
    for (final status in ['accepted', 'declined', 'withdrawn']) {
      final closed = {...legacy, 'status': status};
      expect(DutyRequestStatus.canWithdraw(closed, 'worker-a'), isFalse);
      expect(
        DutyRequestStatus.blocksDuty(closed, ['2099-01-01|morning']),
        isFalse,
      );
      expect(DutyRequestStatus.legacyForApprover(closed, 'agency-a'), isTrue,
          reason: 'closed requests remain visible in their agency history');
    }
    expect(
      DutyRequestStatus.canDecide({...legacy, 'type': 'swap'}, 'agency-a'),
      isFalse,
    );
  });

  test('approved and covered legacy leave stays in its agency calendar and history', () {
    for (final status in ['pending', 'accepted']) {
      final request = {...legacy, 'status': status};
      expect(DutyRequestStatus.legacyForApprover(request, 'agency-a'), isTrue);
      expect(DutyRequestStatus.legacyForApprover(request, 'agency-b'), isFalse);
      expect(DutyRequestStatus.canDecide(request, 'agency-a'), isFalse);
    }
  });
}
