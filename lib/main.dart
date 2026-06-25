import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/config/env_config.dart';
import 'core/monitoring/sentry_service.dart';
import 'core/providers.dart';
import 'demo/location_demo.dart';

void main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      try { await Hive.initFlutter(); } catch (_) {}
      try { await EnvConfig.load(); } catch (_) {}
      try {
        await SentryService.initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      } catch (_) {}
      debugPrint('[MAIN] runApp about to execute');
      runApp(const ProviderScope(child: DebugApp()));
      debugPrint('[MAIN] runApp executed');
    },
    (e, s) => debugPrint('[MAIN] Uncaught: $e'),
  );
}

/// 逐步调试 App：Step A → B → C → D
/// 每步显示颜色 + 文字，精准定位卡在哪一步
class DebugApp extends ConsumerStatefulWidget {
  const DebugApp({super.key});
  @override
  ConsumerState<DebugApp> createState() => _DebugAppState();
}

class _DebugAppState extends ConsumerState<DebugApp> {
  String _step = 'A'; // A/B/C/D
  Color _color = Colors.red;
  String _log = '';

  void _log(String msg) {
    debugPrint('[DEBUG] $msg');
    setState(() => _log += '${DateTime.now().millisecondsSinceEpoch % 100000} $msg\n');
  }

  @override
  void initState() {
    super.initState();
    _log('initState fired');
    _runSteps();
  }

  Future<void> _runSteps() async {
    // Step A: PrivacyFuseControllerProvider
    _log('Step A: reading privacyFuseControllerProvider...');
    setState(() { _step = 'A'; _color = Colors.red; });
    await Future.delayed(const Duration(milliseconds: 500));

    final privacyAsync = ref.read(privacyFuseControllerProvider);
    privacyAsync.whenData((ctrl) {
      _log('Step A: controller initStatus=${ctrl.initStatus}');
    });
    if (!mounted) return;

    // Step B: read PrivacyFuseController
    setState(() { _step = 'B'; _color = Colors.orange; });
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      final privacyAsync2 = ref.read(privacyFuseControllerProvider);
      final status = privacyAsync2.value?.initStatus;
      _log('Step B: initStatus=$status');
    } catch (e) {
      _log('Step B ERROR: $e');
    }
    if (!mounted) return;

    // Step C: render LocationDemoPage directly
    setState(() { _step = 'C'; _color = Colors.yellow; });
    _log('Step C: about to setState to D...');
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;
    setState(() { _step = 'D'; _color = Colors.green; });
    _log('Step D: done');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: ColoredBox(
          color: _color,
          child: SafeArea(
            child: Column(
              children: [
                // Step indicator
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: Colors.black26,
                  child: Column(
                    children: [
                      Text(
                        'STEP $_step',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _step == 'A' ? 'PrivacyFuseControllerProvider' :
                        _step == 'B' ? 'Reading initStatus' :
                        _step == 'C' ? 'About to show LocationDemoPage' :
                                      'LocationDemoPage rendered!',
                        style: const TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                // Log panel
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Colors.black87,
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: Text(
                        _log.isEmpty ? 'waiting...' : _log,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.lightGreenAccent,
                        ),
                      ),
                    ),
                  ),
                ),
                // Show LocationDemoPage when done
                if (_step == 'D')
                  const Expanded(child: LocationDemoPage()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
