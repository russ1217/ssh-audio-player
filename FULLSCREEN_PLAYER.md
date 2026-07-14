# 全屏播放功能说明

## 功能概述

全屏播放模式为用户提供沉浸式的音频播放体验，特别适合需要长时间监控播放进度的场景。

## 主要特性

### 1. 📱 横屏显示
- 自动切换到横屏模式（landscape）
- 提供更宽的显示空间
- 退出时自动恢复竖屏

### 2. ⏱️ 秒表式计时器
- **超大字体**：80px 字号，清晰易读
- **实时显示**：精确到秒的播放时间
- **格式智能**：
  - 不足1小时：`MM:SS`（如 05:32）
  - 超过1小时：`HH:MM:SS`（如 01:05:32）
- **等宽字体**：使用 monospace 字体，数字对齐更美观

### 3. 📊 进度条控制
- **可拖动**：支持手动调整播放位置
- **视觉优化**：
  - 轨道高度：6px
  - 滑块半径：10px
  - 激活颜色：蓝色高亮
  - 未激活：深灰色
- **实时更新**：跟随播放进度自动更新

### 4. ⏰ 时长显示
- **位置**：进度条右侧
- **格式**：`当前时间 / 总时长`
- **示例**：`05:32 / 45:20`
- **样式**：总时长加粗显示，便于区分

### 5. 🔒 防锁屏功能
- **技术实现**：使用 `wakelock_plus` 包
- **自动启用**：进入全屏时自动开启
- **自动禁用**：退出全屏时自动关闭
- **生命周期管理**：应用从后台恢复时重新启用

### 6. 🎮 播放控制
提供三个核心控制按钮：
- **快退 10 秒**：⏪ 图标
- **播放/暂停**：▶️/⏸️ 切换
- **快进 10 秒**：⏩ 图标

### 7. 🚪 退出机制
- **退出按钮**：底部"退出全屏"按钮
- **自动恢复**：
  - 恢复竖屏方向
  - 恢复系统 UI（状态栏、导航栏）
  - 禁用屏幕常亮

## 使用方法

### 进入全屏模式
1. 确保有文件正在播放
2. 在底部播放控制栏找到最右侧的 **全屏按钮** (⛶)
3. 点击按钮进入全屏模式

### 在全屏模式中
- **查看时间**：屏幕中央的大字体显示当前播放时间
- **调整进度**：拖动底部的进度条
- **控制播放**：使用三个控制按钮
- **查看总时长**：进度条下方右侧显示

### 退出全屏模式
点击底部的 **"退出全屏"** 按钮即可返回正常播放界面

## 技术细节

### 依赖包
```yaml
wakelock_plus: ^1.2.8
```

### 关键代码

#### 1. 启用屏幕常亮
```dart
import 'package:wakelock_plus/wakelock_plus.dart';

// 进入全屏时
WakelockPlus.enable();

// 退出全屏时
WakelockPlus.disable();
```

#### 2. 强制横屏
```dart
import 'package:flutter/services.dart';

// 设置首选方向为横屏
SystemChrome.setPreferredOrientations([
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
]);
```

#### 3. 沉浸式全屏
```dart
// 隐藏状态栏和导航栏
SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

// 恢复系统UI
SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
```

#### 4. 生命周期管理
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  
  if (state == AppLifecycleState.resumed) {
    // 重新启用屏幕常亮和横屏
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
}
```

### 时间格式化

```dart
/// 格式化为秒表样式：HH:MM:SS 或 MM:SS
String _formatTimeAsStopwatch(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  
  if (hours > 0) {
    return '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }
  return '${_twoDigits(minutes)}:${_twoDigits(seconds)}';
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');
```

## 注意事项

### 1. 电池消耗
- 屏幕常亮会增加电池消耗
- 建议在不使用时及时退出全屏模式
- 系统可能会在低电量时忽略防锁屏请求

### 2. 系统兼容性
- **Android**：完全支持
- **iOS**：部分支持（可能需要额外权限）
- **桌面平台**：不支持（仅用于开发测试）

### 3. 与其他功能的交互
- **后台播放**：全屏模式下切换到后台会自动暂停防锁屏
- **通知控制**：仍可正常使用通知栏控制
- **定时器**：睡眠定时器和文件计数器正常工作

### 4. 已知限制
- 某些定制 Android 系统可能会覆盖防锁屏设置
- 系统来电或闹钟可能会中断全屏模式
- 部分设备在充电时才能保持屏幕常亮

## 故障排除

### Q: 进入全屏后屏幕仍然锁定
**A**: 
1. 检查系统设置中的"自动锁屏"时间
2. 确认应用有"保持唤醒"权限
3. 尝试重启应用

### Q: 退出全屏后仍然是横屏
**A**: 
1. 这是正常的，退出时会恢复所有方向
2. 旋转设备即可回到竖屏
3. 如果问题持续，请重启应用

### Q: 大字体显示不清晰
**A**: 
1. 检查设备的字体缩放设置
2. 尝试调整系统显示大小
3. 确保使用的是深色背景（黑色最佳）

### Q: 进度条拖动不灵敏
**A**: 
1. 这是网络流媒体的正常现象
2. 本地文件应该响应迅速
3. 检查网络连接稳定性

## 未来改进计划

- [ ] 添加更多控制按钮（上一曲、下一曲、停止）
- [ ] 支持自定义字体大小
- [ ] 添加波形可视化
- [ ] 支持歌词显示
- [ ] 添加主题切换
- [ ] 支持手势控制（双击快进/快退）

## 相关文件

- `/lib/screens/fullscreen_player_screen.dart` - 全屏播放屏幕实现
- `/lib/widgets/bottom_player_bar.dart` - 底部播放栏（包含全屏按钮）
- `/pubspec.yaml` - 依赖配置（包含 wakelock_plus）
