# 项目结构

```
ssh_audio_player/
│
├── android/                              # Android 平台特定文件
│   ├── app/
│   │   ├── build.gradle                 # Android 应用构建配置
│   │   └── src/main/
│   │       ├── AndroidManifest.xml      # Android 应用清单
│   │       ├── java/com/audioplayer/ssh_audio_player/
│   │       │   └── MainActivity.kt      # 主 Activity
│   │       └── res/
│   │           ├── values/
│   │           │   ├── strings.xml      # 字符串资源
│   │           │   └── styles.xml       # 样式定义
│   │           └── drawable/
│   │               └── launch_background.xml  # 启动画面
│   ├── build.gradle                     # 项目级构建配置
│   ├── settings.gradle                  # Gradle 设置
│   ├── gradle.properties                # Gradle 属性
│   ├── local.properties                 # 本地 SDK 路径
│   └── gradle/wrapper/
│       └── gradle-wrapper.properties    # Gradle Wrapper 配置
│
├── lib/                                 # Flutter 源代码
│   ├── main.dart                        # 应用入口点
│   │
│   ├── models/                          # 数据模型
│   │   ├── ssh_config.dart             # SSH 配置模型
│   │   ├── media_file.dart             # 媒体文件模型
│   │   └── playlist.dart               # 播放列表模型
│   │
│   ├── services/                        # 业务服务层
│   │   ├── ssh_service.dart            # SSH 连接和文件操作服务
│   │   ├── audio_player_service.dart   # 音频播放服务
│   │   ├── database_service.dart       # SQLite 数据库服务
│   │   └── timer_service.dart          # 定时器服务
│   │
│   ├── providers/                       # 状态管理
│   │   └── app_provider.dart           # 全局应用状态管理
│   │
│   ├── screens/                         # 页面/屏幕
│   │   ├── home_screen.dart            # 主页（文件浏览器）
│   │   ├── playlist_screen.dart        # 播放列表页面
│   │   └── ssh_config_screen.dart      # SSH 配置管理页面
│   │
│   ├── widgets/                         # 可复用 UI 组件
│   │   ├── file_list_item.dart         # 文件列表项组件
│   │   └── bottom_player_bar.dart      # 底部播放控制栏
│   │
│   └── utils/                           # 工具类（预留）
│
├── test/                                # 测试文件（预留）
│
├── pubspec.yaml                         # 项目依赖配置
├── analysis_options.yaml                # 代码分析规则
├── README.md                            # 项目说明文档
├── GUIDE.md                             # 用户使用指南
├── DEVELOPMENT.md                       # 开发者文档
├── PROJECT_STRUCTURE.md                 # 项目结构文档
└── requirement.md                       # 需求文档
```

## 文件说明

### 核心代码文件

#### 入口文件
- **main.dart** - 应用启动入口，配置主题和 Provider

#### 数据模型 (models/)
- **ssh_config.dart** - SSH 服务器配置的数据结构
- **media_file.dart** - 媒体文件信息（路径、名称、类型等）
- **playlist.dart** - 播放列表和播放列表项

#### 服务层 (services/)
- **ssh_service.dart** - 处理 SSH 连接、目录浏览、文件读取
- **audio_player_service.dart** - 封装音频播放功能
- **database_service.dart** - SQLite 数据库操作（CRUD）
- **timer_service.dart** - 定时关闭功能

#### 状态管理 (providers/)
- **app_provider.dart** - 使用 Provider 模式管理全局状态

#### 页面 (screens/)
- **home_screen.dart** - 主界面，包含文件浏览器和设置
- **playlist_screen.dart** - 播放列表查看和管理
- **ssh_config_screen.dart** - SSH 配置的增删改查

#### UI 组件 (widgets/)
- **file_list_item.dart** - 文件列表项的显示组件
- **bottom_player_bar.dart** - 底部播放控制栏

### 配置文件

#### Flutter 配置
- **pubspec.yaml** - 声明所有依赖包和项目元数据
- **analysis_options.yaml** - Dart 代码分析规则

#### Android 配置
- **android/build.gradle** - 项目级 Gradle 配置
- **android/app/build.gradle** - 应用级构建配置
- **android/settings.gradle** - Gradle 项目设置
- **android/AndroidManifest.xml** - 权限和组件声明
- **android/gradle.properties** - Gradle JVM 参数
- **android/local.properties** - SDK 路径

### 文档文件
- **README.md** - 项目介绍、功能、技术栈、快速开始
- **GUIDE.md** - 详细的用户使用指南
- **DEVELOPMENT.md** - 架构设计、开发指南、扩展说明
- **PROJECT_STRUCTURE.md** - 本文件，项目文件结构说明
- **requirement.md** - 原始需求文档

## 依赖关系

```
main.dart
  └─> AppProvider (状态管理)
        ├─> SSHService
        ├─> AudioPlayerService
        ├─> DatabaseService
        └─> TimerService
  
Screens
  └─> 使用 Provider 访问状态
  └─> 使用 Widgets 构建 UI

Widgets
  └─> 显示数据
  └─> 触发用户操作
```

## 构建流程

1. **flutter pub get** - 下载 pubspec.yaml 中的依赖
2. **Flutter 编译** - Dart 代码编译为平台代码
3. **Gradle 构建** - Android 应用打包
4. **输出 APK/AAB** - 生成可安装文件

## 数据流向

```
用户操作
   ↓
UI 组件
   ↓
Provider (状态更新)
   ↓
Service (业务逻辑)
   ↓
外部系统 (SSH/数据库/文件系统)
   ↓
状态更新
   ↓
UI 重建
```

## 关键设计模式

1. **Provider 模式** - 状态管理
2. **服务层模式** - 业务逻辑封装
3. **MVVM 架构** - Model-View-ViewModel
4. **响应式编程** - Stream 数据流
5. **依赖注入** - 通过 Provider 提供服务

## 版本信息

- **当前版本**: 1.0.0
- **Flutter SDK**: >= 3.2.0
- **Dart SDK**: >= 3.2.0
- **最低 Android API**: 21 (Android 5.0)
- **目标 Android API**: 34 (Android 14)
