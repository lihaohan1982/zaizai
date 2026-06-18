// test/core/privacy/fakes/fake_privacy_state_repository.dart

import 'package:location_chat_app/core/models/privacy_state.dart';
import 'package:location_chat_app/core/repositories/privacy_state_repository.dart';

class FakePrivacyStateRepository implements PrivacyStateRepository {
  PrivacyState? _state;
  bool throwOnSave = false;
  final List<PrivacyState> _saved = [];

  List<PrivacyState> get savedStates => List.unmodifiable(_saved);

  void setState(PrivacyState state) {
    _state = state;
  }

  void clear() {
    _state = null;
    throwOnSave = false;
    _saved.clear();
  }

  @override
  Future<PrivacyState> loadState() async {
    return _state ?? const PrivacyState(isPaused: false);
  }

  @override
  Future<void> saveState(PrivacyState state) async {
    if (throwOnSave) throw Exception('Save failed');
    _saved.add(state);
    _state = state;
  }
}
