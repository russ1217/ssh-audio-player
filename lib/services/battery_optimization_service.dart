import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// 电池优化检测服务
class BatteryOptimizationService {
  static const _channel = MethodChannel('com.ssh_audio_player/battery_optimization');
  static const _promptShownKey = 'battery_optimization_prompt_shown';

  /// 检查是否已忽略电池优化
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      final bool? result = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      debugPrint('🔍 电池优化检查结果: $result');
      return result ?? true;
    } catch (e, stackTrace) {
      debugPrint('⚠️ 检查电池优化状态失败: $e');
      debugPrint('⚠️ 错误堆栈: $stackTrace');
      return true; // 默认假设已关闭，避免频繁提示
    }
  }

  /// 请求忽略电池优化
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('⚠️ 请求电池优化失败: $e');
      // 降级方案：打开设置页面
      await _openSettings();
    }
  }

  /// 打开应用详情设置
  Future<void> _openSettings() async {
    try {
      const uri = 'package:com.ssh_audio_player';
      final url = Uri.parse('package:$uri');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        // 再降级：打开无线设置
        const settingsUrl = 'app-settings:';
        final settingsUri = Uri.parse(settingsUrl);
        if (await canLaunchUrl(settingsUri)) {
          await launchUrl(settingsUri);
        }
      }
    } catch (e) {
      debugPrint('⚠️ 打开设置失败: $e');
    }
  }

  /// 检查是否已显示过提示
  Future<bool> hasPrompted() async {
    try {
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (e) {
        debugPrint('⚠️ SharedPreferences 初始化失败: $e');
        return false;
      }
      
      if (prefs == null) {
        debugPrint('⚠️ SharedPreferences 为 null');
        return false;
      }
      
      return prefs.getBool(_promptShownKey) ?? false;
    } catch (e) {
      debugPrint('⚠️ 读取提示状态失败: $e');
      debugPrint('⚠️ 错误堆栈: ${StackTrace.current}');
      return false; // 默认返回false，允许继续检查
    }
  }

  /// 标记已显示提示
  Future<void> markAsPrompted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_promptShownKey, true);
    } catch (e) {
      debugPrint('⚠️ 保存提示状态失败: $e');
    }
  }

  /// 重置提示状态（用于测试）
  Future<void> resetPrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_promptShownKey);
    } catch (e) {
      debugPrint('⚠️ 重置提示状态失败: $e');
    }
  }
}
