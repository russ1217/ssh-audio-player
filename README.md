# SSH 音频播放器

一个基于 Flutter 开发的 Android 音频播放器应用，支持通过 SSH 访问远程服务器播放音频文件。

## 功能特性

### ✅ 已实现功能

1. **SSH 远程访问**
   - 支持密码认证
   - 支持私钥认证
   - 多服务器配置管理
   - 浏览远程服务器文件目录

2. **音频播放**
   - 支持主流音频格式：MP3, WAV, FLAC, AAC, OGG, M4A, WMA, OPUS, AIFF
   - 支持视频文件提取音频播放：MP4, FLV, MKV, AVI, MOV, WMV, WEBM, M4V
   - 后台播放支持（应用切换到后台继续播放）

3. **播放控制**
   - 播放/暂停
   - 停止
   - 快进（10秒）
   - 快退（10秒）
   - 进度条拖拽定位
   - 上一曲/下一曲

4. **播放列表管理**
   - 添加单个文件到播放列表
   - 添加整个目录到播放列表
   - 顺序播放目录下文件
   - 保存播放列表到本地数据库
   - 播放列表持久化存储

5. **定时关闭**
   - 按时间定时关闭（15分钟、30分钟、1小时、2小时、3小时、6小时）
   - 按播放文件数量定时关闭
   - 可随时取消定时

6. **UI 特性**
   - Material Design 3 设计风格
   - 支持亮色/暗色主题（跟随系统）
   - 底部播放控制栏
   - 文件浏览器界面
   - 播放列表管理界面
   - SSH 配置管理界面

## 技术栈

- **Flutter** - 跨平台 UI 框架
- **Dart** - 编程语言
- **dartssh2** - SSH 客户端库
- **just_audio** - 音频播放
- **audio_service** - 后台音频服务
- **sqflite** - 本地 SQLite 数据库
- **provider** - 状态管理
- **path_provider** - 获取系统路径
- **uuid** - 生成唯一 ID

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── models/                      # 数据模型
│   ├── ssh_config.dart         # SSH 配置模型
│   ├── media_file.dart         # 媒体文件模型
│   └── playlist.dart           # 播放列表模型
├── services/                    # 服务层
│   ├── ssh_service.dart        # SSH 连接服务
│   ├── audio_player_service.dart  # 音频播放服务
│   ├── database_service.dart   # 数据库服务
│   └── timer_service.dart      # 定时服务
├── providers/                   # 状态管理
│   └── app_provider.dart       # 全局状态管理
├── screens/                     # 页面
│   ├── home_screen.dart        # 主页和文件浏览器
│   ├── playlist_screen.dart    # 播放列表页面
│   └── ssh_config_screen.dart  # SSH 配置页面
└── widgets/                     # UI 组件
    ├── file_list_item.dart     # 文件列表项
    └── bottom_player_bar.dart  # 底部播放控制栏
```

## 环境要求

- Flutter SDK >= 3.2.0
- Dart SDK >= 3.2.0
- Android SDK (最低 API 21, 目标 API 34)
- JDK 11+

## 安装和构建

### 1. 安装 Flutter

参考官方文档：https://flutter.dev/docs/get-started/install

### 2. 获取依赖

```bash
flutter pub get
```

### 3. 连接设备

确保已连接 Android 设备或启动模拟器：

```bash
flutter devices
```

### 4. 运行应用

```bash
flutter run
```

### 5. 构建 APK

**调试版：**
```bash
flutter build apk
```

**发布版：**
```bash
flutter build apk --release
```

**App Bundle（用于 Google Play）：**
```bash
flutter build appbundle --release
```

## 使用指南

### 1. 配置 SSH 服务器

1. 打开应用，点击"设置"标签
2. 点击"SSH 服务器配置"
3. 点击右下角"+"添加新服务器
4. 填写以下信息：
   - **名称**：服务器标识名
   - **主机地址**：服务器 IP 或域名
   - **端口**：SSH 端口（默认 22）
   - **用户名**：SSH 用户名
   - **密码**：SSH 密码
   - **初始路径**：登录后默认进入的目录
5. 点击"保存"

### 2. 连接服务器

1. 在 SSH 配置列表中找到目标服务器
2. 点击"登录"图标
3. 连接成功后自动进入初始目录

### 3. 浏览和播放文件

1. 在文件浏览器中点击文件夹进入子目录
2. 点击音频/视频文件开始播放
3. 长按文件可查看更多选项：
   - 播放
   - 添加到播放列表
   - 查看文件信息

### 4. 管理播放列表

1. 切换到"播放列表"标签
2. 查看当前播放队列
3. 点击文件可直接播放
4. 点击"..."可删除单个文件
5. 点击"保存"图标可将播放列表保存到数据库
6. 点击"清空"图标可清空当前播放列表

### 5. 使用定时关闭

1. 打开"设置"标签
2. 点击"定时关闭"
3. 选择预设时间或自定义文件数量
4. 定时启动后将在指定时间/文件数后自动停止播放

## 播放控制

底部播放栏提供以下功能：

- **进度条**：拖拽跳转到任意位置
- **上一曲** ⏮️：播放上一首
- **快退** ⏪：后退 10 秒
- **播放/暂停** ▶️⏸️：切换播放状态
- **快进** ⏩：前进 10 秒
- **下一曲** ⏭️：播放下一首
- **停止** ⏹️：停止播放

## 开发说明

### 添加新的音频格式支持

在 `lib/models/media_file.dart` 中修改：

```dart
bool get isAudio {
  final ext = _getExtension();
  return ['mp3', 'wav', 'flac', /* 添加新格式 */].contains(ext);
}
```

### 自定义快进/快退时间

在 `lib/widgets/bottom_player_bar.dart` 中修改：

```dart
// 修改这里的秒数
provider.seekBackward(const Duration(seconds: 10))
provider.seekForward(const Duration(seconds: 10))
```

### 添加更多定时选项

在 `lib/screens/home_screen.dart` 的 `TimerPickerSheet` 中添加：

```dart
_TimerButton(context, duration: const Duration(hours: 8)),
```

## 已知限制

1. **SSH 文件下载**：大文件可能需要缓冲时间
2. **本地缓存**：当前实现会在播放时下载完整文件到临时目录
3. **并发连接**：暂时只支持同时连接一个服务器
4. **私钥认证**：私钥认证功能已预留，需要额外实现

## 后续优化方向

- [ ] 文件流式播放（无需下载完整文件）
- [ ] 支持同时连接多个服务器
- [ ] 播放历史记录
- [ ] 均衡器和音效设置
- [ ] 睡眠定时倒计时显示
- [ ] 通知栏播放控制
- [ ] 耳机线控支持
- [ ] 离线播放列表缓存
- [ ] 搜索远程文件功能

## 许可证

MIT License

## 反馈和问题

如有问题或建议，欢迎提交 Issue。
