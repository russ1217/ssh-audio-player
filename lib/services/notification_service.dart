import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知栏服务：应用进入后台 时显示通知，点击可恢复
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 初始化通知服务
  Future<void> init() async {
    if (_initialized) return;

    try {
      // Android 初始化设置
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS 初始化设置
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(initSettings);

      // 注意：不在这里主动请求通知权限
      // Android 会在首次显示通知时自动请求权限
      // 避免在 Context 未完全初始化时调用导致崩溃

      _initialized = true;
      debugPrint('✅ 通知服务初始化成功');
    } catch (e) {
      // 初始化失败不影响应用运行
      debugPrint('⚠️ 通知服务初始化失败（不影响核心功能）: $e');
      _initialized = false;
    }
  }

  /// 显示"应用正在运行"通知
  Future<void> showRunningNotification({String? currentFile}) async {
    if (!_initialized) return;

    try {
      const androidDetails = AndroidNotificationDetails(
        'ssh_player_for_russ_background',
        'SSH Player for Russ - 后台运行',
        channelDescription: '应用进入后台时显示的通知，点击可恢复',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: true,
        ongoing: true, // 持续通知，不被滑走
        autoCancel: false,
        onlyAlertOnce: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final title = 'SSH Player for Russ';
      final body = currentFile != null ? '正在播放: $currentFile' : '应用正在后台运行';

      await _notifications.show(
        0, // 固定 ID
        title,
        body,
        details,
        payload: 'restore_app',
      );

      debugPrint('🔔 显示后台通知: $body');
    } catch (e) {
      debugPrint('❌ 显示通知失败: $e');
    }
  }

  /// 隐藏通知
  Future<void> hideNotification() async {
    if (!_initialized) return;

    try {
      await _notifications.cancel(0);
      debugPrint('🔕 隐藏后台通知');
    } catch (e) {
      // 忽略隐藏失败的错误（通常是缓存问题，不影响功能）
      debugPrint('⚠️ 隐藏通知失败（可忽略）: $e');
    }
  }
}
