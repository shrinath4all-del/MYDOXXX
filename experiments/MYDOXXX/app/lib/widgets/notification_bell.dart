import '../services/app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/notification_inbox.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../constants/app_colors.dart';
import '../utils/ist_clock.dart';

/// Bell icon with an unread badge and the notifications list, at the top of
/// every login. The list holds every notification sent to the account (see
/// NotificationInbox) plus the screen's own events: bookings-based roles pass
/// [bookings]; hospitals, ambulances and care physicians pass ready-made
/// [events] (see RoleNotifications); agencies pass neither. Tapping a push
/// notification on the phone opens the same list (see
/// [PushService.openSignal]).
class NotificationBell extends StatefulWidget {
  final String uid;

  /// Firestore collection that stores `notificationsReadAt` ('patients',
  /// 'doctors', 'agencies' …).
  final String collection;
  final bool forPatient;
  final Stream<List<Map<String, dynamic>>>? bookings;

  /// Ready-made notifications ({kind, title, body, at}), newest first.
  final Stream<List<Map<String, String>>>? events;

  /// Called when a notification in the list is tapped (e.g. open My Bookings).
  final VoidCallback onOpenItem;
  final Color iconColor;
  final bool includeOffers;

  const NotificationBell({
    super.key,
    required this.uid,
    required this.collection,
    required this.forPatient,
    this.bookings,
    this.events,
    required this.onOpenItem,
    this.iconColor = AppTheme.darkNavy,
    this.includeOffers = true,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  DateTime? _readAt;
  List<Map<String, String>> _events = [];
  bool _loaded = false; // bookings have arrived at least once
  bool _wantOpen = false; // a tapped push is waiting for the list
  bool _sheetOpen = false;
  late final Stream<List<Map<String, String>>> _inbox =
      NotificationInbox.stream(widget.uid);

  @override
  void initState() {
    super.initState();
    _loadReadAt();
    PushService.openSignal.addListener(_onPushTapped);
    // App was launched by tapping a notification
    if (PushService.pendingOpen) _wantOpen = true;
  }

  @override
  void dispose() {
    PushService.openSignal.removeListener(_onPushTapped);
    super.dispose();
  }

  void _onPushTapped() {
    _wantOpen = true;
    if (_loaded) _maybeOpen();
  }

  void _maybeOpen() {
    if (!_wantOpen || _sheetOpen || !mounted) return;
    _wantOpen = false;
    PushService.pendingOpen = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSheet();
    });
  }

  Future<void> _loadReadAt() async {
    try {
      final doc = await AppDatabase.instance
          .collection(widget.collection)
          .doc(widget.uid)
          .get();
      final at = IstClock.tryParse(
          (doc.data()?['notificationsReadAt'] ?? '').toString());
      if (mounted) setState(() => _readAt = at);
    } catch (_) {}
  }

  Future<void> _markRead() async {
    final now = IstClock.now();
    if (mounted) setState(() => _readAt = now);
    try {
      await AppDatabase.instance
          .collection(widget.collection)
          .doc(widget.uid)
          .set({'notificationsReadAt': now.toIso8601String()},
              SetOptions(merge: true));
    } catch (_) {}
  }

  static IconData _icon(String kind) {
    switch (kind) {
      case 'accepted':
      case 'booked':
        return Icons.check_circle_outline_rounded;
      case 'late':
        return Icons.schedule_rounded;
      case 'started':
        return Icons.play_circle_outline_rounded;
      case 'completed':
      case 'rated':
        return Icons.star_outline_rounded;
      case 'request':
      case 'offer':
        return Icons.campaign_outlined;
      case 'absent':
      case 'declined':
      case 'lateStart':
        return Icons.warning_amber_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  void _openSheet() {
    if (_sheetOpen) return;
    _sheetOpen = true;
    final events = _events;
    final size = MediaQuery.sizeOf(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Notifications',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy)),
              const SizedBox(height: 8),
              if (events.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No notifications yet. Updates will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted)),
                ),
              ...events.take(NotificationInbox.limit).map((e) {
                final warn = e['kind'] == 'absent' ||
                    e['kind'] == 'declined' ||
                    e['kind'] == 'lateStart';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        warn ? AppColors.dangerSoft : AppTheme.pastelBlue,
                    child: Icon(_icon(e['kind']!),
                        color: warn ? AppColors.danger : AppTheme.primaryTeal),
                  ),
                  title: Text(e['title']!,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle:
                      Text(e['body']!, style: const TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onOpenItem();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      _sheetOpen = false;
      _markRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, String>>>(
      stream: _inbox,
      builder: (context, inbox) => _screenEvents(
        (events, hasData) => _bell(
          NotificationInbox.merge(inbox.data ?? const [], events),
          hasData || inbox.hasData,
        ),
      ),
    );
  }

  /// The screen's own events (none for agencies).
  Widget _screenEvents(
      Widget Function(List<Map<String, String>> events, bool hasData) show) {
    if (widget.events != null) {
      return StreamBuilder<List<Map<String, String>>>(
        stream: widget.events,
        builder: (context, snap) => show(snap.data ?? const [], snap.hasData),
      );
    }
    if (widget.bookings == null) return show(const [], true);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.bookings,
      builder: (context, snap) => show(
        FirestoreService.bookingNotifications(
          snap.data ?? [],
          uid: widget.uid,
          forPatient: widget.forPatient,
          includeOffers: widget.includeOffers,
        ),
        snap.hasData,
      ),
    );
  }

  Widget _bell(List<Map<String, String>> events, bool hasData) {
    // a new-shift notice already seen is not listed again
    _events = NotificationInbox.withoutSeenOffers(events, _readAt);
    if (hasData && !_loaded) {
      _loaded = true;
      if (_wantOpen) _maybeOpen();
    }
    final unread = _events.where((e) {
      final readAt = _readAt;
      if (readAt == null) return true;
      final at = IstClock.tryParse(e['at']!);
      return at == null || at.isAfter(readAt);
    }).length;
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: Icon(Icons.notifications_none_rounded,
            color: widget.iconColor, size: 24),
      ),
      onPressed: _openSheet,
    );
  }
}
