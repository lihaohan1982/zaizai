/// 运行时隐私状态（全局动态数据，高频变动）
class PrivacyState {
  final bool isPaused;
  final DateTime? pauseUntil;

  const PrivacyState({
    this.isPaused = false,
    this.pauseUntil,
  });

  Map<String, dynamic> toHiveMap() => {
        'isPaused': isPaused,
        'pauseUntil': pauseUntil?.toIso8601String(),
      };

  factory PrivacyState.fromHiveMap(Map<dynamic, dynamic> map) {
    return PrivacyState(
      isPaused: map['isPaused'] ?? false,
      pauseUntil: map['pauseUntil'] != null
          ? DateTime.parse(map['pauseUntil'])
          : null,
    );
  }
}
