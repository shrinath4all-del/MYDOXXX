import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/widgets/chat_cards.dart';

Widget _host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  final request = {
    'messageId': 'm1',
    'type': 'call_request',
    'callType': 'audio',
    'callStatus': 'requested',
    'createdAt': '2026-10-29T16:05:00',
  };

  testWidgets('the doctor accepts or declines a call request',
      (tester) async {
    var accepted = false, declined = false;
    await tester.pumpWidget(_host(CallRequestCard(
      message: {...request, 'senderName': 'Ravi'},
      providerView: true,
      canStart: true,
      onAccept: () => accepted = true,
      onDecline: () => declined = true,
    )));
    expect(find.text('Ravi asks for an audio call'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.tap(find.text('Decline'));
    expect(accepted, isTrue);
    expect(declined, isTrue);
  });

  testWidgets('the patient can cancel a request, then start and end a call',
      (tester) async {
    var cancelled = false, started = false, ended = false;
    Widget card(String status) => _host(CallRequestCard(
          message: {...request, 'callType': 'video', 'callStatus': status},
          providerView: false,
          canStart: true,
          onCancel: () => cancelled = true,
          onStart: () => started = true,
          onEnd: () => ended = true,
        ));
    await tester.pumpWidget(card('requested'));
    expect(find.text('Video call request'), findsOneWidget);
    await tester.tap(find.text('Cancel request'));
    await tester.pumpWidget(card('accepted'));
    await tester.tap(find.text('Start video call'));
    await tester.pumpWidget(card('started'));
    await tester.tap(find.text('End call'));
    expect([cancelled, started, ended], [true, true, true]);
    await tester.pumpWidget(card('completed'));
    expect(find.byType(ElevatedButton), findsNothing);
  });

  test('call status labels', () {
    expect(CallRequestCard.statusLabel({'callStatus': 'started'}), 'On call');
    expect(
        CallRequestCard.statusLabel({'callStatus': 'completed', 'callSeconds': 125}),
        'Call completed · 02:05');
    expect(CallRequestCard.statusLabel({'callStatus': 'missed'}), 'Missed call');
    expect(CallRequestCard.statusLabel({'callStatus': 'cancelled'}),
        'Request cancelled');
    expect(CallRequestCard.statusLabel({}), 'Waiting for the doctor');
  });

  testWidgets('a prescription is labelled and shows when it was sent',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(_host(PrescriptionCard(
      message: {
        'type': 'prescription',
        'fileName': 'rx.pdf',
        'senderName': 'Dr. Asha',
        'createdAt': '2026-10-29T16:05:00',
      },
      isMe: false,
      onOpen: () => opened = true,
    )));
    expect(find.text('PRESCRIPTION'), findsOneWidget);
    expect(find.textContaining('Sent 29 Oct'), findsOneWidget);
    await tester.tap(find.text('rx.pdf'));
    expect(opened, isTrue);
  });

  testWidgets('a file says what it is before it is opened', (tester) async {
    await tester.pumpWidget(_host(ChatFileTile(
      icon: Icons.audiotrack_rounded,
      kind: 'Audio',
      fileName: 'note.m4a',
      action: 'Tap to play',
      isMe: false,
      onTap: () {},
    )));
    expect(find.text('AUDIO'), findsOneWidget);
    expect(find.text('note.m4a'), findsOneWidget);
  });
}
