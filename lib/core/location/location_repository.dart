import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_chat_app/core/network/dio_client.dart';
import 'package:location_chat_app/core/security/geo_encryption_service.dart';

/// 位置数据仓库 - 负责将加密后的位置数据发送给后端
class LocationRepository {
  final Dio _dio;
  final GeoEncryptionService _encryptionService;

  LocationRepository({
    required Dio dio,
    required GeoEncryptionService encryptionService,
  })  : _dio = dio,
        _encryptionService = encryptionService;

  /// 将位置数据上报给后端（先加密再发送）
  Future<void> reportLocation({
    required double lat,
    required double lng,
    required double accuracy,
    required int battery,
    required bool charging,
  }) async {
    try {
      // 1. 构造明文位置数据
      final plainText = json.encode({
        'lat': lat,
        'lng': lng,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // 2. 加密位置数据
      final encryptedPayload = await _encryptionService.encrypt(plainText);

      // 3. 发送加密后的数据到后端
      await _dio.post(
        '/api/location/update',
        data: {
          'encryptedPayload': encryptedPayload,
          'accuracy': accuracy,
          'battery': battery,
          'charging': charging,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      // 网络异常或 403 (暂停状态) 统一在这里处理，不阻断引擎运行
      debugPrint('Location report failed: $e');
      rethrow;
    }
  }
}

/// Provider: 提供 LocationRepository 单例
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(
    dio: DioClient().dio,
    // ✅ ProdGeoEncryptionService（AES-256-GCM，密钥存 Keychain/Keystore）
    // DevGeoEncryptionService 已禁用：encrypt/decrypt 均抛异常
    encryptionService: ProdGeoEncryptionService(),
  );
});
