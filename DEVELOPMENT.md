# 开发者文档

## 架构设计

### 整体架构

```
┌─────────────────────────────────────────────────┐
│                   UI Layer                      │
│  (Screens & Widgets)                            │
│                                                 │
│  ┌──────────┐ ┌──────────┐ ┌─────────────────┐ │
│  │HomeScreen│ │Playlist  │ │SSHConfigScreen  │ │
│  │          │ │Screen    │ │                 │ │
│  └──────────┘ └──────────┘ └─────────────────┘ │
│         ↓              ↓              ↓        │
├─────────────────────────────────────────────────┤
│              Provider Layer                     │
│                                                 │
│              ┌─────────────┐                    │
│              │AppProvider  │                    │
│              │(State Mgmt) │                    │
│              └─────────────┘                    │
│         ↓         ↓         ↓         ↓        │
├─────────────────────────────────────────────────┤
│              Service Layer                      │
│                                                 │
│  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌──────┐│
│  │SSHService│ │AudioPlayer│ │Database│ │Timer ││
│  │          │ │Service   │ │Service │ │Service││
│  └──────────┘ └──────────┘ └────────┘ └──────┘│
├─────────────────────────────────────────────────┤
│              Model Layer                        │
│                                                 │
│  ┌──────────┐ ┌──────────┐ ┌─────────────────┐ │
│  │SSHConfig │ │MediaFile │ │Playlist/Item    │ │
│  └──────────┘ └──────────┘ └─────────────────┘ │
└─────────────────────────────────────────────────┘
```

### 数据流

```
用户操作 → UI → Provider → Service → 外部系统
                        ↓
                     State 更新
                        ↓
                     UI 重建
```

## 核心模块说明

### 1. SSH 服务 (SSHService)

**位置**: `lib/services/ssh_service.dart`

**职责**:
- 管理 SSH 连接
- 浏览远程文件系统
- 读取文件内容

**主要方法**:
```dart
Future<bool> connect(SSHConfig config)  // 连接服务器
Future<void> disconnect()               // 断开连接
Future<List<MediaFile>> listDirectory(String path)  // 列出目录
Future<List<int>> readFile(String path)  // 读取文件
```

**实现细节**:
- 使用 dartssh2 库
- 支持密码认证（私钥认证已预留）
- 使用 SFTP 读取文件

### 2. 音频播放服务 (AudioPlayerService)

**位置**: `lib/services/audio_player_service.dart`

**职责**:
- 播放音频文件
- 控制播放状态
- 提供播放进度信息

**主要方法**:
```dart
Future<void> playFile(String filePath)  // 播放文件
Future<void> play()                      // 继续播放
Future<void> pause()                     // 暂停
Future<void> stop()                      // 停止
Future<void> seek(Duration position)    // 跳转
Future<void> seekForward(Duration d)    // 快进
Future<void> seekBackward(Duration d)   // 快退
```

**流（Streams）**:
```dart
Stream<PlaybackState> playbackStateStream  // 播放状态
Stream<Duration> positionStream            // 播放进度
Stream<Duration> durationStream            // 音频时长
Stream<int> currentIndexStream             // 当前索引
Stream<void> completeStream                // 播放完成
```

### 3. 数据库服务 (DatabaseService)

**位置**: `lib/services/database_service.dart`

**职责**:
- 持久化存储数据
- 管理 SSH 配置
- 管理播放列表
- 记录播放历史

**数据表**:
- `ssh_configs` - SSH 服务器配置
- `playlists` - 播放列表
- `playlist_items` - 播放列表项
- `play_history` - 播放历史

### 4. 定时服务 (TimerService)

**位置**: `lib/services/timer_service.dart`

**职责**:
- 睡眠定时器
- 文件计数定时器
- 触发定时完成事件

**主要方法**:
```dart
void setSleepTimer(Duration duration)     // 设置睡眠定时
void setFileCountTimer(int maxFiles)      // 设置文件计数
void incrementPlayedFiles()               // 增加已播放文件数
void stop()                               // 停止所有定时器
```

### 5. 应用状态管理 (AppProvider)

**位置**: `lib/providers/app_provider.dart`

**职责**:
- 统一管理所有状态
- 协调各个服务
- 提供 UI 状态

**主要状态**:
```dart
List<SSHConfig> sshConfigs          // SSH 配置列表
SSHConfig? activeSSHConfig          // 当前活动配置
bool isSSHConnected                 // SSH 连接状态
List<MediaFile> currentFiles        // 当前目录文件
List<MediaFile> playlist            // 播放列表
int currentIndex                    // 当前播放索引
bool isPlaying                      // 是否正在播放
Duration position                   // 当前位置
Duration duration                   // 总时长
```

## UI 组件

### 屏幕（Screens）

1. **HomeScreen** - 主界面
   - 文件浏览器
   - 底部播放控制
   - 导航栏

2. **PlaylistScreen** - 播放列表管理
   - 显示播放队列
   - 删除/保存功能

3. **SSHConfigScreen** - SSH 配置管理
   - 添加/编辑/删除配置
   - 连接服务器

### 组件（Widgets）

1. **BottomPlayerBar** - 底部播放控制栏
   - 进度条
   - 播放控制按钮
   - 当前播放信息

2. **FileListItem** - 文件列表项
   - 文件图标（根据类型）
   - 文件名和大小
   - 点击/长按操作

## 如何扩展

### 添加新的音频格式

编辑 `lib/models/media_file.dart`:

```dart
bool get isAudio {
  if (isDirectory) return false;
  final ext = _getExtension();
  return [
    'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus', 'aiff',
    'your_new_format',  // 添加这里
  ].contains(ext);
}
```

### 添加新的定时选项

编辑 `lib/screens/home_screen.dart` 中的 `TimerPickerSheet`:

```dart
Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    _TimerButton(context, duration: const Duration(minutes: 15)),
    _TimerButton(context, duration: const Duration(minutes: 30)),
    // 添加新的定时选项
    _TimerButton(context, duration: const Duration(hours: 8)),
  ],
)
```

### 修改快进/快退时间

编辑 `lib/widgets/bottom_player_bar.dart`:

```dart
// 快退按钮 - 修改秒数
IconButton(
  icon: const Icon(Icons.replay_10),  // 改为 replay_30 等
  onPressed: () => provider.seekBackward(const Duration(seconds: 10)), // 修改这里
  tooltip: '快退10秒',
),

// 快进按钮
IconButton(
  icon: const Icon(Icons.forward_10),  // 改为 forward_30 等
  onPressed: () => provider.seekForward(const Duration(seconds: 10)), // 修改这里
  tooltip: '快进10秒',
),
```

### 添加通知栏控制

需要集成 audio_service 的媒体通知功能：

1. 创建 AudioHandler 实现
2. 注册媒体会话
3. 处理媒体按钮事件
4. 更新通知状态

参考：https://pub.dev/packages/audio_service

### 实现流式播放

当前实现是下载完整文件后播放。要实现流式播放：

1. 使用 SSH 端口转发创建本地代理
2. 将 SSH 文件流映射到 HTTP 流
3. 使用 just_audio 播放 HTTP 流

这需要更复杂的实现，但可以减少大文件的等待时间。

## 调试技巧

### 启用调试模式

在 `lib/main.dart` 中添加：

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 启用调试日志
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      print('[DEBUG] $message');
    }
  };
  
  runApp(const MyApp());
}
```

### 查看数据库

使用 Android Studio 的 Device File Explorer：
```
/data/data/com.audioplayer.ssh_audio_player/databases/ssh_audio_player.db
```

使用 SQLite 浏览器打开查看。

### 日志过滤

```bash
# 查看 Flutter 日志
flutter logs

# 查看特定标签的日志
adb logcat | grep -i "ssh\|audio\|player"
```

## 性能优化建议

1. **文件缓存**
   - 已播放的文件缓存在临时目录
   - 可以添加缓存大小限制
   - 可以添加缓存清理功能

2. **内存管理**
   - 大文件列表使用分页加载
   - 及时释放不用的资源
   - 使用懒加载

3. **网络优化**
   - 实现文件流式传输
   - 添加重试机制
   - 显示下载进度

## 测试

### 单元测试

```bash
flutter test
```

### 集成测试

```bash
flutter drive --target=test_driver/app.dart
```

### Widget 测试

```bash
flutter test test/widget_test.dart
```

## 构建发布版本

### APK

```bash
flutter build apk --release
```

输出位置：`build/app/outputs/flutter-apk/app-release.apk`

### App Bundle（推荐）

```bash
flutter build appbundle --release
```

输出位置：`build/app/outputs/bundle/release/app-release.aab`

### 安装到设备

```bash
flutter install
```

## 代码规范

遵循 Dart 官方风格指南：
- https://dart.dev/guides/language/effective-dart/style

关键规则：
- 使用 2 个空格缩进
- 类名使用 PascalCase
- 变量和方法使用 camelCase
- 常量使用 lower_case_with_underscores
- 私有成员使用下划线前缀

## 贡献指南

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 许可证

本项目采用 MIT 许可证。
