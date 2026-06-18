// test/core/messaging/fakes/fake_uuid_provider.dart

import 'package:location_chat_app/core/messaging/quick_message_service.dart';

class FakeUuidProvider implements UuidProvider {
  int _counter = 0;

  @override
  String v4() {
    _counter++;
    return 'test-uuid-$_counter';
  }

  void reset() {
    _counter = 0;
  }
}
