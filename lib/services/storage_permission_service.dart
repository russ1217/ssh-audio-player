import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

/// 存储权限管理服务
class StoragePermissionService {
  static final StoragePermissionService _instance = StoragePermissionService._internal();
  
  factory StoragePermissionService() => _instance;
  
  StoragePermissionService._internal();

  // ✅ 缓存Android版本，避免重复查询
  int? _cachedAndroidVersion;

  /// 检查并请求存储权限
  Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) {
      debugPrint('⚠️ 非Android平台，跳过存储权限检查');
      return true;
    }

    try {
      // ✅ 获取真实的Android版本
      final androidVersion = await _getAndroidVersion();
      debugPrint('📱 Android版本: $androidVersion (API Level)');
      
      // Android 13+ (API 33+) 使用新的媒体权限
      if (androidVersion >= 33) {
        debugPrint('📱 Android 13+，检查媒体权限...');
        
        // 请求音频和视频权限
        final audioStatus = await Permission.audio.status;
        final videoStatus = await Permission.videos.status;
        
        debugPrint('📊 当前权限状态 - Audio: ${audioStatus.name}, Video: ${videoStatus.name}');
        
        if (audioStatus.isGranted && videoStatus.isGranted) {
          debugPrint('✅ 媒体权限已授予');
          return true;
        }
        
        // 如果之前被永久拒绝，引导用户去设置
        if (audioStatus.isPermanentlyDenied || videoStatus.isPermanentlyDenied) {
          debugPrint('⚠️ 权限被永久拒绝，引导用户去设置');
          await openAppSettingsPage();
          return false;
        }
        
        // 请求权限
        debugPrint('🔐 请求媒体权限...');
        final statuses = await [
          Permission.audio,
          Permission.videos,
        ].request();
        
        debugPrint('📊 请求结果 - Audio: ${statuses[Permission.audio]?.name}, Video: ${statuses[Permission.videos]?.name}');
        
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
        debugPrint('📊 当前存储权限状态: ${status.name}');
        
        if (status.isGranted) {
          debugPrint('✅ 存储权限已授予');
          return true;
        }
        
        // 如果之前被永久拒绝，引导用户去设置
        if (status.isPermanentlyDenied) {
          debugPrint('⚠️ 权限被永久拒绝，引导用户去设置');
          await openAppSettingsPage();
          return false;
        }
        
        // 请求权限
        debugPrint('🔐 请求存储权限...');
        final result = await Permission.storage.request();
        
        debugPrint('📊 请求结果: ${result.name}');
        
        if (result.isGranted) {
          debugPrint('✅ 存储权限已授予');
          return true;
        } else {
          debugPrint('❌ 存储权限被拒绝');
          return false;
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 检查存储权限失败: $e');
      debugPrint('📚 堆栈: $stackTrace');
      return false;
    }
  }

  /// 获取Android版本号
  Future<int> _getAndroidVersion() async {
    if (_cachedAndroidVersion != null) {
      return _cachedAndroidVersion!;
    }
    
    try {
      const platform = MethodChannel('android_version');
      final int version = await platform.invokeMethod('getAndroidVersion');
      _cachedAndroidVersion = version;
      debugPrint('✅ 通过原生方法获取Android版本: $version');
      return version;
    } catch (e) {
      debugPrint('⚠️ 通过MethodChannel获取Android版本失败: $e');
      debugPrint('🔄 尝试从Build.VERSION获取...');
      
      // 备用方案：使用DeviceInfoPlugin或其他方式
      // 这里暂时使用一个合理的默认值
      _cachedAndroidVersion = 34; // 假设为Android 14
      debugPrint('⚠️ 使用默认Android版本: $_cachedAndroidVersion');
      return _cachedAndroidVersion!;
    }
  }

  /// 打开应用设置页面
  Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }
}
