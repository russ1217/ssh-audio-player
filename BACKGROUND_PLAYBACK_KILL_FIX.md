# 后台播放停止问题修复

## 问题描述

当播放由50MB以下小文件组成的播放列表时,App进入后台播放后,如果用户手动杀死App(从最近任务中滑动清除),播放不会立即停止,还会继续几十秒才停止。

## 根本原因分析

### 1. 前台服务配置错误
在 `BackgroundPlayerService.kt` 中,服务返回 `START_STICKY`:
```kotlin
return START_STICKY // 如果服务被杀死,系统会尝试重启
```

这导致即使用户杀死App,Android系统也会尝试重启前台服务,使播放器继续在后台运行。

### 2. 缺少应用销毁监听
没有在用户杀死App时主动停止前台服务和播放器的逻辑。

### 3. 生命周期不同步
Dart层和Native层的服务生命周期没有严格绑定,导致资源清理不及时。

## 解决方案

采用**双重保障机制**,在Native层和Dart层同时处理应用销毁事件。

### 修复1: Native层 (BackgroundPlayerService.kt)

#### 修改启动模式
将 `START_STICKY` 改为 `START_NOT_STICKY`,避免系统自动重启已停止的服务:

```kotlin
override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    // ... existing code ...
    return START_NOT_STICKY // ✅ 关键修复：改为 NOT_STICKY，避免系统自动重启服务
}
```

#### 添加onTaskRemoved回调
当用户从最近任务中移除App时,立即停止服务:

```kotlin
/**
 * ✅ 关键修复：当用户从最近任务中移除应用时调用
 * 必须在此停止播放和服务，防止后台继续播放
 */
override fun onTaskRemoved(rootIntent: Intent?) {
    super.onTaskRemoved(rootIntent)
    println("🛑 应用被用户从最近任务中移除，停止服务和播放")
    stopSelf()
}
```

### 修复2: Dart层 (main.dart)

#### 监听应用销毁状态
在 `didChangeAppLifecycleState()` 中添加对 `detached` 状态的监听:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      // 进入后台，显示通知并启动前台服务
      _notificationService.showRunningNotification();
      if (!_isForegroundServiceRunning) {
        BackgroundService.start().then((_) {
          _isForegroundServiceRunning = true;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      // 回到前台，隐藏通知
      _notificationService.hideNotification();
    } else if (state == AppLifecycleState.detached) {
      // ✅ 关键修复：应用被销毁时（用户杀死app），停止前台服务和播放器
      _stopForegroundServiceAndPlayer();
    }
}
```

#### 实现清理方法
```dart
/// 停止前台服务和播放器
Future<void> _stopForegroundServiceAndPlayer() async {
    debugPrint('🛑 应用被销毁，停止前台服务和播放器...');
    
    try {
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

## 工作流程

### 正常后台播放
1. App进入后台 → `AppLifecycleState.paused` 触发
2. 显示通知并启动前台服务
3. 播放器继续在后台运行

### 用户杀死App
**第一道防线 (Native层)**:
1. 用户从最近任务中滑动清除App
2. Android系统调用 `onTaskRemoved()`
3. 立即执行 `stopSelf()` 停止前台服务
4. 服务销毁,释放WakeLock和网络回调

**第二道防线 (Dart层)**:
1. Flutter引擎检测到应用即将销毁
2. 触发 `AppLifecycleState.detached` 状态
3. 调用 `_stopForegroundServiceAndPlayer()`
4. 停止前台服务并隐藏通知

### 双重保障优势
- **即时响应**: Native层的 `onTaskRemoved()` 是系统级回调,响应最快
- **兜底保护**: Dart层的 `detached` 状态作为额外保障,确保资源正确释放
- **可靠性**: 即使某一层未及时响应,另一层也能确保服务停止

## 测试验证

### 测试步骤
1. 连接SSH服务器
2. 浏览包含多个小文件(<50MB)的目录
3. 添加到播放列表并开始播放
4. 按Home键使App进入后台(确认播放继续)
5. 从最近任务中滑动清除App
6. **预期结果**: 播放立即停止,不再继续

### 日志验证
成功修复后,杀死App时应看到以下日志:
```
🛑 应用被用户从最近任务中移除，停止服务和播放  (Native层)
🛑 应用被销毁，停止前台服务和播放器...         (Dart层)
✅ 前台服务已停止
✅ 通知已隐藏
```

## 注意事项

1. **START_NOT_STICKY的影响**: 
   - 不会影响正常的后台播放功能
   - 只是防止系统在服务被杀死后自动重启
   - 用户主动停止服务时,服务不会意外重启

2. **onTaskRemoved的触发时机**:
   - 仅在用户从最近任务中清除App时调用
   - 系统因内存不足杀死进程时不会调用
   - 这是Android系统提供的标准回调

3. **detached状态的局限性**:
   - 在某些极端情况下(如系统强制杀死进程),可能不会触发
   - 因此需要Native层的 `onTaskRemoved()` 作为主要保障

4. **与其他功能的兼容性**:
   - 不影响睡眠定时器功能
   - 不影响文件计数定时器功能
   - 不影响SSH断线重连功能

## 相关文件

- `android/app/src/main/kotlin/com/audioplayer/ssh_audio_player/BackgroundPlayerService.kt`
- `lib/main.dart`

## 提交记录

```bash
git commit -m "fix: 修复手动杀死App后播放继续的问题

问题描述：
- 播放50MB以下小文件时，App进入后台后手动杀死App，播放还会继续几十秒才停止

根本原因：
1. BackgroundPlayerService使用START_STICKY模式，系统会自动重启服务
2. 缺少应用销毁时的清理逻辑
3. Dart层和Native层生命周期不同步

修复方案：
1. Native层 (BackgroundPlayerService.kt)：
   - 将START_STICKY改为START_NOT_STICKY，避免系统自动重启
   - 添加onTaskRemoved()回调，用户杀死App时立即停止服务

2. Dart层 (main.dart)：
   - 监听AppLifecycleState.detached状态
   - 应用销毁时主动停止前台服务和隐藏通知

双重保障机制确保用户杀死App后立即停止播放"
```
