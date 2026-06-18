import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location_chat_app/core/location/location_strategy.dart';

void main() {
  late LocationStrategyEngine engine;
  setUp(() => engine = LocationStrategyEngine.instance);

  Position mockPos({
    required double lat, required double lng,
    double speed = 0.0, double accuracy = 10.0,
  }) {
    return Position(
      latitude: lat, longitude: lng, timestamp: DateTime.now(),
      accuracy: accuracy, altitude: 0, altitudeAccuracy: 0,
      heading: 0, headingAccuracy: 0, speed: speed, speedAccuracy: 0,
      isMocked: false,
    );
  }

  const double lat1 = 39.9042; // 北京
  const double lng1 = 116.4074;
  const double lat2 = 39.9142; // 北偏 ~1.1km

  // 所有需要测试"非首次上报"逻辑的用例，必须传 lastReportTime
  // 否则 null 会触发首次定位→直接上报分支

  group('① shouldWakeUp：严格大于 0.5 m/s', () {
    test('speed = 0.0 → false', () => expect(engine.shouldWakeUp(0.0), isFalse));
    test('speed = 0.5（边界值）→ false', () => expect(engine.shouldWakeUp(0.5), isFalse));
    test('speed = 0.51 → true', () => expect(engine.shouldWakeUp(0.51), isTrue));
    test('speed = 1.5（步行）→ true', () => expect(engine.shouldWakeUp(1.5), isTrue));
    test('speed = 2.0（步行上限）→ true', () => expect(engine.shouldWakeUp(2.0), isTrue));
    test('speed = 12.0（驾车下限）→ true', () => expect(engine.shouldWakeUp(12.0), isTrue));
    test('speed = 30.0（高速）→ true', () => expect(engine.shouldWakeUp(30.0), isTrue));
  });

  group('② 精度过滤：accuracy > 100m → 丢弃', () {
    test('accuracy = 100m（边界值）→ 参与判断', () {
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, accuracy: 100.0),
      ), isNotNull);
    });
    test('accuracy = 101m → 丢弃', () {
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, accuracy: 101.0),
      ), isNull);
    });
  });

  group('③ 首次定位直接上报（lastReportTime=null）', () {
    test('静止 → 5分钟', () {
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, speed: 0.0),
      ), equals(Duration(minutes: 5)));
    });
    test('步行 → 1分钟', () {
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, speed: 1.5),
      ), equals(Duration(minutes: 1)));
    });
    test('驾车 → 20秒', () {
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, speed: 15.0),
      ), equals(Duration(seconds: 20)));
    });
  });

  group('④ 位移触发：distance >= 50m 立即上报（lastReportTime 有值）', () {
    test('位移 0m → 不上报（时间未达）', () {
      final last = mockPos(lat: lat1, lng: lng1);
      final cur = mockPos(lat: lat1, lng: lng1);
      // 位移 0 < 50；时间刚上报过（lastReportTime=now），不足间隔 → null
      expect(engine.shouldReport(
        current: cur, last: last,
        lastReportTime: DateTime.now(),
      ), isNull);
    });

    test('位移 49m → 不上报', () {
      final last = mockPos(lat: lat1, lng: lng1);
      final cur = mockPos(lat: lat1 + 0.00044, lng: lng1);
      expect(engine.shouldReport(
        current: cur, last: last,
        lastReportTime: DateTime.now(),
      ), isNull);
    });

    test('位移 50m（边界值）→ 上报', () {
      final last = mockPos(lat: lat1, lng: lng1);
      final cur = mockPos(lat: lat1 + 0.00045, lng: lng1);
      expect(engine.shouldReport(
        current: cur, last: last,
        lastReportTime: DateTime.now(),
      ), isNotNull);
    });

    test('位移 1.1km → 上报', () {
      final last = mockPos(lat: lat1, lng: lng1);
      final cur = mockPos(lat: lat2, lng: lng1);
      expect(engine.shouldReport(
        current: cur, last: last,
        lastReportTime: DateTime.now(),
      ), isNotNull);
    });
  });

  group('⑤ 速度 → 上报间隔（lastReportTime 足够久，触发间隔判断）', () {
    // lastReportTime 必须足够旧（> interval），elapsed >= requiredInterval 才返回间隔
    test('静止 → 5分钟', () {
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, speed: 0.0),
        lastReportTime: DateTime.now().subtract(Duration(minutes: 6)),
      ), equals(Duration(minutes: 5)));
    });
    test('步行 → 1分钟', () {
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, speed: 1.5),
        lastReportTime: DateTime.now().subtract(Duration(minutes: 2)),
      ), equals(Duration(minutes: 1)));
    });
    test('跑步/骑行 → 2分钟', () {
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, speed: 5.0),
        lastReportTime: DateTime.now().subtract(Duration(minutes: 3)),
      ), equals(Duration(minutes: 2)));
    });
    test('驾车 → 20秒', () {
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, speed: 15.0),
        lastReportTime: DateTime.now().subtract(Duration(seconds: 30)),
      ), equals(Duration(seconds: 20)));
    });
  });

  group('⑥ 时间间隔未达标不触发上报', () {
    test('静止 1 分钟（需等 5 分钟）→ null', () {
      final lastReport = DateTime.now().subtract(Duration(minutes: 1));
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, speed: 0.0),
        lastReportTime: lastReport,
      ), isNull);
    });
    test('静止 6 分钟 → 上报', () {
      final lastReport = DateTime.now().subtract(Duration(minutes: 6));
      expect(engine.shouldReport(
        current: mockPos(lat: lat1, lng: lng1, speed: 0.0),
        lastReportTime: lastReport,
      ), equals(Duration(minutes: 5)));
    });
  });

  group('⑦ Haversine 距离计算验证（lastReportTime 有值）', () {
    test('同一点距离 = 0 → 时间未达，不触发', () {
      final last = mockPos(lat: lat1, lng: lng1);
      final cur = mockPos(lat: lat1, lng: lng1);
      expect(engine.shouldReport(
        current: cur, last: last,
        lastReportTime: DateTime.now(),
      ), isNull);
    });
    test('赤道上 1 度经度 ≈ 111km → 位移远超 50m → 触发', () {
      final last = mockPos(lat: 0.0, lng: 0.0);
      final cur = mockPos(lat: 0.0, lng: 1.0);
      expect(engine.shouldReport(
        current: cur, last: last,
        lastReportTime: DateTime.now(),
      ), isNotNull);
    });
  });
}
