# 后台自动恢复播放Bug修复文档

## 问题描述

用户手动暂停播放后，应用在后台有几率自动恢复播放，特别是在以下场景：

1. **其他应用暂停时**：切换到其他音乐应用（如喜马拉雅）并暂停，ssh-audio会自动恢复播放
2. **电话场景**：接听或拨打电话时
3. **系统通知**：系统通知声音播放时

### 典型复现步骤

1. 打开app，播放音乐
2. 手动暂停
3. 打开另外app，比如喜马拉雅，播放
4. 喜马拉雅暂停，并外划退出
5. **问题**：ssh-audio 意外开始重播 ❌

## 根本原因分析

### 1. MediaSession回调逻辑错误（主要原因）

在 `BackgroundPlayerService.kt` 中：

```kotlin
// ❌ 错误做法：统一使用toggle
override fun onPlay() {
    handleMediaControl("toggle_play_pause")
}
override fun onPause() {
    handleMediaControl("toggle_play_pause")
}
```

当其他应用获取音频焦点时，Android系统会调用 `onPause()` 暂停你的应用。但由于使用的是toggle逻辑，如果此时内部状态已经是paused，再次调用toggle就会意外恢复播放。

### 2. 缺少音频焦点管理

- 没有实现Android的AudioFocus机制
- 无法感知和处理音频焦点变化事件
- 当电话、导航提示音等场景发生时，无法正确响应

### 3. **用户意图识别缺失**（核心问题）

- 无法区分"用户主动暂停"和"系统强制暂停"（音频焦点丢失/网络断开）
- SSH断开、网络中断、音频焦点丢失都会触发暂停，但这些情况下应该允许自动恢复
- 只有用户明确点击暂停按钮时，才不应该自动恢复

### 4. **MediaSession onPlay() 回调被系统误触发**（新增问题）

当其他应用（如喜马拉雅）退出时，Android系统的MediaSession管理器可能会错误地调用你的 `onPlay()` 回调，导致应用自动恢复播放。虽然我们在 `handleAudioFocusChange()` 的 `AUDIOFOCUS_GAIN` 分支中没有发送play命令，但系统层面的MediaSession状态管理可能会导致 `onPlay()` 被调用。

## 完整解决方案

### 方案架构

```
用户操作/系统事件
    ↓
Native层 (BackgroundPlayerService)
    ↓ isSystemForced参数
Flutter层 (main.dart)
    ↓
AppProvider
    ↓ _userManuallyPaused标志
自动恢复逻辑检查
```

### 1. 明确区分命令类型

#### Native层修改

``kotlin
// ✅ 正确做法：发送明确的命令，并标识是否是系统强制
override fun onPlay() {
    super.onPlay()
    Log.d(TAG, "▶️ MediaSession: 收到播放命令")
    
    // ✅ 关键修复：检查是否刚刚因为失去音频焦点而暂停
    // 如果是，说明这是系统误触发，不应该自动恢复播放
    if (!hasAudioFocus) {
        Log.w(TAG, "⚠️ 当前没有音频焦点，忽略 onPlay() 回调（可能是系统误触发）")
        return
    }
    
    // ✅ 明确发送 play 命令，不使用 toggle
    handleMediaControl("play", isSystemForced = false)
}

override fun onPause() {
    super.onPause()
    Log.d(TAG, "⏸️ MediaSession: 收到暂停命令")
    // ✅ 明确发送 pause 命令，不使用 toggle
    handleMediaControl("pause", isSystemForced = true) // 由音频焦点管理器调用时传递true
}

private fun handleMediaControl(action: String, isSystemForced: Boolean = false) {
    val intent = Intent("com.audioplayer.ssh_audio_player.MEDIA_CONTROL").apply {
        putExtra("action", action)
        putExtra("isSystemForced", isSystemForced) // ✅ 传递系统强制标志
        setPackage(packageName)
    }
    sendBroadcast(intent)
}
```

#### Flutter层修改

``dart
MediaSessionService.onMediaControl = (action, {bool isSystemForced = false}) {
  switch (action) {
    case 'pause':
      if (isSystemForced) {
        // 系统强制暂停（音频焦点丢失），不设置_userManuallyPaused
        _globalAppProvider!.pauseBySystem();
      } else {
        // 用户主动暂停，设置_userManuallyPaused
        _globalAppProvider!.togglePlayPause();
      }
      break;
  }
};
```

### 2. 实现完整的音频焦点管理

``kotlin
private fun requestAudioFocus(): Boolean {
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

    return audioManager?.requestAudioFocus(audioFocusRequest!!) ==
        AudioManager.AUDIOFOCUS_REQUEST_GRANTED
}

private fun handleAudioFocusChange(focusChange: Int) {
    when (focusChange) {
        AudioManager.AUDIOFOCUS_LOSS -> {
            Log.d(TAG, "🎯 永久失去音频焦点，发送暂停命令（系统强制）")
            hasAudioFocus = false
            handleMediaControl("pause", isSystemForced = true) // ✅ 传递true
        }
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
            Log.d(TAG, "🎯 暂时失去音频焦点，发送暂停命令（系统强制）")
            handleMediaControl("pause", isSystemForced = true) // ✅ 传递true
        }
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
            Log.d(TAG, "🎯 暂时失去音频焦点(可降低音量)，发送暂停命令（系统强制）")
            handleMediaControl("pause", isSystemForced = true) // ✅ 传递true
        }
    }
}
```

### 3. 用户意图识别机制

#### AppProvider新增标志

``dart
class AppProvider extends ChangeNotifier {
  bool _userManuallyPaused = false; // ✅ 标记用户是否主动暂停
  
  /// 用户主动切换播放/暂停
  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayerService.pause();
      _isPlaying = false;
      _userManuallyPaused = true; // ✅ 用户主动暂停
      debugPrint('⏸️ 用户主动暂停，_userManuallyPaused = true');
    } else {
      await _audioPlayerService.play();
      _isPlaying = true;
      _userManuallyPaused = false; // ✅ 用户主动播放，清除标志
      debugPrint('▶️ 用户主动播放，_userManuallyPaused = false');
    }
  }
  
  /// 系统强制暂停（不设置用户主动暂停标志）
  Future<void> pauseBySystem() async {
    if (_isPlaying) {
      await _audioPlayerService.pause();
      _isPlaying = false;
      // ✅ 系统强制暂停，不设置_userManuallyPaused
      debugPrint('⏸️ 系统强制暂停，_userManuallyPaused 保持不变($_userManuallyPaused)');
    }
  }
}
```

#### SSH断开时清除标志

``dart
Future<void> _autoResumePlayback() async {
  _isAutoResuming = true;
  _shouldResumeAfterReconnect = true;
  _playbackPositionBeforeDisconnect = _audioPlayerService.currentPosition;
  // ✅ SSH断开是系统事件，不是用户主动暂停，清除标志
  _userManuallyPaused = false;
  debugPrint('💾 保存播放进度（非用户主动暂停）');
  
  // 停止当前播放...
}
```

#### 自动恢复时检查标志

``dart
Future<void> _handleNetworkReconnected() async {
  // ... SSH重连逻辑 ...
  
  if (_shouldResumeAfterReconnect && _currentPlayingFile != null) {
    // ✅ 关键修复：如果用户主动暂停，不要自动恢复播放
    if (_userManuallyPaused) {
      debugPrint('⚠️ 用户已主动暂停，网络恢复后不自动恢复播放');
      _shouldResumeAfterReconnect = false;
      _userManuallyPaused = false;
    } else {
      debugPrint('🔄 网络恢复，准备恢复播放...');
      await _resumePlaybackAfterReconnect();
    }
  }
}
```

## 修改的文件清单

### 1. Android原生层

- `android/app/src/main/kotlin/com/audioplayer/ssh_audio_player/BackgroundPlayerService.kt`
  - 添加音频焦点相关导入和变量
  - 修改 `handleMediaControl()` 方法，添加 `isSystemForced` 参数
  - 修改 `handleAudioFocusChange()` 方法，传递 `isSystemForced = true`
  - **修改 `onPlay()` 回调**：增加音频焦点检查，防止系统误触发
  - 修改 `onPause()` 回调

### 2. Flutter层

- `lib/services/background_service.dart`
  - 修改 `onMediaControl` 回调签名，添加 `isSystemForced` 参数

- `lib/main.dart`
  - 修改媒体控制监听器，根据 `isSystemForced` 决定调用哪个方法

- `lib/providers/app_provider.dart`
  - 添加 `_userManuallyPaused` 成员变量
  - 修改 `togglePlayPause()` 方法，设置/清除标志
  - 新增 `pauseBySystem()` 方法
  - 修改 `_autoResumePlayback()` 方法，清除标志
  - 修改 `_handleNetworkReconnected()` 方法，检查标志
  - 修改 `_setupSSHHeartbeatListener()` 方法，检查标志
  - 修改 `_resumePlaybackAfterReconnect()` 方法，清除标志

## 测试验证清单

### 场景1：用户主动暂停后切换应用
- [x] 用户点击暂停按钮
- [x] 切换到其他音乐应用（如喜马拉雅）并播放
- [x] 其他应用暂停并退出
- [x] **预期结果**：ssh-audio **不应** 自动恢复播放 ✅

### 场景2：播放时接听电话
- [x] 正在播放音乐
- [x] 接听电话
- [x] **预期结果**：ssh-audio正确暂停
- [x] 挂断电话
- [x] **预期结果**：ssh-audio **不应** 自动恢复（需要用户手动点击播放）✅

### 场景3：SSH断开后重连
- [x] 正在播放音乐
- [x] SSH连接断开（网络问题）
- [x] **预期结果**：ssh-audio暂停，保存播放进度
- [x] SSH重新连接成功
- [x] **预期结果**：如果不是用户主动暂停，应自动恢复播放 ✅

### 场景4：通知栏控制
- [x] 通过通知栏点击暂停按钮
- [x] **预期结果**：视为系统强制暂停，可自动恢复
- [x] SSH断开后重连
- [x] **预期结果**：应自动恢复播放 ✅

### 场景5：蓝牙设备控制
- [x] 通过蓝牙设备点击暂停
- [x] **预期结果**：视为系统强制暂停
- [x] 其他应用暂停后
- [x] **预期结果**：ssh-audio可自动恢复 ✅

## 技术细节

### Android版本兼容性

- `AudioFocusRequest` API 26+ (Android 8.0)
- `FLAG_IMMUTABLE` API 31+ (Android 12)
- 对于旧版本，代码中有降级处理

### 状态流转图

```
初始状态: _userManuallyPaused = false

用户点击暂停 → _userManuallyPaused = true
  ↓
SSH断开 → _userManuallyPaused = false (系统事件)
  ↓
SSH重连 → 检查 _userManuallyPaused
  ├─ true → 不自动恢复
  └─ false → 自动恢复 ✅

音频焦点丢失 → pauseBySystem() → _userManuallyPaused 不变
  ↓
如果是用户主动暂停前丢失 → _userManuallyPaused = true → 不自动恢复
  ↓
如果是播放中丢失 → _userManuallyPaused = false → 可自动恢复
```

## 调试技巧

### 日志关键字

```bash
# 查看用户主动暂停
adb logcat | grep "用户主动暂停"

# 查看系统强制暂停
adb logcat | grep "系统强制暂停"

# 查看自动恢复决策
adb logcat | grep "用户已主动暂停.*不自动恢复"

# 查看音频焦点变化
adb logcat | grep "音频焦点"
```

### 常见问题排查

1. **用户暂停后仍然自动恢复**
   - 检查日志中是否有 `_userManuallyPaused = true`
   - 确认调用的是 `togglePlayPause()` 而不是 `pauseBySystem()`

2. **SSH重连后不自动恢复**
   - 检查 `_userManuallyPaused` 是否为 `false`
   - 确认 `_shouldResumeAfterReconnect` 是否为 `true`

3. **通知栏暂停后无法自动恢复**
   - 确认通知栏点击触发的是系统强制暂停
   - 检查 `isSystemForced` 参数是否正确传递

## 总结

本次修复通过引入**用户意图识别机制**和**音频焦点保护机制**，完美解决了后台自动恢复播放的问题：

1. **明确区分命令来源**：通过 `isSystemForced` 参数区分用户操作和系统事件
2. **精准的状态管理**：通过 `_userManuallyPaused` 标志记录用户意图
3. **智能的恢复策略**：只在非用户主动暂停的情况下自动恢复播放
4. **防止系统误触发**：在 `onPlay()` 回调中增加音频焦点检查，避免其他应用退出时的误触发

这确保了：
- ✅ 用户主动暂停后，不会被其他应用干扰而自动恢复
- ✅ 其他应用（如喜马拉雅）暂停并退出时，不会误触发你的应用恢复播放
- ✅ 系统强制暂停（SSH断开、音频焦点丢失）后，可以正常自动恢复
- ✅ 符合用户预期的行为，提升用户体验
