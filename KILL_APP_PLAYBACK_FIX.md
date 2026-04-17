# 杀死App后小文件继续播放问题修复

## 问题描述

播放50MB以下的小文件时，当用户手动从最近任务中杀死App后，音频还会继续播放几十秒才停止。

**注意**：这个问题之前在 commit `30136ca` 和 `87374cd` 中已经修复过，但现在又复现了。

## 历史修复回顾

### 第一次修复 (commit 30136ca)
- **问题**：冷启动小文件无声 + 杀掉app后继续播放
- **方案**：在 `stopPlayback()` 中添加 `BackgroundService.stop()` 调用
- **效果**：部分解决，但仍有问题

### 第二次修复 (commit 87374cd)
- **问题**：手动杀死App后播放继续
- **方案**：
  1. Native层：将 `START_STICKY` 改为 `START_NOT_STICKY`
  2. Native层：添加 `onTaskRemoved()` 回调
  3. Dart层：监听 `AppLifecycleState.detached` 状态
- **效果**：理论上应该解决，但实际上还有遗漏

## 根本原因分析

通过检查代码发现，虽然之前的修复已经做了很多工作，但存在一个**关键遗漏**：

### 问题所在

在 `lib/main.dart` 的 `_stopForegroundServiceAndPlayer()` 方法中：

```dart
Future<void> _stopForegroundServiceAndPlayer() async {
  debugPrint('🛑 应用被销毁，停止前台服务和播放器...');
  
  try {
    // ❌ 只停止了前台服务，但没有停止音频播放器！
    if (_isForegroundServiceRunning) {
      await BackgroundService.stop();
      _isForegroundServiceRunning = false;
      debugPrint('✅ 前台服务已停止');
    }
    
    // 隐藏通知
    _notificationService.hideNotification();
    debugPrint('✅ 通知已隐藏');
  } catch (e) {
    debugPrint('⚠️ 停止服务时出错: $e');
  }
}
```

**问题分析**：
1. ✅ Native层的前台服务确实被停止了（`BackgroundService.stop()`）
2. ✅ WakeLock 被释放
3. ✅ 网络回调被注销
4. ❌ **但是 Dart 层的音频播放器（`just_audio`）仍在运行！**

### 为什么会继续播放？

- `just_audio` 是独立的音频播放器实例，它在 Dart 层运行
- 即使 Native 层的前台服务被停止，Dart 层的播放器仍然持有音频焦点
- Android 系统不会立即杀死 Dart VM，导致音频继续播放直到系统回收资源
- 这个过程可能需要几十秒

## 修复方案

### 核心思路

在应用销毁时，**先停止 Dart 层的音频播放器，再停止 Native 层的前台服务**。

### 修改内容

**文件**: `lib/main.dart`

```dart
/// 停止前台服务和播放器
Future<void> _stopForegroundServiceAndPlayer() async {
  debugPrint('🛑 应用被销毁，停止前台服务和播放器...');
  
  try {
    // ✅ 关键修复：先获取 AppProvider 并停止音频播放
    final context = _navigatorKey.currentContext;
    if (context != null) {
      try {
        final provider = context.read<AppProvider>();
        await provider.stopPlayback();  // ← 新增这一行
        debugPrint('✅ 音频播放器已停止');
      } catch (e) {
        debugPrint('⚠️ 停止音频播放器失败: $e');
      }
    }
    
    // 停止前台服务
    if (_isForegroundServiceRunning) {
      await BackgroundService.stop();
      _isForegroundServiceRunning = false;
      debugPrint('✅ 前台服务已停止');
    }
    
    // 隐藏通知
    _notificationService.hideNotification();
    debugPrint('✅ 通知已隐藏');
  } catch (e) {
    debugPrint('⚠️ 停止服务时出错: $e');
  }
}
```

### 执行顺序

1. **第一步**：调用 `provider.stopPlayback()`
   - 停止 `just_audio` 播放器
   - 释放音频焦点
   - 停止流式服务
   - 停止预下载
   - 调用 `BackgroundService.stop()`（这是第二层保障）

2. **第二步**：再次调用 `BackgroundService.stop()`
   - 确保 Native 层前台服务被停止
   - 释放 WakeLock
   - 注销网络回调

3. **第三步**：隐藏通知
   - 清除通知栏显示

## 技术要点

### 为什么需要双重调用 BackgroundService.stop()？

1. **第一层**：`provider.stopPlayback()` 内部会调用 `BackgroundService.stop()`
   - 这是正常的业务逻辑，确保停止播放时同步停止服务

2. **第二层**：`_stopForegroundServiceAndPlayer()` 再次调用 `BackgroundService.stop()`
   - 这是兜底机制，确保即使第一层调用失败或异常，服务仍会被停止
   - 符合防御性编程原则

### 生命周期管理

| 层级 | 组件 | 销毁时机 | 处理方式 |
|------|------|----------|----------|
| Dart层 | `just_audio` 播放器 | App detached | `provider.stopPlayback()` |
| Dart层 | `AppProvider` | App detached | 自动随 Widget 销毁 |
| Native层 | `BackgroundPlayerService` | App removed from recents | `onTaskRemoved()` + `stopSelf()` |
| Native层 | WakeLock | Service destroyed | `onDestroy()` 中释放 |

## 测试验证

### 测试步骤

1. 安装新版本 APK
2. 连接 SSH 服务器
3. 播放一个小于 50MB 的音频文件
4. 按 Home 键进入后台
5. 从最近任务中滑动移除 App
6. **预期结果**：音频立即停止，不再继续播放

### 日志确认

查看 logcat 输出，应该看到：

```
🛑 应用被销毁，停止前台服务和播放器...
🛑 后台服务已停止
✅ 音频播放器已停止
✅ 前台服务已停止
✅ 通知已隐藏
🛑 应用被用户从最近任务中移除，停止服务和播放
```

## 相关文件

- `lib/main.dart` - 应用生命周期管理
- `lib/providers/app_provider.dart` - 播放控制逻辑
- `android/app/src/main/kotlin/com/audioplayer/ssh_audio_player/BackgroundPlayerService.kt` - Native 层前台服务

## 总结

这次修复的关键在于认识到：**停止前台服务 ≠ 停止音频播放器**。

- 前台服务只是保持 CPU 和网络活跃的机制
- 音频播放器是独立的组件，需要显式停止
- 必须在应用销毁时同时处理这两个层面

这是一个典型的**多层架构生命周期同步问题**，需要在每一层都做好清理工作。
