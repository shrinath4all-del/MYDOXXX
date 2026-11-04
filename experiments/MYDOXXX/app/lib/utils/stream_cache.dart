import 'dart:async';

/// Keeps one live Firestore stream per key for a screen, so redraws
/// (typing, timers, location updates) reuse the open connection instead of
/// opening a new one and downloading the data again.
///
/// Each cached stream can be listened to by several widgets and by widgets
/// that come and go (tabs): a new listener immediately gets the latest
/// value, and the Firestore listener closes once nobody is listening.
class StreamCache {
  final Map<String, Stream<dynamic>> _streams = {};

  Stream<T> get<T>(String key, Stream<T> Function() create) =>
      (_streams[key] ??= _shareLatest<T>(create)) as Stream<T>;

  static Stream<T> _shareLatest<T>(Stream<T> Function() create) {
    final listeners = <MultiStreamController<T>>{};
    StreamSubscription<T>? source;
    late T latest;
    var hasLatest = false;

    return Stream<T>.multi((controller) {
      listeners.add(controller);
      if (hasLatest) controller.add(latest);
      source ??= create().listen(
        (value) {
          latest = value;
          hasLatest = true;
          for (final l in listeners.toList()) {
            l.add(value);
          }
        },
        onError: (Object e, StackTrace st) {
          for (final l in listeners.toList()) {
            l.addError(e, st);
          }
        },
      );
      controller.onCancel = () {
        listeners.remove(controller);
        if (listeners.isEmpty) {
          source?.cancel();
          source = null;
          hasLatest = false;
        }
      };
    });
  }
}

/// Emits [combine] of the latest values of [a] and [b] once both have sent
/// one, and again whenever either changes.
Stream<R> combineLatest2<A, B, R>(
    Stream<A> a, Stream<B> b, R Function(A a, B b) combine) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false, hasB = false;
  void emit() {
    if (hasA && hasB) controller.add(combine(lastA as A, lastB as B));
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen((v) {
        lastA = v;
        hasA = true;
        emit();
      }, onError: controller.addError);
      subB = b.listen((v) {
        lastB = v;
        hasB = true;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}
