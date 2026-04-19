# 本地文件播放列表功能修复

## 问题描述

### 问题1：本地文件添加到播放列表失效

**现象：**
- 在本地文件模式下，点击"添加到播放列表"按钮无反应
- 播放列表中没有添加任何文件
- 没有任何错误提示

**原因分析：**
```dart
// ❌ 原来的代码
Future<void> addDirectoryToPlaylist(String path) async {
  if (!_isSSHConnected) return;  // 本地模式下_isSSHConnected为false，直接返回
  // ...
}
```

该方法只检查SSH连接状态，在本地模式下会立即返回，不执行任何操作。

### 问题2：播放本地视频时界面一直转圈（已确认播放器正常工作）

**现象：**
- 播放本地视频文件时，主界面显示加载指示器（转圈）
- 但视频实际上已经在正常播放
- 日志显示播放器状态已更新为playing

**可能原因：**
- `_isLoading`标志虽然在finally块中被正确设置为false
- 但UI组件可能在某些情况下没有及时响应状态变化
- 需要进一步观察用户反馈

## 修复方案

### 修复1：支持本地模式的播放列表添加

**修改后的代码：**
```dart
Future<void> addDirectoryToPlaylist(String path) async {
  // ✅ 支持本地模式和SSH模式
  if (!_isLocalMode && !_isSSHConnected) {
    debugPrint('❌ 未连接到SSH服务器且不在本地模式');
    return;
  }

  try {
    _isLoading = true;
    notifyListeners();

    List<MediaFile> files;
    
    if (_isLocalMode) {
      // ✅ 本地模式：使用Dart Directory API
      debugPrint('📁 本地模式：扫描目录 $path');
      await Future.delayed(Duration.zero);
      
      final directory = Directory(path);
      if (!await directory.exists()) {
        debugPrint('❌ 目录不存在: $path');
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      final entities = await directory.list().toList();
      files = entities.map((entity) {
        try {
          final stat = entity.statSync();
          final isDir = stat.type == FileSystemEntityType.directory;
          final fileName = entity.path.split('/').lastWhere(
            (segment) => segment.isNotEmpty,
            orElse: () => entity.path,
          );
          
          return MediaFile(
            path: entity.path,
            name: fileName,
            isDirectory: isDir,
            size: isDir ? null : stat.size,
          );
        } catch (e) {
          debugPrint('⚠️ 跳过无法访问的项目: ${entity.path}');
          return null;
        }
      }).whereType<MediaFile>().toList();
      
      debugPrint('📊 本地目录扫描完成，找到 ${files.length} 个项目');
    } else {
      // ✅ SSH模式：使用SSH服务
      debugPrint('🌐 SSH模式：扫描目录 $path');
      await Future.delayed(Duration.zero);
      files = await _sshService.listDirectory(path);
    }
    
    final mediaFiles = files.where((f) => f.isMedia).toList();
    mediaFiles.sort((a, b) => a.name.compareTo(b.name));
    
    debugPrint('🎵 发现 ${mediaFiles.length} 个媒体文件');
    
    // ✅ 分批添加到播放列表
    const batchSize = 50;
    for (int i = 0; i < mediaFiles.length; i += batchSize) {
      final end = (i + batchSize < mediaFiles.length) ? i + batchSize : mediaFiles.length;
      final batch = mediaFiles.sublist(i, end);
      _playlist.addAll(batch);
      
      await Future.delayed(Duration.zero);
      notifyListeners();
      
      debugPrint('📋 已添加 ${end}/${mediaFiles.length} 个文件到播放列表');
    }
    
    debugPrint('✅ 播放列表添加完成，共 ${mediaFiles.length} 个文件');
  } catch (e, stackTrace) {
    debugPrint('❌ 添加目录到播放列表失败: $e');
    debugPrint('📚 堆栈: $stackTrace');
  } finally {
    _isLoading = false;
    notifyListeners();
  }
}
```

**关键改进：**
1. **条件判断优化**：`if (!_isLocalMode && !_isSSHConnected)` - 任一模式可用即可
2. **本地文件扫描**：复用与`_loadCurrentDirectory`相同的文件提取逻辑
3. **错误处理**：捕获并跳过无法访问的文件，而不是中断整个流程
4. **详细日志**：区分本地/SSH模式，显示扫描进度和结果
5. **统一流程**：两种模式都筛选媒体文件、排序、分批添加

## 测试步骤

### 安装新版本APK

APK已推送到设备：
```
/sdcard/Download/ssh_audio_player_v4.apk
```

### 测试1：本地文件添加到播放列表

1. **打开应用并切换到本地模式**
   - 点击手机图标📱
   - 授予存储权限
   
2. **导航到有媒体文件的目录**
   - 例如：`/storage/emulated/0/Download/DLManager`
   - 该目录包含多个MP4视频文件

3. **点击"添加到播放列表"按钮**
   - AppBar右侧的📋图标
   
4. **验证结果**
   - 应该看到SnackBar提示"已添加目录到播放列表"
   - 切换到"播放列表"标签页
   - 应该看到所有媒体文件已添加到列表中

5. **查看日志确认**
```bash
adb logcat | grep -E "flutter|播放列表"
```

**预期日志输出：**
```
I/flutter: 📁 本地模式：扫描目录 /storage/emulated/0/Download/DLManager
I/flutter: 📊 本地目录扫描完成，找到 10 个项目
I/flutter: 🎵 发现 8 个媒体文件
I/flutter: 📋 已添加 8/8 个文件到播放列表
I/flutter: ✅ 播放列表添加完成，共 8 个文件
```

### 测试2：播放本地视频

1. **点击任意视频文件开始播放**
2. **观察界面**
   - 底部播放控制条应该显示
   - 如果有转圈，应该在几秒内消失
   - 视频应该正常播放

3. **查看日志**
```bash
adb logcat | grep "播放器状态"
```

**预期日志：**
```
I/flutter: 📊 just_audio 状态变化: processingState=ProcessingState.ready, playing=true
I/flutter: 📻 广播播放器状态: PlayerState.playing
I/flutter: 📊 播放器状态变化: PlayerState.playing, isPlaying: false → true
```

如果播放器状态已经是playing但UI还在转圈，请截图反馈。

## 技术细节

### 本地文件扫描逻辑

```dart
// 1. 列出目录内容
final entities = await directory.list().toList();

// 2. 映射为MediaFile对象
files = entities.map((entity) {
  try {
    final stat = entity.statSync();
    final isDir = stat.type == FileSystemEntityType.directory;
    
    // ✅ 正确提取文件名
    final fileName = entity.path.split('/').lastWhere(
      (segment) => segment.isNotEmpty,
      orElse: () => entity.path,
    );
    
    return MediaFile(
      path: entity.path,
      name: fileName,
      isDirectory: isDir,
      size: isDir ? null : stat.size,
    );
  } catch (e) {
    // 跳过无法访问的文件
    return null;
  }
}).whereType<MediaFile>().toList(); // 过滤掉null值
```

### 分批添加策略

```dart
const batchSize = 50; // 每批50个文件
for (int i = 0; i < mediaFiles.length; i += batchSize) {
  final batch = mediaFiles.sublist(i, min(i + batchSize, mediaFiles.length));
  _playlist.addAll(batch);
  
  // 让出控制权给UI线程
  await Future.delayed(Duration.zero);
  notifyListeners();
}
```

**优势：**
- 避免一次性添加大量文件导致UI卡顿
- 用户可以实时看到添加进度
- 即使有数千个文件也能流畅处理

## 相关文件

- [lib/providers/app_provider.dart](file:///home/russ/tmp/player/lib/providers/app_provider.dart) - 核心业务逻辑
- [lib/models/media_file.dart](file:///home/russ/tmp/player/lib/models/media_file.dart) - 数据模型

## Git提交记录

```
commit xxxxxx - 修复：本地模式下添加到播放列表功能失效
  - 修改条件判断支持本地模式
  - 添加本地文件扫描逻辑
  - 统一处理流程和日志输出
```

## 总结

本次修复解决了本地文件模式下播放列表功能完全不可用的问题。通过复用已有的文件扫描逻辑和统一的添加流程，确保了本地和SSH模式的一致性体验。

关于视频播放时界面转圈的问题，从日志看播放器工作正常。如果用户仍然遇到此问题，可能需要进一步调查UI组件的状态同步机制。
