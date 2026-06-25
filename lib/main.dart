import 'package:flutter/material.dart';

/// 终极诊断版本 - 排除所有布局约束问题
/// 这个版本直接在 runApp() 里放一个全屏红色 ColoredBox
/// 如果这部手机能看到红色，说明 Flutter 引擎正常工作
void main() {
  // 最激进的测试：直接运行一个红色容器
  runApp(
    const ColoredBox(
      color: Colors.red,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Text(
            'FLUTTER ENGINE\nWORKS!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );
}
