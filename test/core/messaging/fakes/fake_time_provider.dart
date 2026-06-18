// test/core/messaging/fakes/fake_time_provider.dart

import 'dart:async';
import 'package:location_chat_app/core/messaging/quick_message_service.dart';

class FakeTimeProvider implements TimeProvider {
  DateTime _now;

  FakeTimeProvider([DateTime? initial])
      : _now = initial ?? DateTime(2026, 6, 17, 10, 0, 0);

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  void setTime(DateTime time) {
    _now = time;
  }

  void reset() {
    _now = DateTime(2026, 6, 17, 10, 0, 0);
  }

  @override
  Timer createTimer(Duration duration, void Function() callback) {
    return _FakeTimer(callback);
  }
}

class _FakeTimer implements Timer {
  final void Function() callback;
  bool _cancelled = false;

  _FakeTimer(this.callback);

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;
}
