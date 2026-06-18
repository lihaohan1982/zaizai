// lib/core/repositories/geofence_repository.dart
import 'package:hive/hive.dart';
import 'package:location_chat_app/core/models/geofence_config_data.dart';
import 'package:location_chat_app/core/security/geo_encryption_service.dart';

abstract class GeofenceRepository {
  Future<void> saveConfig(GeofenceConfigData config);
  Future<GeofenceConfigData?> loadConfig(String fenceId);
  Future<void> deleteConfig(String fenceId);
}

class LocalGeofenceRepository implements GeofenceRepository {
  final Box<dynamic> _box;
  final GeoEncryptionService _encryptionService;

  /// [架构] 严格的依赖注入，测试时可轻松替换为 FakeBox
  LocalGeofenceRepository(this._box, this._encryptionService);

  @override
  Future<void> saveConfig(GeofenceConfigData config) async {
    final map = config.toHiveMap();

    // [安全] 落盘前加密敏感坐标
    map['centerLat'] =
        double.parse(await _encryptionService.encrypt(map['centerLat'].toString()));
    map['centerLon'] =
        double.parse(await _encryptionService.encrypt(map['centerLon'].toString()));

    await _box.put(config.fenceId, map);
  }

  @override
  Future<GeofenceConfigData?> loadConfig(String fenceId) async {
    final map = _box.get(fenceId);
    if (map == null) return null;

    try {
      // [安全] 读取时解密
      map['centerLat'] =
          double.parse(await _encryptionService.decrypt(map['centerLat'].toString()));
      map['centerLon'] =
          double.parse(await _encryptionService.decrypt(map['centerLon'].toString()));
      return GeofenceConfigData.fromHiveMap(map);
    } catch (e) {
      // 数据损坏或密钥丢失时静默失败，让上层重建
      return null;
    }
  }

  @override
  Future<void> deleteConfig(String fenceId) async {
    await _box.delete(fenceId);
  }
}
