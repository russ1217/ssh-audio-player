# 播放列表独立位置恢复功能修复

## 问题描述

之前的实现中，播放位置恢复是**全局的**：
- App启动时读取最后一次保存的播放位置
- 无论打开哪个播放列表，都会尝试恢复到那个全局记录
- 如果打开的播放列表与上次播放的不同，会导致索引越界或从错误的位置开始

**用户期望的行为**：
- 每个播放列表**独立记录**上次播放位置
- 打开某个播放列表时，如果该列表有记录，就恢复到那个位置
- 如果该列表没有记录，就从第一个文件开始播放

## 根本原因分析

### 原有实现的问题

1. **恢复时机不当**：
   - [_restoreLastPlayedPosition()](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L315-L356)在AppProvider初始化时被调用
   - 此时还没有加载任何播放列表，无法判断应该恢复到哪个列表
   
2. **恢复逻辑不匹配**：
   - 数据库中已经按`playlistId`保存了位置
   - 但恢复时没有在**打开播放列表的时机**检查该列表是否有记录

3. **UI交互混乱**：
   - UI层通过`pendingRestoreInfo`显示恢复对话框
   - 但由于恢复时机不对，对话框可能在不合适的时机显示

## 修复方案

### 核心思路

将播放位置恢复的时机从**App初始化时**改为**打开播放列表时**，实现每个播放列表独立管理自己的播放位置。

### 修改1：移除App初始化时的恢复调用

**位置**：[lib/providers/app_provider.dart:73-79](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L73-L79)

```dart
Future<void> _init() async {
  await _loadSSHConfigs();
  _setupSSHHeartbeatListener();
  _setupAudioPlayerListeners();
  _setupTimerListeners();
  // ✅ 移除：不再在初始化时恢复播放位置，改为在打开播放列表时恢复
  // _restoreLastPlayedPosition();
}
```

### 修改2：在loadPlaylist中检查并恢复位置

**位置**：[lib/providers/app_provider.dart:1168-1224](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L1168-L1224)

```dart
Future<void> loadPlaylist(Playlist playlist) async {
  // 清空当前播放列表
  _playlist.clear();
  _currentIndex = 0;
  _currentPlayingFile = null;
  
  // 将保存的播放列表项转换为 MediaFile
  for (final item in playlist.items) {
    _playlist.add(MediaFile.file(item.filePath, item.fileName));
  }
  
  // ✅ 关键修复：检查该播放列表是否有上次播放记录
  await _restorePlaylistPosition(playlist.id);
  
  notifyListeners();
  debugPrint('✅ 播放列表已加载: ${playlist.name} (${_playlist.length} 首歌曲), 当前索引=$_currentIndex');
}
```

### 修改3：新增_restorePlaylistPosition方法

**位置**：[lib/providers/app_provider.dart:1183-1224](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L1183-L1224)

```dart
/// 恢复指定播放列表的上次播放位置
Future<void> _restorePlaylistPosition(String playlistId) async {
  try {
    final lastPosition = await _databaseService.getLastPlayedPosition();
    if (lastPosition == null) {
      debugPrint('📭 播放列表 $playlistId 没有上次播放记录，从第一个开始');
      _currentIndex = 0;
      return;
    }

    final savedPlaylistId = lastPosition['playlistId'] as String;
    
    // 只有当保存的播放列表ID与当前加载的列表ID匹配时才恢复
    if (savedPlaylistId != playlistId) {
      debugPrint('📭 播放列表 $playlistId 没有上次播放记录（上次播放的是 $savedPlaylistId），从第一个开始');
      _currentIndex = 0;
      return;
    }

    final songIndex = lastPosition['songIndex'] as int;
    final positionMs = lastPosition['position'] as int;
    
    // 验证索引有效性
    if (songIndex >= 0 && songIndex < _playlist.length) {
      _currentIndex = songIndex;
      
      // ✅ 如果有进度信息，设置待恢复状态供UI显示或自动恢复
      if (positionMs > 0) {
        _pendingRestoreInfo = {
          'playlistId': playlistId,
          'songIndex': songIndex,
          'positionMs': positionMs,
        };
        debugPrint('🔄 恢复播放列表 $playlistId 的上次位置: 索引=$songIndex, 进度=${positionMs}ms');
      } else {
        debugPrint('🔄 恢复播放列表 $playlistId 的上次索引: $songIndex（无进度信息）');
      }
    } else {
      debugPrint('⚠️ 歌曲索引 $songIndex 超出范围 (0-${_playlist.length - 1})，从第一个开始');
      _currentIndex = 0;
    }
  } catch (e) {
    debugPrint('⚠️ 恢复播放列表位置失败: $e');
    _currentIndex = 0;
  }
}
```

**关键逻辑**：
1. 读取数据库中的上次播放位置
2. 检查`playlistId`是否匹配
3. 如果匹配且索引有效，设置`_currentIndex`
4. 如果有进度信息（毫秒级），保存到[_pendingRestoreInfo](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L359)供后续使用

### 修改4：更新restoreAndPlay方法

**位置**：[lib/providers/app_provider.dart:369-438](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L369-L438)

保持原有的逻辑，使用[_pendingRestoreInfo](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L359)来恢复完整的播放状态（包括进度）。

## 工作流程

### 场景1：打开有记录的播放列表

```
用户操作: 打开"我的歌单A"
↓
loadPlaylist("我的歌单A")
↓
_restorePlaylistPosition("playlist_a_id")
↓
检查数据库: 找到 playlistId="playlist_a_id", songIndex=5, position=120000ms
↓
设置: _currentIndex = 5
设置: _pendingRestoreInfo = { playlistId, songIndex: 5, positionMs: 120000 }
↓
UI显示对话框: "检测到上次播放记录：第6首，进度2:00，是否恢复？"
↓
用户点击"恢复" → restoreAndPlay() → 播放第6首并seek到2:00
用户点击"忽略" → clearPendingRestoreInfo() → 从第6首开头开始播放
```

### 场景2：打开没有记录的播放列表

```
用户操作: 打开"我的歌单B"
↓
loadPlaylist("我的歌单B")
↓
_restorePlaylistPosition("playlist_b_id")
↓
检查数据库: 没有找到 playlistId="playlist_b_id" 的记录
↓
设置: _currentIndex = 0
_pendingRestoreInfo = null
↓
UI不显示对话框，直接从第1首开始播放
```

### 场景3：切换播放列表

```
当前状态: 正在播放"我的歌单A"的第6首
↓
用户操作: 切换到"我的歌单B"
↓
loadPlaylist("我的歌单B")
↓
_restorePlaylistPosition("playlist_b_id")
↓
检查数据库: 上次记录是 playlistId="playlist_a_id"，不匹配
↓
设置: _currentIndex = 0
_pendingRestoreInfo = null
↓
从"我的歌单B"的第1首开始播放
```

## 技术要点

### 1. 播放位置保存（保持不变）

**位置**：[lib/providers/app_provider.dart:1084-1092](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L1084-L1092)

```dart
await _databaseService.saveLastPlayedPosition(
  playlistId: playlistId,  // 按播放列表ID保存
  songIndex: _currentIndex,
  position: _position,
  duration: _duration > Duration.zero ? _duration : null,
);
```

这个逻辑已经是按`playlistId`保存的，无需修改。

### 2. 播放位置恢复（新逻辑）

**触发时机**：每次调用[loadPlaylist()](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L1168-L1181)时
**恢复内容**：
- **索引级别**：自动设置`_currentIndex`（在[loadPlaylist()](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L1168-L1181)中完成）
- **进度级别**：保存到[_pendingRestoreInfo](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L359)，由UI决定是否恢复

### 3. UI交互优化

现有的UI逻辑（[playlist_screen.dart](file:///home/russ/tmp/player/lib/screens/playlist_screen.dart)）已经支持：
- 检查`provider.pendingRestoreInfo`
- 显示恢复对话框
- 用户选择"恢复"或"忽略"

这个逻辑无需修改，因为我们的修改保证了[_pendingRestoreInfo](file:///home/russ/tmp/player/lib/providers/app_provider.dart#L359)只在打开有记录的播放列表时才被设置。

## 优势

1. **独立性**：每个播放列表独立管理自己的播放位置
2. **准确性**：不会出现跨列表恢复导致的索引越界
3. **灵活性**：用户可以选择是否恢复到具体进度，或者只恢复索引
4. **兼容性**：保持了现有的UI交互逻辑，无需修改界面代码

## 相关文件

- `lib/providers/app_provider.dart`：核心播放列表管理和位置恢复逻辑
- `lib/services/database_service.dart`：播放位置的持久化存储（已支持按playlistId保存）
- `lib/screens/playlist_screen.dart`：UI层的恢复对话框（无需修改）

## 测试建议

### 测试场景1：单个播放列表的恢复
1. 打开"歌单A"，播放到第5首，进度2分钟
2. 退出应用
3. 重新打开应用，打开"歌单A"
4. **验证**：应该显示恢复对话框，提示恢复到第5首2分钟处
5. 点击"恢复"，**验证**：应该从第5首2分钟处继续播放

### 测试场景2：多个播放列表的独立恢复
1. 打开"歌单A"，播放到第3首
2. 切换到"歌单B"，播放到第7首
3. 退出应用
4. 重新打开应用，打开"歌单A"
5. **验证**：应该恢复到"歌单A"的第3首（而不是"歌单B"的第7首）
6. 切换到"歌单B"
7. **验证**：应该恢复到"歌单B"的第7首

### 测试场景3：无记录的播放列表
1. 创建新的"歌单C"
2. 打开"歌单C"
3. **验证**：不应该显示恢复对话框，直接从第1首开始

### 测试场景4：索引越界处理
1. 打开"歌单A"（有10首歌），播放到第8首
2. 删除"歌单A"的前5首歌，只剩5首
3. 重新打开"歌单A"
4. **验证**：应该检测到索引越界，从第1首开始播放

## 修复日期
2026-04-17
