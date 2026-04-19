# 本地文件播放功能

## 功能概述

在原有SSH远程播放功能的基础上，新增了**本地文件播放**功能。用户可以在"本地文件"和"SSH远程文件"两种模式之间自由切换，享受一致的播放体验。

## 核心特性

### ✅ 双模式支持

| 特性 | 本地文件模式 | SSH远程模式 |
|------|------------|-----------|
| **文件来源** | Android设备本地存储 | 远程SSH服务器 |
| **播放方式** | 直接播放本地文件 | HTTP流式边下边播 |
| **网络连接** | 无需网络 | 需要SSH连接 |
| **权限要求** | 存储权限 | 无特殊权限 |
| **适用场景** | 本地音乐库、下载的文件 | 服务器上的音频资源 |

### ✅ 一致的用户体验

无论使用哪种模式，以下功能完全一致：
- 🎵 播放控制（播放/暂停/停止/快进/快退）
- 📋 播放列表管理
- ⏱️ 定时关闭功能
- 📻 蓝牙设备曲目显示
- 🔔 后台播放和通知栏控制
- 💾 播放位置记忆

## 使用方法

### 1. 切换到本地文件模式

1. 打开应用，进入"文件"标签页
2. 点击AppBar右上角的**手机图标** 📱（绿色）
3. 首次切换时会请求存储权限，请点击"允许"
4. 成功切换后，图标变为**云图标** ☁️（蓝色），表示当前为本地模式

### 2. 浏览本地文件

- 默认进入 `/storage/emulated/0` 目录（内部存储根目录）
- 点击文件夹进入子目录
- 点击返回按钮（←）返回上级目录
- 点击刷新按钮重新加载当前目录

### 3. 播放本地文件

- 点击任意音频/视频文件即可开始播放
- 支持所有原有格式：MP3, WAV, FLAC, AAC, OGG, M4A, MP4, MKV等
- 播放控制与SSH模式完全相同

### 4. 添加目录到播放列表

- 点击AppBar的"添加到播放列表"按钮（📋图标）
- 当前目录下所有媒体文件将被添加到播放列表

### 5. 切换回SSH模式

- 点击AppBar右上角的**云图标** ☁️（蓝色）
- 如果SSH已配置并连接，将自动加载远程文件
- 如果未连接，会提示先配置SSH

## 技术实现

### 1. 架构设计

```
AppProvider
├── _isLocalMode (bool)          // 模式标志
├── switchToLocalMode()          // 切换到本地模式
├── switchToSSHMode()            // 切换到SSH模式
├── _loadCurrentDirectory()      // 根据模式加载文件
└── playMedia()                  // 根据模式选择播放方式
```

### 2. 关键代码逻辑

#### 模式切换
```dart
// 切换到本地模式
Future<bool> switchToLocalMode() async {
  // 1. 请求存储权限
  final hasPermission = await _permissionService.ensureStoragePermission();
  if (!hasPermission) return false;
  
  // 2. 设置模式标志
  _isLocalMode = true;
  
  // 3. 加载本地目录
  await _loadCurrentDirectory();
  notifyListeners();
  return true;
}
```

#### 文件加载
```dart
Future<void> _loadCurrentDirectory() async {
  if (_isLocalMode) {
    // 本地模式：使用Dart Directory API
    final directory = Directory(_currentPath);
    final entities = await directory.list().toList();
    _currentFiles = entities.map((entity) => MediaFile(...)).toList();
  } else {
    // SSH模式：使用SSH服务
    _currentFiles = await _sshService.listDirectory(_currentPath);
  }
}
```

#### 文件播放
```dart
Future<void> playMedia(MediaFile file) async {
  if (_isLocalMode) {
    // 本地模式：直接播放
    await _audioPlayerService.playFile(file.path, isVideo: file.isVideo);
  } else {
    // SSH模式：流式播放
    await _playMediaStreaming(file);
  }
}
```

### 3. 权限管理

#### AndroidManifest.xml 配置
```xml
<!-- Android 12及以下 -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" 
    android:maxSdkVersion="32" />

<!-- Android 13+ (API 33+) -->
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
```

#### 运行时权限请求
```dart
// StoragePermissionService
Future<bool> ensureStoragePermission() async {
  if (await _isAndroid13OrAbove()) {
    // Android 13+: 请求音频和视频权限
    final statuses = await [
      Permission.audio,
      Permission.videos,
    ].request();
    return statuses[Permission.audio]?.isGranted == true &&
           statuses[Permission.videos]?.isGranted == true;
  } else {
    // Android 12及以下: 请求存储权限
    final result = await Permission.storage.request();
    return result.isGranted;
  }
}
```

## 注意事项

### 1. Android版本兼容性

- **Android 10 (API 29)+**: 引入了分区存储（Scoped Storage）
  - 应用专属目录（如`getExternalStorageDirectory()`）无需额外权限
  - 访问公共目录可能需要用户授权
  
- **Android 13 (API 33)+**: 引入了细粒度媒体权限
  - `READ_EXTERNAL_STORAGE`已被废弃
  - 需要使用`READ_MEDIA_AUDIO`和`READ_MEDIA_VIDEO`

### 2. 推荐的文件存放位置

为避免权限问题，建议将音频文件存放在：
- **应用专属目录**: `/storage/emulated/0/Android/data/com.audioplayer.ssh_audio_player/files/`
- **Download目录**: `/storage/emulated/0/Download/`
- **Music目录**: `/storage/emulated/0/Music/`

### 3. 已知限制

- ❌ 不支持iOS平台（仅Android）
- ⚠️ Android 11+访问某些系统目录可能受限
- ⚠️ 部分OEM厂商可能有额外的存储权限限制

### 4. 故障排除

**问题1：切换到本地模式时提示权限被拒绝**
- 解决：前往"设置 → 应用 → SSH Audio Player → 权限"，手动授予存储权限

**问题2：看不到某些文件或文件夹**
- 原因：Android分区存储限制或文件隐藏属性
- 解决：尝试将文件移动到Download或Music目录

**问题3：播放本地文件时无声**
- 检查：确认文件格式是否支持
- 检查：确认文件路径是否正确（无特殊字符）
- 尝试：重启应用或重新加载目录

## 未来改进方向

1. **文件搜索功能**: 支持按名称、类型搜索本地文件
2. **最近播放**: 记录最近播放的本地文件历史
3. **文件夹收藏**: 允许用户收藏常用的本地文件夹
4. **文件排序**: 支持按名称、大小、日期等多种方式排序
5. **缩略图显示**: 为专辑封面生成缩略图
6. **元数据读取**: 从ID3标签读取歌曲信息（标题、艺术家、专辑）

## Git提交记录

```
commit xxxxxx - 新增：本地文件播放功能
  - 添加本地/SSH模式切换
  - 实现本地文件系统浏览
  - 本地文件直接播放
  - 存储权限管理
  - UI优化
```

## 总结

本地文件播放功能的加入，使应用从单纯的"SSH远程播放器"升级为"全能的音频播放器"，既保留了原有的远程播放优势，又增加了本地播放的便利性。用户可以根据实际需求灵活选择文件来源，享受无缝的播放体验。
