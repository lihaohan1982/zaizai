import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 合规隐私弹窗助手
///
/// 展示必须由用户主动选择的隐私政策弹窗。
/// [show] 返回 true 表示用户同意，false 表示拒绝。
///
/// 使用示例：
/// ```dart
/// final agreed = await PrivacyDialogHelper.show(
///   context: context,
///   title: '位置权限申请',
///   content: '为了提供位置相关服务，需要获取您的位置信息...',
///   privacyPolicyUrl: 'https://your-app.com/privacy',
/// );
/// ```
class PrivacyDialogHelper {
  PrivacyDialogHelper._();

  /// 展示合规隐私弹窗
  ///
  /// [context] BuildContext
  /// [title] 弹窗标题
  /// [content] 隐私政策正文（支持多行富文本）
  /// [privacyPolicyUrl] 隐私政策网页链接
  ///
  /// 返回用户选择：[true] 同意，[false] 拒绝。
  /// 若弹窗被系统强制关闭（barrierDismissible=false），返回 false。
  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String content,
    required String privacyPolicyUrl,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 合规要求：强制用户必须做出选择
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(content),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final uri = Uri.parse(privacyPolicyUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: Text(
                    '点击查看《隐私政策》',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('拒绝'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('同意'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}
