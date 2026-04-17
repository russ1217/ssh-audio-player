# Android通知栏媒体控制功能

## 功能概述

实现了Android系统下拉通知栏中的媒体播放控制界面，用户可以直接在通知栏中控制音乐播放，无需打开应用。

## 功能特性

✅ **通知栏控制按钮**
- ⏮️ 上一曲 (Previous)
- ▶️/⏸️ 播放/暂停 (Play/Pause) - 根据当前状态动态切换
- ⏭️ 下一曲 (Next)
- ⏹️ 停止 (Stop)

✅ **多场景支持**
- 下拉通知栏显示控制界面
- 锁屏界面显示媒体信息和控制按钮
- 蓝牙设备接收播放状态和控制命令
- 系统媒体按钮（耳机线控等）支持

✅ **实时更新**
- 曲目标题实时显示
- 播放/暂停状态同步更新
- 播放进度定期刷新

## 技术实现

### 1. Native层（Kotlin）

#### BackgroundPlayerService.kt

**核心改进：**

```kotlin
// 状态跟踪
private var currentTitle: String = "SSH Player"
private var isCurrentlyPlaying: Boolean = false

// MediaSession回调处理
mediaSession?.setCallback(object : MediaSession.Callback() {
    override fun onPlay() { handleMediaControl("play") }
    override fun onPause() { handleMediaControl("pause") }
    override fun onStop() { handleMediaControl("stop") }
    override fun onSkipToNext() { handleMediaControl("next") }
    override fun onSkipToPrevious() { handleMediaControl("previous") }
})

// 构建带控制按钮的通知
private fun buildMediaStyleNotification(): NotificationCompat.Builder {
    return NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle(currentTitle)
        .setStyle(
            androidx.media.app.NotificationCompat.MediaStyle()
                .setShowActionsInCompactView(0, 1, 2)
                .setMediaSession(mediaSession?.sessionToken)
        )
        .addAction(previousIntent)
        .addAction(playbackAction)
        .addAction(nextIntent)
        .addAction(stopIntent)
}

// 动态更新通知
fun updateNotification(title: String, isPlaying: Boolean) {
    currentTitle = title
    isCurrentlyPlaying = isPlaying
    val notification = buildMediaStyleNotification().build()
    notificationManager.notify(NOTIFICATION_ID, notification)
}
```

**关键方法：**
- `initializeMediaSession()` - 初始化MediaSession并注册回调
- `handleMediaControl(action)` - 通过广播发送控制命令
- `buildMediaStyleNotification()` - 构建带MediaStyle的通知
- `updateNotification()` - 更新通知内容
- `createMediaControlPendingIntent()` - 创建控制动作的PendingIntent

#### MainActivity.kt

**广播接收器：**

```kotlin
private var mediaControlReceiver: BroadcastReceiver? = null

private fun registerMediaControlReceiver() {
    mediaControlReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.getStringExtra("action")
            // 转发到Flutter层
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                val channel = MethodChannel(messenger, "com.audioplayer.ssh_audio_player/media_control")
                channel.invokeMethod("onMediaControl", mapOf("action" to action))
            }
        }
    }
    
    val filter = IntentFilter("com.audioplayer.ssh_audio_player.MEDIA_CONTROL")
    registerReceiver(mediaControlReceiver, filter)
}

override fun onDestroy() {
    super.onDestroy()
    unregisterMediaControlReceiver() // 防止内存泄漏
}
```

### 2. Flutter层（Dart）

#### background_service.dart

**监听器初始化：**

```dart
class MediaSessionService {
  static Function(String action)? onMediaControl;

  static void initializeMediaControlListener() {
    const controlChannel = MethodChannel('com.audioplayer.ssh_audio_player/media_control');
    
    controlChannel.setMethodCallHandler((call) async {
      if (call.method == 'onMediaControl') {
        final action = call.arguments['action'] as String?;
        debugPrint('📱 Flutter 收到媒体控制命令: $action');
        
        if (action != null && onMediaControl != null) {
          onMediaControl!(action);
        }
      }
    });
  }
}
```

#### main.dart

**全局初始化和命令处理：**

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化媒体控制监听器
  MediaSessionService.initializeMediaControlListener();
  
  runApp(const MyApp());
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // 设置媒体控制回调
    MediaSessionService.onMediaControl = _handleMediaControl;
  }

  Future<void> _handleMediaControl(String action) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    
    final provider = context.read<AppProvider>();
    
    switch (action) {
      case 'play':
        if (!provider.isPlaying) await provider.togglePlayPause();
        break;
      case 'pause':
        if (provider.isPlaying) await provider.togglePlayPause();
        break;
      case 'stop':
        await provider.stopPlayback();
        break;
      case 'next':
        await provider.playNextInPlaylist();
        break;
      case 'previous':
        await provider.playPreviousInPlaylist();
        break;
    }
  }
}
```

## 工作流程

```
用户点击通知栏按钮
    ↓
Android系统触发PendingIntent
    ↓
BackgroundPlayerService发送MEDIA_CONTROL广播
    ↓
MainActivity的BroadcastReceiver接收
    ↓
通过MethodChannel转发到Flutter层
    ↓
Flutter调用AppProvider的播放控制方法
    ↓
播放状态变化，更新通知显示
```

## 配置要求

### AndroidManifest.xml

```xml
<!-- 媒体控制权限 -->
<uses-permission android:name="android.permission.MEDIA_CONTENT_CONTROL" />

<!-- 前台服务类型声明 -->
<service
    android:name=".BackgroundPlayerService"
    android:foregroundServiceType="mediaPlayback|dataSync" />
```

## 测试验证

### 手动测试步骤

1. **启动应用并开始播放**
   ```bash
   flutter run
   ```

2. **检查通知栏**
   - 下拉通知栏
   - 应看到带控制按钮的通知
   - 显示当前播放的曲目标题

3. **测试控制按钮**
   - 点击 ▶️ 播放 → 验证开始播放
   - 点击 ⏸️ 暂停 → 验证暂停播放
   - 点击 ⏭️ 下一曲 → 验证切换到下一首
   - 点击 ⏮️ 上一曲 → 验证切换到上一首
   - 点击 ⏹️ 停止 → 验证停止播放并清除通知

4. **锁屏测试**
   - 锁定手机屏幕
   - 点亮屏幕（不解锁）
   - 应看到锁屏媒体控制界面

5. **蓝牙设备测试**
   - 连接蓝牙耳机或音箱
   - 使用蓝牙设备的播放/暂停按钮
   - 验证应用响应控制命令

6. **耳机线控测试**
   - 插入有线耳机
   - 使用耳机上的播放/暂停按钮
   - 验证应用响应

### 预期行为

| 操作 | 预期结果 |
|------|---------|
| 点击通知栏播放按钮 | 开始播放，按钮变为暂停图标 |
| 点击通知栏暂停按钮 | 暂停播放，按钮变为播放图标 |
| 点击下一曲 | 播放列表中下一首歌曲开始播放 |
| 点击上一曲 | 播放列表中上一首歌曲开始播放 |
| 点击停止 | 停止播放，通知可能消失或显示停止状态 |
| 蓝牙设备控制 | 应用响应蓝牙设备的播放控制命令 |
| 锁屏控制 | 锁屏界面显示媒体控制和曲目信息 |

## 注意事项

### 兼容性

- **最低Android版本**: Android 5.0 (API 21)
- **MediaStyle支持**: 使用 `androidx.media.app.NotificationCompat.MediaStyle` 确保向后兼容
- **Android 12+**: PendingIntent 必须指定 `FLAG_IMMUTABLE` 或 `FLAG_MUTABLE`

### 性能优化

1. **通知更新节流**
   - 避免频繁更新通知（每秒最多一次）
   - 只在播放状态或曲目变化时更新

2. **资源管理**
   - Activity销毁时注销广播接收器
   - Service销毁时释放MediaSession

3. **内存泄漏预防**
   - 广播接收器使用弱引用
   - 及时清理不再使用的对象

### 常见问题

**Q: 通知栏没有显示控制按钮？**

A: 检查以下几点：
1. 确认 `androidx.media:media` 依赖已添加
2. 确认 `setStyle()` 使用了 `MediaStyle()`
3. 确认调用了 `setMediaSession()` 关联MediaSession
4. 检查通知渠道是否正确创建

**Q: 点击按钮没有反应？**

A: 检查：
1. BroadcastReceiver 是否正确注册
2. Intent Filter 的 action 是否匹配
3. MethodChannel 名称是否与Flutter层一致
4. 查看logcat日志确认广播是否发送

**Q: 蓝牙设备无法控制？**

A: 确认：
1. MediaSession 已正确初始化并激活
2. 设置了 `FLAG_HANDLES_MEDIA_BUTTONS` 标志
3. MediaSession Callback 已注册
4. 蓝牙设备已正确配对并连接

## 未来扩展

可能的增强方向：

1. **快进/快退**: 添加长按快进/快退功能
2. **播放模式**: 支持单曲循环、随机播放等模式切换
3. **收藏功能**: 在通知栏添加收藏按钮
4. **歌词显示**: 在锁屏界面显示滚动歌词
5. **自定义布局**: 使用RemoteViews自定义通知布局
6. **Widget支持**: 添加桌面小组件控制

## 相关文档

- [Android MediaSession指南](https://developer.android.com/guide/topics/media-apps/working-with-a-media-session)
- [NotificationCompat.MediaStyle](https://developer.android.com/reference/androidx/media/app/NotificationCompat.MediaStyle)
- [Foreground Services](https://developer.android.com/guide/components/foreground-services)

## 提交记录

```
commit 644013d
feat: 实现Android通知栏媒体播放控制功能

- Native层(Kotlin):
  * BackgroundPlayerService: 添加MediaStyle通知，支持播放/暂停/上一曲/下一曲/停止按钮
  * BackgroundPlayerService: 实现MediaSession回调，处理来自通知栏和蓝牙设备的控制命令
  * BackgroundPlayerService: 动态更新通知内容以反映播放状态变化
  * MainActivity: 注册广播接收器，将控制命令转发到Flutter层
  * MainActivity: 在onDestroy中正确注销广播接收器

- Flutter层(Dart):
  * background_service.dart: MediaSessionService添加initializeMediaControlListener方法
  * background_service.dart: 定义onMediaControl回调接口
  * main.dart: 初始化媒体控制监听器
  * main.dart: 实现_handleMediaControl处理播放控制命令

- AndroidManifest:
  * 添加MEDIA_CONTENT_CONTROL权限
```
