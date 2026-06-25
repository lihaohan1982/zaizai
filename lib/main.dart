import 'package:flutter/material.dart';

/// 极简测试版本 - 用于诊断小米14 Ultra 白屏问题
/// 这个版本不包含任何初始化代码、插件、或状态管理
/// 如果这部手机能看到红色屏幕，说明 Flutter 引擎正常工作
void main() {
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.red,
        child: Center(
          child: Text(
            'Minimal App\nWorks!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );
}
