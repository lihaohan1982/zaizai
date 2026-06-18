import 'dart:async';
import 'dart:ui' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location_chat_app/core/geofence/geofence_state_machine.dart';

// ─── Fake Timer & TimeProvider ────────────────────────────────

class _NoopTimer implements Timer {
  bool _cancelled = false;
  @override void cancel() => _cancelled = true;
  @override bool get isActive => !_cancelled;
  @override int get tick => 0;
}

class FakeTimeProvider implements TimeProvider {
  DateTime _now = DateTime(2024, 1, 1);

  // 记录 (timer, callback)，elapse 时检查 isActive
  final List<(Timer, VoidCallback)> _scheduled = [];

  @override DateTime now() => _now;

  @override
  Timer createTimer(Duration duration, VoidCallback callback) {
    final timer = _NoopTimer();
    _scheduled.add((timer, callback));
    return timer;
  }

  /// 推进时间并只触发未被取消的 Timer 回调
  void elapse(Duration d) {
    _now = _now.add(d);
    final batch = List<(Timer, VoidCallback)>.from(_scheduled);
    _scheduled.clear();
    for (final (timer, cb) in batch) {
      if (timer.isActive) cb();
    }
  }

  /// 仅推进时间，不触发回调
  void advance(Duration d) => _now = _now.add(d);
}

// ─── Helpers ─────────────────────────────────────────────────

Position _pos(double accuracy,
    {double lat = 30.0, double lon = 120.0}) {
  return Position(
    latitude: lat, longitude: lon, timestamp: DateTime.now(),
    accuracy: accuracy, altitude: 0, heading: 0, speed: 0,
    speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
    isMocked: false,
  );
}

const _fenceLat = 30.0;
const _fenceLon = 120.0;
const _fenceRadius = 100.0;

Position get _inside => _pos(10.0, lat: 30.0003, lon: 120.0003);
Position get _outside => _pos(10.0, lat: 30.002, lon: 120.002);

// ─── 冷启动完成 helpers ─────────────────────────────────────

void _coldStartOutside(GeofenceStateMachine m, FakeTimeProvider t) {
  m.evaluatePosition(_outside); t.advance(Duration(seconds: 10));
  m.evaluatePosition(_outside); t.advance(Duration(seconds: 10));
  m.evaluatePosition(_outside);
}

void _coldStartInside(GeofenceStateMachine m, FakeTimeProvider t) {
  m.evaluatePosition(_inside); t.advance(Duration(seconds: 10));
  m.evaluatePosition(_inside); t.advance(Duration(seconds: 10));
  m.evaluatePosition(_inside);
}

// ─── Tests ────────────────────────────────────────────────────

void main() {

  group('【V5.3】suspend() 彻底休眠', () {
    test('suspend() 期间 evaluatePosition 被静默丢弃', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartInside(m, t);
      expect(m.statusNotifier.value, GeofenceStatus.inside);
      m.suspend();
      expect(m.statusNotifier.value, GeofenceStatus.outside);
      m.evaluatePosition(_inside); // 静默丢弃
      m.evaluatePosition(_inside);
      expect(m.statusNotifier.value, GeofenceStatus.outside);
      m.dispose();
    });

    test('suspend() 取消计时器，elapse 不触发已取消的 Timer', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartOutside(m, t);
      m.evaluatePosition(_inside); // 开始 120s 防抖
      expect(m.statusNotifier.value, GeofenceStatus.transitioning);
      m.suspend(); // 取消 Timer

      // 30s 后：Timer 已取消，不触发
      t.elapse(Duration(seconds: 30));
      expect(m.statusNotifier.value, GeofenceStatus.outside);

      m.dispose();
    });
  });

  group('【V5.3】resume() 强制重新冷启动', () {
    test('resume() 后状态被重置，重新开始冷启动流程', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartInside(m, t);
      expect(m.statusNotifier.value, GeofenceStatus.inside);

      m.suspend();
      m.resume();

      // resume 后清除了冷启动样本，重新开始
      m.evaluatePosition(_outside); t.advance(Duration(seconds: 10));
      m.evaluatePosition(_outside); t.advance(Duration(seconds: 10));
      m.evaluatePosition(_outside);
      expect(m.statusNotifier.value, GeofenceStatus.outside);

      m.dispose();
    });
  });

  // ─── 冷启动多数投票 ──────────────────────────────────────

  group('【V5.1】冷启动多数投票', () {
    test('3 个内样本 → 进入 inside', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      m.evaluatePosition(_inside); t.advance(Duration(seconds: 10));
      m.evaluatePosition(_inside); t.advance(Duration(seconds: 10));
      m.evaluatePosition(_inside);
      expect(m.statusNotifier.value, GeofenceStatus.inside);
      m.dispose();
    });

    test('2 内 1 外样本 → 进入 inside（2/3 多数）', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      m.evaluatePosition(_inside); t.advance(Duration(seconds: 10));
      m.evaluatePosition(_inside); t.advance(Duration(seconds: 10));
      m.evaluatePosition(_outside);
      expect(m.statusNotifier.value, GeofenceStatus.inside);
      m.dispose();
    });

    test('1 内 2 外样本 → 留在 outside', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      m.evaluatePosition(_inside); t.advance(Duration(seconds: 10));
      m.evaluatePosition(_outside); t.advance(Duration(seconds: 10));
      m.evaluatePosition(_outside);
      expect(m.statusNotifier.value, GeofenceStatus.outside);
      m.dispose();
    });
  });

  // ─── 冷启动熔断 ─────────────────────────────────────────

  group('【V5.1】冷启动熔断机制', () {
    test('样本间隔 > 30s → 丢弃样本重新开始', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      m.evaluatePosition(_inside);
      t.elapse(Duration(seconds: 31)); // 超过 30s 间隔
      m.evaluatePosition(_inside);   // 重新开始，第 1 个样本
      expect(m.statusNotifier.value, GeofenceStatus.outside); // 不足 3 样本
      m.dispose();
    });

    test('总窗口 > 60s → 熔断丢弃', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      m.evaluatePosition(_inside);
      t.advance(Duration(seconds: 20));
      m.evaluatePosition(_inside);
      t.advance(Duration(seconds: 45)); // t=65s > 60s 总窗口
      m.evaluatePosition(_inside);      // 熔断重置后第 1 个样本
      expect(m.statusNotifier.value, GeofenceStatus.outside);
      m.dispose();
    });

    test('连续 3 次熔断后：强制退出冷启动，保守设为 outside', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      // 3 次循环：第 1 次采样，第 2/3 次触发 2 次熔断
      for (int i = 0; i < 3; i++) {
        m.evaluatePosition(_inside);
        t.elapse(Duration(seconds: 31));
      }
      // 此时 resetCount=2，冷启动仍在
      expect(m.statusNotifier.value, GeofenceStatus.outside);

      // 第 4 次评估触发第 3 次熔断 → 强制退出冷启动，_isColdStart=false
      // force-exit 内联清理样本，不重置 resetCount（=3）
      m.evaluatePosition(_inside);
      expect(m.statusNotifier.value, GeofenceStatus.outside); // force-exit 设 outside

      // 第 5 次评估：_isColdStart=false → 走正常跃迁
      // outside + inside → _startEnterConfirmation() → transitioning
      m.evaluatePosition(_inside);
      expect(m.statusNotifier.value, GeofenceStatus.transitioning);

      m.dispose();
    });
  });

  // ─── 精度过滤 ───────────────────────────────────────────

  group('【V5.1】精度过滤', () {
    test('accuracy = 50m（边界值）→ 参与判断', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      m.evaluatePosition(_pos(50.0, lat: 30.0003, lon: 120.0003));
      t.advance(Duration(seconds: 10));
      m.evaluatePosition(_pos(50.0, lat: 30.0003, lon: 120.0003));
      t.advance(Duration(seconds: 10));
      m.evaluatePosition(_pos(50.0, lat: 30.0003, lon: 120.0003));
      expect(m.statusNotifier.value, GeofenceStatus.inside);
      m.dispose();
    });

    test('accuracy = 51m → 直接丢弃，不影响状态', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      m.evaluatePosition(_pos(51.0, lat: 30.0003, lon: 120.0003));
      expect(m.statusNotifier.value, GeofenceStatus.outside);
      m.dispose();
    });
  });

  // ─── 进入防抖 120s ──────────────────────────────────────

  group('【V5.1】进入防抖 120s', () {
    test('满 120s → 触发 inside', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartOutside(m, t);
      m.evaluatePosition(_inside);
      t.elapse(Duration(seconds: 120));
      expect(m.statusNotifier.value, GeofenceStatus.inside);
      m.dispose();
    });

    test('进入后 119s 内跳出 → 30s 退出防抖后回 outside', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartOutside(m, t);
      m.evaluatePosition(_inside);  // transitioning: 启动 120s 进入确认
      t.advance(Duration(seconds: 119));
      m.evaluatePosition(_outside); // 立即退出（不防抖），状态 = outside
      expect(m.statusNotifier.value, GeofenceStatus.outside);
      // 进入确认 Timer 已被 cancel，30s 后无变化
      t.elapse(Duration(seconds: 30));
      expect(m.statusNotifier.value, GeofenceStatus.outside);
      m.dispose();
    });
  });

  // ─── 退出立即生效 ───────────────────────────────────────

  group('【V5.1】退出立即生效', () {
    test('从 inside 明确离开 → 立即 outside', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartInside(m, t);
      m.evaluatePosition(_outside);
      expect(m.statusNotifier.value, GeofenceStatus.outside);
      m.dispose();
    });
  });

  // ─── 退出防抖 30s ──────────────────────────────────────

  group('【V5.1】退出防抖 30s', () {
    test('30s 内跳回 inside → 取消退出', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartInside(m, t);
      m.evaluatePosition(_outside); // 启动退出防抖
      t.advance(Duration(seconds: 10));
      m.evaluatePosition(_inside);  // 取消退出防抖
      t.elapse(Duration(seconds: 30)); // 计时器到期，无影响
      expect(m.statusNotifier.value, GeofenceStatus.inside);
      m.dispose();
    });
  });

  // ─── 热更新 ─────────────────────────────────────────────

  group('【V5.1】updateConfig() 平滑过渡', () {
    test('transitioning 时热更新：直接确认进入 inside（V5.3.2 行为）', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartOutside(m, t);
      m.evaluatePosition(_inside);
      expect(m.statusNotifier.value, GeofenceStatus.transitioning);

      // [V5.3.2 修复一] 热更新直接确认为 inside，无需等待计时器
      m.updateConfig(GeofenceConfig.highway);
      expect(m.statusNotifier.value, GeofenceStatus.inside);

      // coldStartGeneration 递增，冷启动代际更新
      expect(m.coldStartGeneration.value, 1);

      m.dispose();
    });

    test('outside 时热更新：直接取消计时器', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartOutside(m, t);
      m.updateConfig(GeofenceConfig.highway);
      expect(m.statusNotifier.value, GeofenceStatus.outside);
      m.dispose();
    });
  });

  // ─── 外部回调 ───────────────────────────────────────────

  group('【V5.1】onStatusChanged 回调', () {
    test('状态变化时正确触发外部回调', () {
      final t = FakeTimeProvider();
      final log = <String>[];
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
        onStatusChanged: (id, s) => log.add('$id:${s.name}'),
      );
      _coldStartInside(m, t);
      m.evaluatePosition(_outside);
      expect(log, contains('home:outside'));
      m.dispose();
    });
  });

  // ─── 精度验证 ──────────────────────────────────────────

  group('【V5.1】validateAndSnapPosition()', () {
    test('accuracy <= 50m → 返回精度校验后的 Position', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      final pos = _pos(30.0, lat: _fenceLat, lon: _fenceLon);
      final r = m.validateAndSnapPosition(pos);
      expect(r.latitude, equals(pos.latitude));
      expect(r.accuracy, equals(30.0));
      expect(r.isMocked, isFalse);
      m.dispose();
    });

    test('accuracy > 50m → 返回原始 Position（同一引用）', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      final pos = _pos(60.0);
      final r = m.validateAndSnapPosition(pos);
      expect(identical(r, pos), isTrue);
      m.dispose();
    });
  });

  // ─── dispose 安全 ─────────────────────────────────────

  // ─── 边界测试：pauseSharing 后立即 dispose ─────────────────────────────

  group('【边界】pauseSharing 后立即调用 dispose', () {
    test('suspend 后立即 dispose 不抛异常', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartInside(m, t);
      expect(m.statusNotifier.value, GeofenceStatus.inside);

      // suspend 后立即 dispose
      m.suspend();
      expect(() => m.dispose(), returnsNormally);
    });

    test('suspend → resume → suspend 后连续 dispose 不抛异常', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartInside(m, t);

      m.suspend();
      m.resume();
      m.suspend();

      // 连续 dispose 两次
      expect(() => m.dispose(), returnsNormally);
      expect(() => m.dispose(), returnsNormally);
    });

    test('transitioning 状态下 suspend 后立即 dispose', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      _coldStartOutside(m, t);
      m.evaluatePosition(_inside); // → transitioning
      expect(m.statusNotifier.value, GeofenceStatus.transitioning);

      m.suspend();
      expect(() => m.dispose(), returnsNormally);
    });
  });

  group('【通用】dispose() 幂等', () {
    test('连续两次 dispose 不抛异常', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      m.dispose();
      expect(() => m.dispose(), returnsNormally);
    });

    test('dispose 后 evaluatePosition 不抛异常', () {
      final t = FakeTimeProvider();
      final m = GeofenceStateMachine(
        fenceId: 'home', centerLat: _fenceLat, centerLon: _fenceLon,
        radiusMeters: _fenceRadius, timeProvider: t,
      );
      m.dispose();
      expect(() => m.evaluatePosition(_outside), returnsNormally);
    });
  });
}
