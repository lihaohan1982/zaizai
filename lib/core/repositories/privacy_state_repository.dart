// lib/core/repositories/privacy_state_repository.dart
import 'package:hive/hive.dart';
import 'package:location_chat_app/core/models/privacy_state.dart';

abstract class PrivacyStateRepository {
  Future<void> saveState(PrivacyState state);
  Future<PrivacyState> loadState();
}

class LocalPrivacyStateRepository implements PrivacyStateRepository {
  static const String _stateKey = 'global_privacy_state';
  final Box<dynamic> _box;

  /// [架构] 严格的依赖注入
  LocalPrivacyStateRepository(this._box);

  @override
  Future<void> saveState(PrivacyState state) async {
    await _box.put(_stateKey, state.toHiveMap());
  }

  @override
  Future<PrivacyState> loadState() async {
    final map = _box.get(_stateKey);
    if (map == null) return const PrivacyState(); // 默认未暂停
    return PrivacyState.fromHiveMap(map);
  }
}
