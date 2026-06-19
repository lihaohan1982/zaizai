import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 输入校验工具 —— 消息长度、XSS 字符过滤
class InputValidator {
  /// 最大消息长度（字节），超过则截断
  static const int maxMessageBytes = 1024;

  /// 允许的快速消息类型（白名单）
  static const Set<String> allowedQuickTypes = {
    'home_arrived',
    'left_home',
    'miss_you',
    'safe_arrived',
    'custom',
  };

  /// 校验并清理消息内容
  ///
  /// 返回清理后的字符串，若内容不合法则返回 null
  static String? validateMessage(String? input) {
    if (input == null || input.trim().isEmpty) return null;

    // 1. 长度校验（UTF-8 字节数）
    final bytes = utf8.encode(input.trim());
    if (bytes.length > maxMessageBytes) {
      debugPrint('[InputValidator] 消息超长: ${bytes.length} > $maxMessageBytes');
      // 截断到最大长度
      return _truncateToBytes(input.trim(), maxMessageBytes);
    }

    // 2. XSS 基础过滤（移除 HTML 标签 + 特殊字符转义）
    var cleaned = _sanitizeXss(input.trim());

    // 3. 空内容检查（过滤后可能为空）
    if (cleaned.isEmpty) return null;

    return cleaned;
  }

  /// 校验快速消息类型（白名单）
  static bool validateQuickType(String? type) {
    if (type == null || type.isEmpty) return false;
    return allowedQuickTypes.contains(type);
  }

  /// XSS 基础过滤
  ///
  /// 移除：<script>, <iframe>, javascript:, on* 事件属性
  /// 转义：< → &lt;, > → &gt;, & → &amp;
  static String _sanitizeXss(String input) {
    var s = input;

    // 移除 HTML 标签（简单正则，非完整 HTML parser）
    s = s.replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<iframe[^>]*>.*?</iframe>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');

    // 移除 javascript: 协议
    s = s.replaceAll(RegExp(r'javascript\s*:', caseSensitive: false), '');

    // 移除 on* 事件属性（onclick, onerror 等）
    s = s.replaceAll(RegExp(r'\s+on[a-zA-Z]+\s*=', caseSensitive: false), ' ');

    // 转义特殊字符（防止剩余 HTML 注入）
    s = s.replaceAll('&', '&amp;');
    s = s.replaceAll('<', '&lt;');
    s = s.replaceAll('>', '&gt;');

    return s.trim();
  }

  /// 按 UTF-8 字节数截断字符串
  static String _truncateToBytes(String input, int maxBytes) {
    final bytes = utf8.encode(input);
    if (bytes.length <= maxBytes) return input;

    // 二分查找最后一个完整字符的边界
    var lo = 0, hi = input.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (utf8.encode(input.substring(0, mid)).length <= maxBytes) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return input.substring(0, lo);
  }
}

/// 客户端限流工具 —— 防抖/节流（Throttle）
///
/// 使用方式：
///   final throttle = Throttle(duration: Duration(seconds: 3));
///   throttle.call(() { /* 高频点击逻辑 */ });
class Throttle {
  final Duration duration;
  DateTime _lastCall = DateTime(1970);

  Throttle({this.duration = const Duration(seconds: 3)});

  /// 节流调用：距上次调用不足 [duration] 则忽略
  void call(VoidCallback action) {
    final now = DateTime.now();
    if (now.difference(_lastCall) >= duration) {
      _lastCall = now;
      action();
    }
  }

  /// 重置计时器（允许下一次立即执行）
  void reset() {
    _lastCall = DateTime(1970);
  }
}

/// 防抖工具（Debounce）
///
/// 使用方式：
///   final debounce = Debounce(duration: Duration(milliseconds: 500));
///   debounce.call(() { /* 搜索输入逻辑 */ });
class Debounce {
  final Duration duration;
  Timer? _timer;

  Debounce({this.duration = const Duration(milliseconds: 500)});

  /// 防抖调用：等待 [duration] 后执行，期间重复调用会重置计时
  void call(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// 立即执行（取消等待中的计时）
  void flush(VoidCallback action) {
    _timer?.cancel();
    action();
  }

  /// 释放资源
  void dispose() {
    _timer?.cancel();
  }
}
