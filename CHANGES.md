# 更新日志

## 2026-04-07 - 电池优化提示功能

### ✨ 新增：首次启动时提示用户关闭电池优化

**需求**: 应用在后台播放时，Android 电池优化可能导致 SSH 连接中断，需要提示用户关闭。

**实现方案**:

#### 1. 检测电池优化状态
- 使用 Platform Channel 调用 Android 原生 API
- 检查应用是否已忽略电池优化
- Android 6.0+ 支持

```kotlin
// MainActivity.kt
private fun isIgnoringBatteryOptimizations(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        powerManager.isIgnoringBatteryOptimizations(packageName)
    } else {
        true // Android 6.0 以下不需要
    }
}
```

#### 2. 首次启动提示
- 仅在首次启动时显示
- 使用 SharedPreferences 记录是否已提示
- 用户点击"知道了"或"去设置"后不再显示

```dart
// 检查逻辑
final hasPrompted = await _batteryService.hasPrompted();
if (hasPrompted) return; // 已提示过，跳过

final isIgnoring = await _batteryService.isIgnoringBatteryOptimizations();
if (isIgnoring) return; // 已关闭电池优化，跳过

// 显示提示对话框
_showBatteryOptimizationDialog();
```

#### 3. 跳转到设置页面
- 点击"去设置"直接跳转到电池优化设置
- 用户可以选择"知道了"跳过
- 自动标记为已提示，不会重复显示

```dart
// 请求忽略电池优化
Future<void> requestIgnoreBatteryOptimizations() async {
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
}
```

#### 4. 友好的对话框设计
```
┌─────────────────────────────────────┐
│ ⚠️ 后台播放优化                     │
├─────────────────────────────────────┤
│ 为了确保应用在后台播放音频时不被    │
│ 中断，建议关闭电池优化。            │
│                                     │
│ 设置步骤：                          │
│ 1. 点击"去设置"按钮                 │
│ 2. 选择"无限制"或"不受限制"         │
│ 3. 返回应用继续播放                 │
│                                     │
│ 提示：不同品牌手机路径略有不同...   │
├─────────────────────────────────────┤
│  [知道了]          [⚙️ 去设置]      │
└─────────────────────────────────────┘
```

**修改文件**:
- `android/app/src/main/AndroidManifest.xml` - 添加电池优化权限
- `android/app/src/main/kotlin/.../MainActivity.kt` - 原生电池优化检测
- `lib/services/battery_optimization_service.dart` - 电池优化服务
- `lib/main.dart` - 首次启动检测和提示
- `pubspec.yaml` - 添加 url_launcher 依赖

**效果**:
- ✅ 首次启动时自动检测电池优化状态
- ✅ 未关闭时显示友好的提示对话框
- ✅ 一键跳转到设置页面
- ✅ 仅提示一次，不会重复打扰用户
- ✅ 用户可以点击"知道了"跳过

---

## 2026-04-07 - SSH 自动恢复播放功能（最终优化版）

### 🔴 新增：SSH 断开后自动恢复播放

**需求**: 播放时 SSH 断开后自动恢复，保持播放不中断。

**完整自动恢复流程**:

```
播放中（大文件使用流式服务）
  ↓
网络断开 → 流式服务 SSH 断开
  ↓
流式服务检测到断开（HTTP 请求失败）
  ↓
调用 onSshDisconnected 回调
  ↓
AppProvider._autoResumePlayback()
  ├─ 保存当前播放进度
  ├─ 停止当前播放（容错处理）
  ├─ await _sshService.reconnect()
  ├─ 等待重连结果
  └─ 设置 _isAutoResuming = true（防抖）
  ↓
SSH 重连成功
  ↓
AppProvider._resumePlaybackAfterReconnect()
  ├─ 重新启动流式服务/使用缓存
  ├─ Seek 到断开前的进度
  ├─ 继续播放
  └─ 重置标志位
  ↓
✅ 播放恢复，用户几乎无感知
```

**关键技术**:

#### 1. 流式服务 SSH 断开检测（即时发现）
```dart
// streaming_audio_service.dart
class StreamingAudioService {
  Function()? onSshDisconnected;
  
  // 停止流式服务时容错处理
  Future<void> stop() async {
    try {
      await _streamingSshClient?.close();
    } catch (e) {
      // SSH 已断开时关闭会抛出异常，忽略
      debugPrint('⚠️ 关闭流式 SSH 连接异常: $e');
    }
  }
  
  // HTTP 请求时检查 SSH
  try {
    await sshClient.run('echo test').timeout(Duration(seconds: 5));
  } catch (e) {
    onSshDisconnected?.call();
    request.response.statusCode = 503;
    return;
  }
}
```

#### 2. 智能心跳间隔（兜底检测）
- 正常状态：60 秒检测一次
- 断开状态：10 秒快速重连
- 重连成功：恢复 60 秒间隔
- 最多重试 5 次

#### 3. 播放状态保存与恢复（后台重试机制）
```dart
// SSH 断开时 - 保存状态并启动后台重试
Future<void> _autoResumePlayback() async {
  _isAutoResuming = true;
  _playbackPositionBeforeDisconnect = _audioPlayerService.currentPosition;
  
  // 停止播放（容错）
  try {
    await _audioPlayerService.stop();
    await _streamingService.stop();
  } catch (e) {}
  
  // 后台重试 SSH 重连（最多5次）
  _retrySshReconnect();
}

// 后台重试 SSH 重连
Future<void> _retrySshReconnect() async {
  const maxAttempts = 5;
  const retryInterval = Duration(seconds: 10);
  
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final success = await _sshService.reconnect()
          .timeout(Duration(seconds: 20));
      
      if (success) {
        await _resumePlaybackAfterReconnect();
        return; // 成功，退出重试
      }
    } catch (e) {
      // 继续重试
    }
    
    if (attempt < maxAttempts) {
      await Future.delayed(retryInterval); // 等待10秒
    }
  }
}
```

**重试策略**:
- 最多重试：5 次
- 重试间隔：10 秒
- 超时时间：20 秒/次
- 总等待时间：最多约 100 秒
```

#### 4. 防抖机制
```dart
bool _isAutoResuming = false;

// 心跳检测中检查
if (_isPlaying && _currentPlayingFile != null && !_isAutoResuming) {
  _autoResumePlayback();
}
```

#### 5. 双重检测机制
- **流式服务检测**: 即时发现（HTTP 请求失败时，<1秒）
- **心跳检测**: 兜底检测（主 SSH 连接状态，10秒内）

**修改文件**:
- `lib/services/ssh_service.dart` - 智能心跳间隔，快速重连，超时处理
- `lib/services/streaming_audio_service.dart` - SSH 断开回调，容错处理
- `lib/providers/app_provider.dart` - 播放状态保存和恢复，防抖机制，同步等待重连
- `lib/services/notification_service.dart` - 容错处理通知隐藏失败

**效果**:
- ✅ 流式服务检测到断开：立即触发恢复（<1秒）
- ✅ 心跳检测作为兜底：10秒内重连
- ✅ 重连成功后自动恢复播放
- ✅ 恢复到断开前的进度（误差 <1秒）
- ✅ 最多重试 5 次，避免无限循环
- ✅ 详细的日志便于排查问题
- ✅ 容错处理，停止播放/通知错误不影响核心功能

**完整日志示例**:
```
⚠️ 流式 SSH 连接已断开，拒绝新的流式请求
🔄 流式服务检测到 SSH 断开，准备恢复播放...
💾 保存播放进度: 0:05:32.123456
🔄 主动触发 SSH 重连...
🔗 SFTP 会话已建立（复用模式）
💓 SSH 心跳检测已启动（正常模式：60秒，最多重试 5 次）
🔄 SSH 重连结果: true
✅ SSH 重连成功，准备恢复播放...
🔄 正在恢复播放: S04E03.mp4
🌐 重新启动流式服务...
⏩ 恢复到进度: 0:05:32.123456
✅ 播放已恢复
```

**错误处理**:
- ✅ 停止流式服务时 SSH 已断开：忽略异常
- ✅ 停止音频播放失败：忽略异常
- ✅ 通知隐藏失败：忽略异常
- ✅ SSH 重连失败：等待心跳重试

---

## 2026-04-07 - SSH 断开处理优化

### 🔴 修复：SSH 断开后无限重试和错误循环

**问题**: SSH 断开后心跳检测无限重试重连，HTTP 流式服务持续收到请求但 SFTP 已关闭，导致大量错误日志。

**解决方案**:

#### 1. SSH 连接超时处理
- 连接超时：15 秒
- 连接测试超时：10 秒
- 重连超时：20 秒
- 避免长时间阻塞

```dart
final socket = await SSHSocket.connect(
  config.host,
  config.port,
  timeout: const Duration(seconds: 15),
).timeout(
  const Duration(seconds: 15),
  onTimeout: () {
    throw TimeoutException('SSH 连接超时');
  },
);
```

#### 2. 限制重连次数
- 最大重试次数：3 次
- 达到上限后停止心跳检测
- 成功重连后重置重试计数

```dart
int _reconnectAttempts = 0;
static const maxReconnectAttempts = 3;

// 心跳检测中
if (_reconnectAttempts < maxReconnectAttempts) {
  _reconnectAttempts++;
  // 尝试重连...
} else {
  debugPrint('⛔ 已达最大重连次数，停止重试');
  stopHeartbeat();
}
```

#### 3. HTTP 流式服务 SSH 状态检查
- 每次收到 HTTP 请求时检查 SSH 连接状态
- SSH 断开后返回 503 错误，不再尝试读取文件
- 避免大量错误日志

```dart
// 检查 SSH 连接是否还有效
try {
  await sshClient.run('echo test').timeout(const Duration(seconds: 5));
} catch (e) {
  debugPrint('⚠️ SSH 连接已断开，拒绝新的流式请求');
  request.response.statusCode = HttpStatus.serviceUnavailable;
  request.response.write('SSH connection lost');
  await request.response.close();
  return;
}
```

#### 4. SSH 断开自动停止播放
- 监听 SSH 连接状态变化
- SSH 断开时如果正在播放则自动停止
- 避免播放器处于错误状态

```dart
_sshService.connectionStatusStream.listen((isConnected) {
  if (!isConnected && _isPlaying) {
    debugPrint('⏹️ SSH 断开，停止播放');
    stopPlayback();
  }
});
```

**修改文件**:
- `lib/services/ssh_service.dart` - 添加超时处理和重连限制
- `lib/services/streaming_audio_service.dart` - SSH 状态检查
- `lib/providers/app_provider.dart` - SSH 断开自动停止播放

**效果**:
- ✅ SSH 断开后不再无限重试
- ✅ 断开后自动停止播放，避免错误循环
- ✅ 错误日志清晰，便于排查问题
- ✅ 用户可以手动重连后继续播放

---

## 2026-04-07 - 后台播放稳定性修复

### 🔴 关键修复：后台播放 2-3 分钟后停止

**问题**: 边下边播状态，进入后台播放后，大约过 2-3 分钟播放后停止或不再有声音，但播放进度条还在继续。

**原因分析**:
1. **iOS 缺少后台音频模式**: `Info.plist` 没有配置 `UIBackgroundModes` 的 `audio` 模式
2. **音频会话未正确配置**: 没有设置音频会话类别，系统不知道应用在播放音频，可能在后台时被暂停

**解决方案**:

#### 1. iOS 后台音频配置
- 在 `ios/Runner/Info.plist` 添加 `UIBackgroundModes` 配置
- 设置 `audio` 模式，允许应用在后台继续播放音频

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

#### 2. 音频会话配置
- 在 `AudioPlayer` 初始化时配置 `AudioContext`
- **Android**: 设置 `stayAwake: true` 保持 CPU 唤醒，防止后台被杀死
- **iOS**: 设置 `category: AVAudioSessionCategory.playback` 告知系统这是后台音频播放

```dart
await _audioPlayer!.setAudioContext(
  AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: true, // 保持 CPU 唤醒
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gain,
    ),
    iOS: const AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: AVAudioSessionOptions.mixWithOthers,
    ),
  ),
);
```

**修改文件**:
- `ios/Runner/Info.plist` - 添加后台音频模式
- `lib/services/audio_player_service_impl.dart` - 添加音频会话配置

**效果**:
- ✅ 应用进入后台后，音频播放不会被系统暂停
- ✅ 播放进度条和音频同步进行
- ✅ 蓝牙音频输出正常
- ✅ 可以长时间后台播放（数小时）

---

## 2026-04-07 - 功能改进

### 1. SSH 连接心跳检测（解决断开连接问题）

**问题**: 边下边播模式中间会停住，可能是因为 SSH 连接断开后没有自动重连。

**解决方案**:
- 在 `SSHService` 中增加心跳检测机制，每 60 秒检查一次 SSH 连接状态
- 如果检测到连接断开，自动尝试重新连接
- 连接状态变化通过 `connectionStatusStream` 广播给所有监听者
- 在 `AppProvider` 中监听连接状态变化，自动更新 UI

**修改文件**:
- `lib/services/ssh_service.dart`: 添加心跳检测逻辑
- `lib/providers/app_provider.dart`: 添加心跳监听器

### 2. 后台预下载后续剧集（优化播放体验）

**问题**: 下载播放一集完成后会停住，不自动播放下一个。

**解决方案**:
- 对于 50MB 以下的文件，在播放当前文件的同时，后台自动预下载播放列表中的后续文件
- 预下载的文件会缓存在本地，播放时优先使用缓存
- 缓存管理：可以通过设置界面清除缓存

**修改文件**:
- `lib/providers/app_provider.dart`: 
  - 添加缓存管理 (`_downloadCache`)
  - 添加预下载逻辑 (`_startPredownloading`, `_predownloadNext`)
  - 修改 `_playMediaAfterDownload` 触发后台预下载
  - 修改 `playMedia` 优先使用缓存文件

### 3. 清除缓存功能

**问题**: 用户需要能够清除已下载的缓存文件以释放磁盘空间。

**解决方案**:
- 在设置界面添加"清除缓存"选项
- 显示当前缓存文件数量
- 点击后弹出确认对话框，确认后清除所有缓存文件

**修改文件**:
- `lib/providers/app_provider.dart`: 添加 `clearDownloadCache()`, `getCacheSize()`, `cacheFileCount`
- `lib/screens/home_screen.dart`: 在设置界面添加清除缓存选项和对话框

### 4. 改进定时关闭功能

**问题**: 用户需要能够查看和取消已设置的定时器。

**解决方案**:
- 在定时设置对话框中显示当前定时状态
- 如果有定时任务在进行，显示"定时已设置"的绿色提示
- "取消定时"按钮在有定时任务时变为可用状态（红色），否则为灰色不可用
- 点击取消后立即停止定时器

**修改文件**:
- `lib/screens/home_screen.dart`: 改进 `TimerPickerSheet` 界面

## 技术细节

### SSH 心跳检测实现

```dart
// 每 60 秒检查一次连接状态
Timer.periodic(Duration(seconds: 60), (_) async {
  final isConnected = await checkConnection();
  if (!isConnected && _currentConfig != null) {
    await reconnect(); // 自动重连
  }
});
```

### 后台预下载实现

```dart
// 播放小文件后触发后台预下载
if (sizeInMB < 50) {
  _startPredownloading();
}

// 递归预下载后续文件
Future<void> _predownloadNext() async {
  if (_predownloadIndex >= _playlist.length) return;
  
  final nextFile = _playlist[_predownloadIndex];
  if (!_downloadCache.containsKey(nextFile.path)) {
    // 下载文件到缓存
    final fileData = await _sshService.readFile(nextFile.path);
    final tempFile = await _createTempFile(fileData, nextFile.name);
    _downloadCache[nextFile.path] = tempFile.path;
    
    // 继续下载下一个
    _predownloadIndex++;
    _predownloadNext();
  }
}
```

## 使用说明

1. **SSH 自动重连**: 应用会自动检测 SSH 连接状态并在断开时自动重连，无需手动操作

2. **后台预下载**: 
   - 播放 50MB 以下文件时自动触发
   - 后续文件会在后台静默下载
   - 播放时优先使用已缓存的文件

3. **清除缓存**:
   - 打开设置界面
   - 点击"清除缓存"
   - 确认后删除所有缓存文件

4. **取消定时**:
   - 打开设置界面
   - 点击"定时关闭"
   - 如果定时已设置，点击红色的"取消定时"按钮
