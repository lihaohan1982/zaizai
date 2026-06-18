// test/core/privacy/fakes/fake_geofence_repository.dart

import 'package:location_chat_app/core/models/geofence_config_data.dart';
import 'package:location_chat_app/core/repositories/geofence_repository.dart';

class FakeGeofenceRepository implements GeofenceRepository {
  GeofenceConfigData? _config;
  bool throwOnLoad = false;

  void setConfig(GeofenceConfigData config) {
    _config = config;
  }

  void clear() {
    _config = null;
    throwOnLoad = false;
  }

  @override
  Future<GeofenceConfigData?> loadConfig(String fenceId) async {
    if (throwOnLoad) throw Exception('Load failed');
    return _config;
  }

  @override
  Future<void> saveConfig(GeofenceConfigData config) async {
    _config = config;
  }

  @override
  Future<void> deleteConfig(String fenceId) async {
    _config = null;
  }
}
