# 音频焦点丢失自动恢复播放Bug修复

## 问题描述

**Bug场景:**
1. 用户在app中播放音乐
2. 用户主动暂停播放
3. App进入后台
4. 用户打开其他需要用到声卡的app(如音乐播放器、视频app等),该app开始播放
5. 用户退出其他app
6. **Bug发生**: 本app自动恢复播放 ❌

**期望行为:**
- 用户已经主动暂停了,不应该在其他应用退出后自动恢复播放
- 只有用户手动点击播放按钮时,才应该恢复播放

## 根本原因分析

### 1. 音频焦点机制
Android系统使用音频焦点(Audio Focus)来管理多个应用的音频播放:
- 当其他应用开始播放时,会请求音频焦点
- 当前应用会收到`AUDIOFOCUS_LOSS`事件,应该暂停播放
- 当其他应用停止时,会释放音频焦点
- 当前应用会收到`AUDIOFOCUS_GAIN`事件,表示重新获得音频焦点

### 2. just_audio的自动恢复行为
`just_audio`插件配合`audio_session`包使用时,默认配置可能会在重新获得音频焦点时自动恢复播放。

### 3. 网络状态变化触发恢复
当其他应用退出时,可能会触发网络状态变化检测,导致`_handleNetworkReconnected`被调用。如果`_shouldResumeAfterReconnect`为true(之前SSH断开过),会尝试恢复播放。

### 4. 标志位检查不完整
之前的代码只检查了`_userManuallyPaused`(用户主动暂停),但没有区分:
- **用户主动暂停**: 用户点击暂停按钮
- **系统强制暂停**: 音频焦点丢失、来电等系统事件导致的暂停

这两种情况都应该阻止自动恢复播放,但需要不同的处理逻辑。

## 解决方案

### 核心思路
添加`_audioFocusLost`标志来专门标记"因音频焦点丢失而暂停"的状态,并在所有可能自动恢复播放的地方检查这个标志。

### 修改内容

#### 1. AppProvider中添加_audioFocusLost标志

**文件:** `lib/providers/app_provider.dart`

```dart
// 自动恢复播放相关
bool _shouldResumeAfterReconnect = false;
Duration? _playbackPositionBeforeDisconnect;
bool _isAutoResuming = false; // 防抖标志
bool _userManuallyPaused = false; // ✅ 标记用户是否主动暂停
bool _isWaitingForSSHReconnect = false; // ✅ 标记是否正在等待SSH重连
bool _audioFocusLost = false; // ✅ 新增：标记是否因音频焦点丢失而暂停
```

添加公开getter:
```dart
bool get audioFocusLost => _audioFocusLost; // ✅ 新增：音频焦点丢失状态
```

#### 2. pauseBySystem方法中设置标志

**文件:** `lib/providers/app_provider.dart`

```dart
/// ✅ 系统强制暂停（不设置用户主动暂停标志）
/// 用于音频焦点丢失、电话等场景
Future<void> pauseBySystem() async {
  try {
    if (_isPlaying) {
      await _audioPlayerService.pause();
      _isPlaying = false;
      // ✅ 关键修复：系统强制暂停，标记音频焦点丢失
      _audioFocusLost = true;
      debugPrint('⏸️ 系统强制暂停，_isPlaying = false, _audioFocusLost = true');
      
      // ✅ 更新 MediaSession 播放状态为暂停
      _updateMediaSessionPlaybackState(isPlaying: false);
    }
  } catch (e) {
    debugPrint('❌ 系统强制暂停失败: $e');
  }
}
```

#### 3. togglePlayPause方法中清除标志

**文件:** `lib/providers/app_provider.dart`

```dart
_isPlaying = true;
// ✅ 用户主动播放，清除标志
_userManuallyPaused = false;
_audioFocusLost = false; // ✅ 用户主动播放，清除音频焦点丢失标志
_isWaitingForSSHReconnect = false; // ✅ 用户主动播放，清除等待重连标志
debugPrint('▶️ 用户主动播放，_isPlaying = true, _userManuallyPaused = false, _audioFocusLost = false, _isWaitingForSSHReconnect = false');
```

#### 4. main.dart中的媒体控制监听器添加检查

**文件:** `lib/main.dart`

```dart
case 'play':
  // ✅ 关键修复：play 命令应该明确执行播放操作
  debugPrint('▶️ 执行播放命令');
  debugPrint('🔍 当前状态: isPlaying=${_globalAppProvider!.isPlaying}, hasCurrentFile=${_globalAppProvider!.currentPlayingFile != null}');
  
  // ✅ 严格检查1：只有在未播放且有文件时才考虑播放
  if (!_globalAppProvider!.isPlaying && _globalAppProvider!.currentPlayingFile != null) {
    // ✅ 关键修复：如果因音频焦点丢失而暂停，不要自动恢复播放
    // 必须由用户主动点击播放按钮才能恢复
    if (_globalAppProvider!.audioFocusLost) {
      debugPrint('⚠️ 音频焦点已丢失，忽略自动播放命令（需用户手动恢复）');
      return;
    }
    
    // ... 其他检查逻辑 ...
    
    debugPrint('✅ 满足播放条件，执行播放');
    _globalAppProvider!.togglePlayPause();
  } else if (_globalAppProvider!.isPlaying) {
    debugPrint('⚠️ 已经在播放中，忽略 play 命令');
  } else {
    debugPrint('⚠️ 没有正在播放的文件，忽略 play 命令（可能是误触发）');
  }
  break;
```

#### 5. _resumePlaybackAfterReconnect方法添加检查

**文件:** `lib/providers/app_provider.dart`

```dart
/// SSH 重连成功后恢复播放
Future<void> _resumePlaybackAfterReconnect() async {
  // ✅ 关键修复：如果是本地模式，不进行任何恢复操作
  if (_isLocalMode) {
    debugPrint('ℹ️ 本地模式，跳过SSH恢复播放逻辑');
    _shouldResumeAfterReconnect = false;
    _isAutoResuming = false;
    return;
  }
  
  // ✅ 关键修复：如果音频焦点已丢失，不要自动恢复播放
  if (_audioFocusLost) {
    debugPrint('⚠️ 音频焦点已丢失，SSH重连后不自动恢复播放');
    _shouldResumeAfterReconnect = false;
    _isAutoResuming = false;
    return;
  }
  
  if (_currentPlayingFile == null) {
    _shouldResumeAfterReconnect = false;
    _isAutoResuming = false;
    return;
  }

  // ... 恢复播放逻辑 ...
}
```

#### 6. _handleNetworkReconnected方法添加检查

**文件:** `lib/providers/app_provider.dart`

```dart
// 如果需要恢复播放
if (_shouldResumeAfterReconnect && _currentPlayingFile != null) {
  // ✅ 关键修复：如果用户主动暂停或音频焦点丢失，不要自动恢复播放
  if (_userManuallyPaused || _audioFocusLost) {
    debugPrint('⚠️ 用户已主动暂停或音频焦点丢失，网络恢复后不自动恢复播放');
    _shouldResumeAfterReconnect = false;
    _userManuallyPaused = false;
    _audioFocusLost = false; // ✅ 清除音频焦点丢失标志
  } else {
    debugPrint('🔄 网络恢复，准备恢复播放...');
    await Future.delayed(const Duration(milliseconds: 500));
    await _resumePlaybackAfterReconnect();
  }
}
```

## 测试场景

### ✅ 场景1: 音频焦点丢失后不应自动恢复
1. 播放音乐
2. 用户主动暂停
3. App进入后台
4. 打开其他音乐app并播放
5. 退出其他音乐app
6. **预期结果**: 本app保持暂停状态,不会自动恢复播放 ✅

### ✅ 场景2: SSH断开后用户暂停,重连成功不应恢复
1. 播放SSH流式音乐
2. SSH断开(模拟网络中断)
3. 用户点击暂停按钮
4. SSH重连成功
5. **预期结果**: 保持暂停状态,不会自动恢复播放 ✅

### ✅ 场景3: 网络断开后用户暂停,恢复后不应恢复
1. 播放音乐
2. 网络断开
3. 用户点击暂停按钮
4. 网络恢复
5. **预期结果**: 保持暂停状态,不会自动恢复播放 ✅

### ✅ 场景4: 用户通过通知栏/蓝牙设备点击播放应正常播放
1. 用户暂停(无论是主动暂停还是音频焦点丢失)
2. 用户通过通知栏的播放按钮或蓝牙设备的播放键点击播放
3. **预期结果**: 正常恢复播放,并清除_audioFocusLost标志 ✅

## 技术要点

### 标志位状态管理

| 场景 | _userManuallyPaused | _audioFocusLost | 是否自动恢复 |
|------|---------------------|-----------------|-------------|
| 用户主动暂停 | true | false | ❌ 否 |
| 音频焦点丢失 | false | true | ❌ 否 |
| SSH断开触发自动暂停 | false | false | ✅ 是(重连后) |
| 用户主动播放 | false | false | - |

### 标志位清除时机

- **用户主动播放时**: 同时清除`_userManuallyPaused`和`_audioFocusLost`
- **网络恢复检测到暂停时**: 同时清除两个标志(避免残留状态)
- **SSH重连成功后**: 在`_resumePlaybackAfterReconnect`中清除

## 总结

通过添加`_audioFocusLost`标志,我们能够准确区分"用户主动暂停"和"系统强制暂停",并在所有可能自动恢复播放的地方进行检查,确保只有在用户明确意图恢复播放时才执行播放操作。

这个修复方案:
- ✅ 解决了音频焦点丢失后自动恢复播放的bug
- ✅ 保持了SSH断线重连的自动恢复功能(仅在非暂停状态下)
- ✅ 支持用户通过通知栏/蓝牙设备手动恢复播放
- ✅ 代码逻辑清晰,易于维护和扩展
