library;

/// 消息话术模板 — 温暖友好，符合伴伴产品调性
///
/// 格式：contentKey → 显示文本
/// 使用场景由 source 字段区分（geofence / manual / privacy）

class MessageTemplates {
  MessageTemplates._();

  // -------------------------------------------------------------------------
  // 手动快捷消息（5条）
  // -------------------------------------------------------------------------
  static const manualTemplates = [
    ('arrived', '到了吗？🤔'),
    ('call_me', '回个电话？📞'),
    ('battery', '记得充电哦🔋'),
    ('goodnight', '晚安 ❤️'),
    ('miss_you', '想你了'),
  ];

  // -------------------------------------------------------------------------
  // 围栏到达消息（4条）
  // -------------------------------------------------------------------------
  static const homeArrivedTemplates = [
    'Ta已经到家了 ❤️',
    'Ta安全到家啦 🏠',
    'Ta 已经平安到家 ❤️',
    'Ta 到家啦～',
  ];

  static const officeArrivedTemplates = [
    'Ta已经到公司啦 💼',
    'Ta 到公司了，早安！☀️',
    'Ta 安全抵达工作地点 💼',
    'Ta 到啦～',
  ];

  // -------------------------------------------------------------------------
  // 围栏离开消息（4条）
  // -------------------------------------------------------------------------
  static const leftHomeTemplates = [
    'Ta刚离开家 🏠',
    'Ta出门啦～',
    'Ta 离开家了，注意安全 ❤️',
    'Ta 出发啦 🏃',
  ];

  static const leftOfficeTemplates = [
    'Ta下班离开公司啦 💼',
    'Ta 离开公司了 🌙',
    'Ta下班啦～',
    'Ta 离开工作地点 💼',
  ];

  // -------------------------------------------------------------------------
  // 隐私状态消息
  // -------------------------------------------------------------------------
  static const sharingPaused = 'Ta 已暂停位置共享 🙈';
  static const sharingResumed = 'Ta 恢复了位置共享 📍';

  // -------------------------------------------------------------------------
  // 拍一拍
  // -------------------------------------------------------------------------
  static const pokeMessage = '👋 拍了拍你';

  // -------------------------------------------------------------------------
  // 根据 contentKey 解析显示文本
  // -------------------------------------------------------------------------
  static String resolveText(String contentKey, {String? customText, String? fenceId}) {
    // 优先使用自定义文本
    if (customText != null && customText.isNotEmpty) return customText;

    switch (contentKey) {
      // 手动快捷
      case 'arrived': return manualTemplates[0].$2;
      case 'call_me': return manualTemplates[1].$2;
      case 'battery': return manualTemplates[2].$2;
      case 'goodnight': return manualTemplates[3].$2;
      case 'miss_you': return manualTemplates[4].$2;
      case 'manual_quick': return customText ?? manualTemplates[0].$2;

      // 围栏到达
      case 'home_arrived':
        return homeArrivedTemplates[fenceId.hashCode.abs() % homeArrivedTemplates.length];
      case 'office_arrived':
        return officeArrivedTemplates[fenceId.hashCode.abs() % officeArrivedTemplates.length];

      // 围栏离开
      case 'left_home':
        return leftHomeTemplates[fenceId.hashCode.abs() % leftHomeTemplates.length];
      case 'left_office':
        return leftOfficeTemplates[fenceId.hashCode.abs() % leftOfficeTemplates.length];

      // 隐私
      case 'sharing_paused': return sharingPaused;
      case 'sharing_resumed': return sharingResumed;

      // 拍一拍
      case 'poke': return pokeMessage;

      default: return contentKey;
    }
  }

  /// 判断是否为自动触发的围栏消息（带地图图标气泡）
  static bool isGeofenceMessage(String contentKey) {
    return ['home_arrived', 'office_arrived', 'left_home', 'left_office']
        .contains(contentKey);
  }

  /// 判断是否为系统消息（居中展示）
  static bool isSystemMessage(String contentKey) {
    return ['sharing_paused', 'sharing_resumed'].contains(contentKey);
  }
}
