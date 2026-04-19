import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// 存储权限管理服务
class StoragePermissionService {
  static final StoragePermissionService _instance = StoragePermissionService._internal();
  
  factory StoragePermissionService() => _instance;
  
  StoragePermissionService._internal();

  /// 检查并请求存储权限
  Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) {
      debugPrint('⚠️ 非Android平台，跳过存储权限检查');
      return true;
    }

    try {
      // Android 13+ (API 33+) 使用新的媒体权限
      if (await _isAndroid13OrAbove()) {
        debugPrint('📱 Android 13+，检查媒体权限...');
        
        // 请求音频和视频权限
        final audioStatus = await Permission.audio.status;
        final videoStatus = await Permission.videos.status;
        
        if (audioStatus.isGranted && videoStatus.isGranted) {
          debugPrint('✅ 媒体权限已授予');
          return true;
        }
        
        // 请求权限
        debugPrint('🔐 请求媒体权限...');
        final statuses = await [
          Permission.audio,
          Permission.videos,
        ].request();
        
        final granted = statuses[Permission.audio]?.isGranted == true &&
                       statuses[Permission.videos]?.isGranted == true;
        
        if (granted) {
          debugPrint('✅ 媒体权限已授予');
          return true;
        } else {
          debugPrint('❌ 媒体权限被拒绝');
          return false;
        }
      } else {
        // Android 12及以下使用传统存储权限
        debugPrint('📱 Android 12及以下，检查存储权限...');
        
        final status = await Permission.storage.status;
        
        if (status.isGranted) {
          debugPrint('✅ 存储权限已授予');
          return true;
        }
        
        // 请求权限
        debugPrint('🔐 请求存储权限...');
        final result = await Permission.storage.request();
        
        if (result.isGranted) {
          debugPrint('✅ 存储权限已授予');
          return true;
        } else {
          debugPrint('❌ 存储权限被拒绝');
          return false;
        }
      }
    } catch (e) {
      debugPrint('❌ 检查存储权限失败: $e');
      return false;
    }
  }

  /// 检查是否为Android 13+
  Future<bool> _isAndroid13OrAbove() async {
    try {
      final androidInfo = await _getAndroidVersion();
      return androidInfo >= 33;
    } catch (e) {
      debugPrint('⚠️ 获取Android版本失败，假设为旧版本: $e');
      return false;
    }
  }

  /// 获取Android版本号（简化实现）
  Future<int> _getAndroidVersion() async {
    // 这里需要通过MethodChannel调用原生代码获取
    // 为了简化，暂时返回一个默认值
    // 实际项目中应该实现完整的原生桥接
    return 30; // 默认假设为Android 11
  }

  /// 打开应用设置页面
  Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
