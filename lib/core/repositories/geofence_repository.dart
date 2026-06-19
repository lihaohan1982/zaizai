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

    // [安全] 加密坐标存为字符串字段，移除明文
    map['centerLatEnc'] =
        await _encryptionService.encrypt(config.centerLat.toString());
    map['centerLonEnc'] =
        await _encryptionService.encrypt(config.centerLon.toString());
    map.remove('centerLat');
    map.remove('centerLon');

    await _box.put(config.fenceId, map);
  }

  @override
  Future<GeofenceConfigData?> loadConfig(String fenceId) async {
    final map = _box.get(fenceId);
    if (map == null) return null;

    try {
      final rebuilt = Map<String, dynamic>.from(map);
      // [安全] 解密加密字段还原为 double
      if (rebuilt.containsKey('centerLatEnc')) {
        rebuilt['centerLat'] =
            double.parse(await _encryptionService.decrypt(rebuilt['centerLatEnc'] as String));
        rebuilt.remove('centerLatEnc');
      }
      if (rebuilt.containsKey('centerLonEnc')) {
        rebuilt['centerLon'] =
            double.parse(await _encryptionService.decrypt(rebuilt['centerLonEnc'] as String));
        rebuilt.remove('centerLonEnc');
      }
      return GeofenceConfigData.fromHiveMap(rebuilt);
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
