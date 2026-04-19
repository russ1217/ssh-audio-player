# 播放列表文件来源标识功能

## 功能描述

在播放列表 UI 中，为每个文件添加来源标识，清晰区分 SSH 远程文件和本地文件。

## 实现方案

### 1. 数据模型增强 (MediaFile)

**新增字段：**
- `sourceType`: FileSourceType 枚举类型，标识文件来源
  - `FileSourceType.local`: 本地文件
  - `FileSourceType.ssh`: SSH 远程文件

**新增便捷方法：**
- `isSSHFile`: 判断是否为 SSH 远程文件
- `isLocalFile`: 判断是否为本地文件

**序列化支持：**
- 在 `toMap()` 和 `fromMap()` 中添加 sourceType 的序列化和反序列化
- 兼容旧数据：如果数据库中缺少 sourceType 字段，默认为 `local`

### 2. 文件加载时设置来源

**本地模式：**
- `_loadCurrentDirectory()`: 加载本地目录时设置 `sourceType: FileSourceType.local`
- `addDirectoryToPlaylist()`: 添加本地目录到播放列表时设置 `sourceType: FileSourceType.local`

**SSH 模式：**
- `_loadCurrentDirectory()`: 加载 SSH 远程目录时设置 `sourceType: FileSourceType.ssh`
- `addDirectoryToPlaylist()`: 添加 SSH 目录到播放列表时设置 `sourceType: FileSourceType.ssh`

### 3. UI 显示优化 (PlaylistScreen)

在播放列表项的 subtitle 中显示来源标识徽章：

**SSH 文件标识：**
- 🎨 蓝色主题
- ☁️ 云朵图标 + "SSH" 文字
- 浅蓝色背景 + 蓝色边框

**本地文件标识：**
- 🎨 绿色主题
- 📱 手机图标 + "本地" 文字
- 浅绿色背景 + 绿色边框

## 视觉效果

```
┌─────────────────────────────────────┐
│ 🎵 song.mp3                         │
│ [☁️ SSH] 音频文件                    │  ← SSH 远程文件
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 🎵 music.mp3                        │
│ [📱 本地] 音频文件                   │  ← 本地文件
└─────────────────────────────────────┘
```

## 使用场景

1. **混合播放列表**：用户可以同时添加本地文件和 SSH 远程文件到同一个播放列表，通过标识清晰区分
2. **网络感知**：用户可以看到哪些文件需要网络连接才能播放
3. **性能预期**：SSH 文件可能需要缓冲时间，标识帮助用户做好心理准备
4. **故障排查**：当播放失败时，可以快速判断是否是网络连接问题

## 相关文件

- `/home/russ/tmp/player/lib/models/media_file.dart` - 数据模型
- `/home/russ/tmp/player/lib/providers/app_provider.dart` - 业务逻辑
- `/home/russ/tmp/player/lib/screens/playlist_screen.dart` - UI 展示

## 测试建议

1. **场景1**：在本地模式下添加文件到播放列表
   - 预期：显示绿色"本地"标识

2. **场景2**：在 SSH 模式下添加文件到播放列表
   - 预期：显示蓝色"SSH"标识

3. **场景3**：混合添加本地和 SSH 文件
   - 预期：列表中同时显示两种标识，清晰可辨

4. **场景4**：从数据库恢复播放列表
   - 预期：标识正确显示，无异常

5. **场景5**：切换模式后查看播放列表
   - 预期：已添加的文件保持原有标识不变

## 技术亮点

✅ **数据驱动**：通过枚举类型确保类型安全
✅ **向后兼容**：旧数据自动默认为本地文件
✅ **视觉清晰**：使用颜色和图标双重标识
✅ **响应式布局**：适配不同屏幕尺寸
✅ **性能优化**：仅在 UI 层增加轻量级 Widget

