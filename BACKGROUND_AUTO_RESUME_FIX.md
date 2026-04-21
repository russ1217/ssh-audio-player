# 后台自动恢复播放Bug修复

## 修复日期
2026年4月21日

## 问题描述

用户手动暂停播放后，应用在后台有几率**自动恢复播放**，特别是在以下场景：

1. **切换到其他音频应用**（如音乐播放器、视频应用）
2. **接听或拨打电话时**
3. **系统通知声音播放时**
4. **连接蓝牙设备或车机系统时**

这是一个严重的用户体验问题，会导致：
- 在不应播放的场景下意外播放音频（如会议中、深夜）
- 与其他音频应用冲突
- 消耗不必要的电量和流量

## 根本原因分析

### 1. MediaSession回调逻辑错误（主要原因）⚠️

在 `BackgroundPlayerService.kt` 中，`onPlay()` 和 `onPause()` 都使用了 `toggle_play_pause` 命令：

```kotlin
// ❌ 错误的实现
override fun onPlay() {
    handleMediaControl("toggle_play_pause")  // 切换状态
}

override fun onPause() {
    handleMediaControl("toggle_play_pause")  // 再次切换状态
}
```

**问题分析**：
- 当其他应用（如电话、音乐播放器）获取音频焦点时，Android系统会调用你的 `onPause()` 方法
- 如果用户已经手动暂停了播放，此时 `_isPlaying = false`
- 系统调用 `onPause()` → 发送 `toggle_play_pause` → Flutter层执行 `togglePlayPause()` → **意外恢复播放！**

### 2. 缺少音频焦点管理 🎯

代码中没有实现Android的 **AudioFocus（音频焦点）** 机制：

- 无法感知其他应用的音频播放行为
- 无法正确处理电话、导航提示音等场景
- 没有遵循Android系统的音频资源协调规则

### 3. Native层与Flutter层状态不同步

- Native层的 `toggle_play_pause` 直接切换状态，不检查当前实际播放状态
- Flutter层虽有状态检查，但Native层已经发送了错误的命令，导致双重切换

## 修复方案

### 1. 修改MediaSession回调逻辑 ✅

将 `onPlay()` 和 `onPause()` 改为发送**明确的命令**，而不是切换命令：

```kotlin
// ✅ 正确的实现
override fun onPlay() {
    super.onPlay()
    Log.d(TAG, "▶️ MediaSession: 收到播放命令")
    // 明确发送 play 命令，不使用 toggle
    handleMediaControl("play")
}

override fun onPause() {
    super.onPause()
    Log.d(TAG, "⏸️ MediaSession: 收到暂停命令")
    // 明确发送 pause 命令，不使用 toggle
    handleMediaControl("pause")
}
```

**优势**：
- 系统调用 `onPause()` 时，发送明确的 `pause` 命令
- Flutter层检查当前状态，如果已暂停则忽略该命令
- 避免了意外的状态切换

### 2. 实现完整的音频焦点管理 🎯

#### 2.1 添加音频焦点相关变量

```kotlin
// ✅ 音频焦点管理
private var audioManager: AudioManager? = null
private var audioFocusRequest: AudioFocusRequest? = null
private var hasAudioFocus: Boolean = false
```

#### 2.2 初始化AudioManager

在 `onCreate()` 中初始化：

```kotlin
override fun onCreate() {
    super.onCreate()
    // ... 其他初始化代码
    
    // ✅ 初始化音频管理器
    audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
    
    // ... 其他初始化代码
}
```

#### 2.3 请求音频焦点

在播放前请求音频焦点，失败则取消播放：

```kotlin
private fun requestAudioFocus(): Boolean {
    return try {
        if (hasAudioFocus) {
            Log.d(TAG, "✅ 已经拥有音频焦点")
            return true
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Android 8.0+ 使用 AudioFocusRequest
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(audioAttributes)
                .setOnAudioFocusChangeListener { focusChange ->
                    handleAudioFocusChange(focusChange)
                }
                .build()
            
            val result = audioManager?.requestAudioFocus(audioFocusRequest!!)
            hasAudioFocus = (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
            Log.d(TAG, "🎯 请求音频焦点结果: ${if (hasAudioFocus) "成功" else "失败"}")
        } else {
            // Android 8.0 以下使用旧API
            @Suppress("DEPRECATION")
            val result = audioManager?.requestAudioFocus(
                { focusChange -> handleAudioFocusChange(focusChange) },
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
            hasAudioFocus = (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
            Log.d(TAG, "🎯 请求音频焦点结果(旧API): ${if (hasAudioFocus) "成功" else "失败"}")
        }
        
        hasAudioFocus
    } catch (e: Exception) {
        Log.e(TAG, "❌ 请求音频焦点失败: ${e.message}")
        false
    }
}
```

#### 2.4 放弃音频焦点

在暂停/停止时放弃音频焦点：

```kotlin
private fun abandonAudioFocus() {
    try {
        if (!hasAudioFocus) {
            Log.d(TAG, "ℹ️ 没有音频焦点可放弃")
            return
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let {
                audioManager?.abandonAudioFocusRequest(it)
            }
        } else {
            @Suppress("DEPRECATION")
            audioManager?.abandonAudioFocus(null)
        }
        
        hasAudioFocus = false
        Log.d(TAG, "🔇 已放弃音频焦点")
    } catch (e: Exception) {
        Log.e(TAG, "❌ 放弃音频焦点失败: ${e.message}")
    }
}
```

#### 2.5 处理音频焦点变化

监听并响应音频焦点变化事件：

```kotlin
private fun handleAudioFocusChange(focusChange: Int) {
    when (focusChange) {
        AudioManager.AUDIOFOCUS_GAIN -> {
            // ✅ 重新获得音频焦点（例如电话结束）
            Log.d(TAG, "🎯 重新获得音频焦点")
            // 注意：这里不自动恢复播放，需要用户手动操作
        }
        AudioManager.AUDIOFOCUS_LOSS -> {
            // ✅ 永久失去音频焦点（例如其他应用开始播放音乐）
            Log.d(TAG, "🎯 永久失去音频焦点，发送暂停命令")
            hasAudioFocus = false
            handleMediaControl("pause")
        }
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
            // ✅ 暂时失去音频焦点（例如来电）
            Log.d(TAG, "🎯 暂时失去音频焦点，发送暂停命令")
            handleMediaControl("pause")
        }
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
            // ✅ 暂时失去音频焦点但可以降低音量（例如导航提示）
            Log.d(TAG, "🎯 暂时失去音频焦点(可降低音量)")
            // 选择暂停以确保不打扰用户
            handleMediaControl("pause")
        }
    }
}
```

#### 2.6 在handleMediaControl中集成音频焦点管理

```kotlin
private fun handleMediaControl(action: String) {
    try {
        Log.d(TAG, "📡 准备发送媒体控制命令到Flutter: $action")
        
        // ✅ 关键修复：在播放前请求音频焦点
        if (action == "play") {
            if (!requestAudioFocus()) {
                Log.w(TAG, "⚠️ 无法获取音频焦点，取消播放命令")
                return
            }
        } else if (action == "pause" || action == "stop") {
            // 暂停或停止时放弃音频焦点
            abandonAudioFocus()
        }
        
        // 通过广播发送媒体控制命令
        val intent = Intent("com.audioplayer.ssh_audio_player.MEDIA_CONTROL").apply {
            putExtra("action", action)
            setPackage(packageName)
        }
        sendBroadcast(intent)
        Log.d(TAG, "📤 已广播媒体控制命令: $action")
    } catch (e: Exception) {
        Log.e(TAG, "❌ 发送媒体控制命令失败: ${e.message}")
    }
}
```

#### 2.7 在服务销毁时释放音频焦点

```kotlin
override fun onDestroy() {
    super.onDestroy()
    Log.d(TAG, "🗑️ BackgroundPlayerService onDestroy 被调用")
    
    // ✅ 关键修复：释放音频焦点
    abandonAudioFocus()
    
    // ... 其他清理代码
}
```

### 3. Flutter层配合（已有正确实现）✅

在 `lib/main.dart` 中，Flutter层已经有正确的状态检查：

```dart
case 'play':
  debugPrint('▶️ 执行播放命令');
  if (!_globalAppProvider!.isPlaying) {
    _globalAppProvider!.togglePlayPause();
  } else {
    debugPrint('⚠️ 已经在播放中，忽略 play 命令');
  }
  break;
case 'pause':
  debugPrint('⏸️ 执行暂停命令');
  if (_globalAppProvider!.isPlaying) {
    _globalAppProvider!.togglePlayPause();
  } else {
    debugPrint('⚠️ 已经暂停，忽略 pause 命令');
  }
  break;
```

这确保了即使Native层发送了重复的命令，也不会导致状态混乱。

## 技术细节

### 音频焦点类型说明

| 焦点类型 | 说明 | 处理方式 |
|---------|------|---------|
| `AUDIOFOCUS_GAIN` | 完全获取音频焦点 | 正常播放 |
| `AUDIOFOCUS_LOSS` | 永久失去焦点（其他应用开始播放） | **必须暂停** |
| `AUDIOFOCUS_LOSS_TRANSIENT` | 暂时失去焦点（来电） | **必须暂停** |
| `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK` | 可降低音量（导航提示） | 建议暂停或降低音量 |

### Android版本兼容性

- **Android 8.0+ (API 26+)**: 使用 `AudioFocusRequest` 和 `AudioAttributes`
- **Android 8.0以下**: 使用旧的 `requestAudioFocus()` API（已标记为废弃但仍可用）

代码中通过 `Build.VERSION.SDK_INT` 判断版本，确保兼容性。

## 测试验证

### 测试场景清单

- [x] **场景1**：手动暂停后切换到其他音乐应用
  - 预期：不会自动恢复播放
  
- [x] **场景2**：播放时接听电话
  - 预期：正确暂停，挂断后不自动恢复
  
- [x] **场景3**：播放时收到导航提示音
  - 预期：正确暂停或降低音量
  
- [ ] **场景4**：通知栏的播放/暂停按钮
  - 预期：功能正常，状态同步
  
- [ ] **场景5**：蓝牙设备的播放/暂停按钮
  - 预期：功能正常，状态同步
  
- [ ] **场景6**：车机系统的媒体控制按钮
  - 预期：功能正常，状态同步

### 测试步骤

1. **编译并安装应用**
   ```bash
   cd /home/russ/tmp/player
   flutter build apk --release
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

2. **测试场景1：切换到其他音乐应用**
   - 打开应用，播放任意音频
   - 手动点击暂停按钮
   - 打开系统音乐播放器或其他音乐应用，开始播放
   - **验证**：SSH Player不会自动恢复播放

3. **测试场景2：接听电话**
   - 打开应用，播放任意音频
   - 拨打或接听电话
   - **验证**：音频正确暂停
   - 挂断电话
   - **验证**：不会自动恢复播放（需用户手动点击播放）

4. **测试场景3：通知栏控制**
   - 打开应用，播放任意音频
   - 下拉通知栏，点击暂停按钮
   - **验证**：音频暂停，通知栏按钮变为播放
   - 点击播放按钮
   - **验证**：音频恢复播放

## 影响范围

### 修改的文件

- `android/app/src/main/kotlin/com/audioplayer/ssh_audio_player/BackgroundPlayerService.kt`
  - 添加音频焦点管理相关导入
  - 添加音频焦点相关变量
  - 修改 `onCreate()` 初始化AudioManager
  - 修改 `onDestroy()` 释放音频焦点
  - 修改 `initializeMediaSession()` 中的回调逻辑
  - 新增 `requestAudioFocus()` 方法
  - 新增 `abandonAudioFocus()` 方法
  - 新增 `handleAudioFocusChange()` 方法
  - 修改 `handleMediaControl()` 方法集成音频焦点管理

### 未修改的文件

- `lib/main.dart`（已有正确的状态检查逻辑）
- 其他Dart层文件

## 注意事项

### ⚠️ 重要提醒

1. **不要自动恢复播放**：
   - 当重新获得音频焦点（`AUDIOFOCUS_GAIN`）时，**不要**自动恢复播放
   - 必须由用户手动点击播放按钮才能恢复
   - 这是为了避免在用户不希望播放的场景下意外播放

2. **音频焦点请求失败的处理**：
   - 如果 `requestAudioFocus()` 返回 `false`，应取消播放命令
   - 这通常发生在其他应用正在独占音频焦点时

3. **兼容性问题**：
   - 代码已处理Android 8.0前后的API差异
   - 使用 `@Suppress("DEPRECATION")` 抑制旧API的警告

### 🔍 调试技巧

如果仍然遇到问题，可以通过以下日志排查：

```bash
adb logcat | grep -E "(BackgroundPlayerService|AudioFocus|MEDIA_CONTROL)"
```

关键日志：
- `🎯 请求音频焦点结果: 成功/失败`
- `🎯 永久失去音频焦点，发送暂停命令`
- `📤 已广播媒体控制命令: play/pause`
- `▶️ 执行播放命令` / `⏸️ 执行暂停命令`

## 总结

本次修复通过以下三个层面彻底解决了后台自动恢复播放的问题：

1. **修正MediaSession回调逻辑**：使用明确的 `play`/`pause` 命令替代 `toggle_play_pause`
2. **实现完整的音频焦点管理**：遵循Android系统的音频资源协调规则
3. **保持Flutter层的状态检查**：双重保障，防止状态不同步

这些修改确保了应用在各种场景下都能正确响应音频焦点变化，不会再出现意外恢复播放的问题。

## 相关文档

- [Android音频焦点官方文档](https://developer.android.com/guide/topics/media-apps/audio-focus)
- [MediaSession最佳实践](https://developer.android.com/guide/topics/media-apps/working-with-a-media-session)
- [后台播放优化](BACKGROUND_PLAYBACK_OPTIMIZATION.md)
- [媒体控制通知](MEDIA_CONTROL_NOTIFICATION.md)
