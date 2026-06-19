// test/core/repositories/geofence_repository_test.dart
//
// H-4 修复验证：加密坐标存取全链路测试
// 验证 saveConfig → loadConfig 往返时，加密坐标能正确还原为 double

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:location_chat_app/core/models/geofence_config_data.dart';
import 'package:location_chat_app/core/repositories/geofence_repository.dart';
import 'package:location_chat_app/core/security/geo_encryption_service.dart';

// ---- Fake Encryption Service (可逆的简单实现，用于单元测试) ----

class FakeEncryptionService implements GeoEncryptionService {
  @override
  Future<String> encrypt(String plainText) async {
    // 简单可逆：base64 编码模拟加密，返回格式与 Prod 一致
    return 'FAKE:${base64Encode(utf8.encode(plainText))}';
  }

  @override
  Future<String> decrypt(String cipherText) async {
    if (!cipherText.startsWith('FAKE:')) {
      throw Exception('Invalid ciphertext format');
    }
    final b64part = cipherText.substring(5);
    return utf8.decode(base64Decode(b64part));
  }
}

// ---- Helper ----

GeofenceConfigData _makeConfig({
  String fenceId = 'fence_001',
  double lat = 39.9042,
  double lon = 116.4074,
  double radius = 200.0,
}) {
  return GeofenceConfigData(
    fenceId: fenceId,
    centerLat: lat,
    centerLon: lon,
    radiusMeters: radius,
  );
}

void main() {
  late Box<dynamic> box;
  late FakeEncryptionService encryption;
  late LocalGeofenceRepository repo;

  setUp(() async {
    // Hive 内存测试 Box
    Hive.init('./test_temp_hive');
    box = await Hive.openBox<dynamic>('geofence_test_${DateTime.now().millisecondsSinceEpoch}');
    encryption = FakeEncryptionService();
    repo = LocalGeofenceRepository(box, encryption);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk(box.name);
  });

  group('H-4 围栏加密存储往返测试', () {
    test('saveConfig → loadConfig: 坐标经加密存储后可正确还原', () async {
      final config = _makeConfig(lat: 39.9042, lon: 116.4074);

      await repo.saveConfig(config);
      final loaded = await repo.loadConfig(config.fenceId);

      expect(loaded, isNotNull);
      expect(loaded!.centerLat, equals(39.9042));
      expect(loaded.centerLon, equals(116.4074));
      expect(loaded.radiusMeters, equals(200.0));
      expect(loaded.fenceId, equals('fence_001'));
    });

    test('saveConfig: Hive 中不存储明文坐标（centerLat/centerLon）', () async {
      final config = _makeConfig();

      await repo.saveConfig(config);

      final stored = box.get(config.fenceId) as Map<dynamic, dynamic>;
      // 明文字段必须已移除
      expect(stored.containsKey('centerLat'), isFalse,
          reason: 'centerLat 明文不应存在');
      expect(stored.containsKey('centerLon'), isFalse,
          reason: 'centerLon 明文不应存在');
      // 加密字段必须存在
      expect(stored.containsKey('centerLatEnc'), isTrue);
      expect(stored.containsKey('centerLonEnc'), isTrue);
      // 加密字段是字符串
      expect(stored['centerLatEnc'], isA<String>());
      expect(stored['centerLonEnc'], isA<String>());
    });

    test('loadConfig: 不存在的 fenceId 返回 null', () async {
      final result = await repo.loadConfig('nonexistent');
      expect(result, isNull);
    });

    test('deleteConfig: 删除后 loadConfig 返回 null', () async {
      final config = _makeConfig();
      await repo.saveConfig(config);

      await repo.deleteConfig(config.fenceId);
      final result = await repo.loadConfig(config.fenceId);
      expect(result, isNull);
    });

    test('saveConfig → loadConfig: 负数坐标（西半球/南半球）正确处理', () async {
      final config = _makeConfig(lat: -33.8688, lon: -63.1816);

      await repo.saveConfig(config);
      final loaded = await repo.loadConfig(config.fenceId);

      expect(loaded!.centerLat, equals(-33.8688));
      expect(loaded.centerLon, equals(-63.1816));
    });

    test('saveConfig → loadConfig: 多次写入同 fenceId 以最后一次为准', () async {
      final config1 = _makeConfig(lat: 39.9042, lon: 116.4074);
      final config2 = _makeConfig(lat: 31.2304, lon: 121.4737);

      await repo.saveConfig(config1);
      await repo.saveConfig(config2);
      final loaded = await repo.loadConfig(config1.fenceId);

      expect(loaded!.centerLat, equals(31.2304));
      expect(loaded.centerLon, equals(121.4737));
    });

    test('saveConfig → loadConfig: 多个围栏互不干扰', () async {
      final config1 =
          _makeConfig(fenceId: 'fence_A', lat: 39.9042, lon: 116.4074);
      final config2 =
          _makeConfig(fenceId: 'fence_B', lat: 31.2304, lon: 121.4737);

      await repo.saveConfig(config1);
      await repo.saveConfig(config2);

      final loaded1 = await repo.loadConfig('fence_A');
      final loaded2 = await repo.loadConfig('fence_B');

      expect(loaded1!.centerLat, equals(39.9042));
      expect(loaded2!.centerLat, equals(31.2304));
    });
  });
}
