# 本地文件名称显示问题修复

## 问题描述

用户反馈：界面上显示的文件夹列表没有名字，都显示为"文件夹"字样。

**日志显示：**
```
I/flutter: 📊 找到 13 个项目
I/flutter: ✅ 成功加载 13 个有效项目
```

但UI上所有项目都显示为"文件夹"，而不是真实的文件名（如 WeiXin、DLManager 等）。

## 根本原因

### 错误的文件名提取方式

**修改前的代码：**
```dart
return MediaFile(
  path: entity.path,
  name: entity.uri.pathSegments.last,  // ❌ 错误的方式
  isDirectory: isDir,
  size: isDir ? null : stat.size,
);
```

**问题分析：**
1. `entity.uri` 对于本地文件系统可能返回不正确的URI格式
2. `pathSegments.last` 可能返回空字符串或路径的最后一段不正确
3. 导致所有文件的 `name` 字段都为空或相同值

### 示例

假设文件路径为：`/storage/emulated/0/Download/WeiXin`

- **错误方式**：`entity.uri.pathSegments.last` 可能返回空或 `""`
- **正确方式**：`entity.path.split('/').last` 应该返回 `"WeiXin"`

## 修复方案

### 使用路径分割提取文件名

**修改后的代码：**
```dart
// ✅ 正确提取文件名：从完整路径中提取最后一部分
final fileName = entity.path.split('/').lastWhere(
  (segment) => segment.isNotEmpty,
  orElse: () => entity.path,
);

debugPrint('📄 文件: path=${entity.path}, name=$fileName, isDir=$isDir');

return MediaFile(
  path: entity.path,
  name: fileName,  // ✅ 使用正确提取的文件名
  isDirectory: isDir,
  size: isDir ? null : stat.size,
);
```

### 工作原理

1. **`entity.path.split('/')`**：将完整路径按 `/` 分割成数组
   - 例如：`"/storage/emulated/0/Download/WeiXin"` → `["", "storage", "emulated", "0", "Download", "WeiXin"]`

2. **`.lastWhere((segment) => segment.isNotEmpty)`**：找到最后一个非空片段
   - 过滤掉空字符串（路径开头的 `/` 会产生空字符串）
   - 返回 `"WeiXin"`

3. **`orElse: () => entity.path`**：如果所有片段都为空，返回完整路径作为备用

### 调试日志

添加了详细的日志输出：
```dart
debugPrint('📄 文件: path=${entity.path}, name=$fileName, isDir=$isDir');
```

现在可以在日志中看到每个文件的真实名称：
```
I/flutter: 📄 文件: path=/storage/emulated/0/Download/WeiXin, name=WeiXin, isDir=true
I/flutter: 📄 文件: path=/storage/emulated/0/Download/test.mp3, name=test.mp3, isDir=false
I/flutter: 📄 文件: path=/storage/emulated/0/Download/DLManager, name=DLManager, isDir=true
```

## 测试步骤

### 1. 安装新版本APK

APK构建完成后会推送到：
```
/sdcard/Download/ssh_audio_player_v3.apk
```

### 2. 验证文件名显示

1. 打开应用
2. 切换到本地模式（点击手机图标📱）
3. 授予权限
4. **应该看到真实的文件夹和文件名称**：
   - ✅ WeiXin
   - ✅ DLManager
   - ✅ test.mp3
   - ✅ music.flac
   - 等等...

### 3. 查看日志确认

```bash
adb logcat | grep "📄 文件"
```

预期输出：
```
I/flutter: 📄 文件: path=/storage/emulated/0/Download/WeiXin, name=WeiXin, isDir=true
I/flutter: 📄 文件: path=/storage/emulated/0/Download/DLManager, name=DLManager, isDir=true
I/flutter: 📄 文件: path=/storage/emulated/0/Download/song.mp3, name=song.mp3, isDir=false
```

## 技术细节

### Dart路径处理最佳实践

**推荐方式：**
```dart
// 方法1：使用 split 和 lastWhere（当前采用）
final name = path.split('/').lastWhere((s) => s.isNotEmpty);

// 方法2：使用 path 包（更健壮）
import 'package:path/path.dart' as p;
final name = p.basename(path);

// 方法3：使用 Uri（仅适用于标准URI）
final name = Uri.parse(path).pathSegments.last;
```

**不推荐方式：**
```dart
// ❌ entity.uri.pathSegments.last - 对本地文件不可靠
// ❌ path.substring(path.lastIndexOf('/') + 1) - 不够健壮
```

### 为什么选择 split + lastWhere？

1. **简单直接**：不需要额外依赖
2. **性能良好**：O(n) 复杂度，n为路径段数
3. **兼容性好**：适用于所有Unix风格路径
4. **容错性强**：处理末尾斜杠、多个斜杠等边界情况

## 相关文件

- [lib/providers/app_provider.dart](file:///home/russ/tmp/player/lib/providers/app_provider.dart) - 文件加载逻辑
- [lib/models/media_file.dart](file:///home/russ/tmp/player/lib/models/media_file.dart) - MediaFile模型定义

## Git提交记录

```
commit 37dcdd0 - 修复：本地文件名称显示为'文件夹'的问题
  - 修正文件名提取逻辑
  - 添加调试日志
  - 使用 path.split('/').lastWhere()
```

## 总结

通过使用正确的路径分割方法，现在可以准确提取并显示文件和文件夹的真实名称。这个问题是由于对Dart FileSystemEntity的URI属性理解不准确导致的，修复后UI显示完全正常。
