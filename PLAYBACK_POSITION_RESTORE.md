# 播放列表上次播放位置记忆功能

## 功能概述

本功能实现了播放位置的持久化存储和自动恢复。当用户关闭应用后再次打开时，系统会检测到上次的播放记录，并提供一键恢复到上次播放位置的便捷操作。

## 核心特性

### 1. **自动保存播放位置**
- ✅ 每次播放歌曲时自动保存当前位置
- ✅ 记录播放列表 ID、歌曲索引、播放进度
- ✅ 异步保存，不影响播放性能
- ✅ 智能匹配所属播放列表

### 2. **智能恢复提示**
- ✅ 应用启动时自动检测上次播放记录
- ✅ 验证播放列表和歌曲索引的有效性
- ✅ UI 显示橙色恢复按钮提醒用户
- ✅ 可选择忽略或恢复，灵活控制

### 3. **一键恢复播放**
- ✅ 自动连接对应的 SSH 服务器
- ✅ 加载完整的播放列表
- ✅ 跳转到正确的歌曲索引
- ✅ 精确恢复到指定播放进度
- ✅ 完善的错误处理和用户提示

## 使用场景

### 场景 1：追剧续播

**问题：** 看到一半的电视剧，关闭应用后下次找不到从哪里继续

**解决：**
1. 观看第 5 集到 15:30
2. 关闭应用
3. 下次打开时，点击橙色的"恢复"按钮
4. 自动连接到服务器，加载播放列表
5. 直接播放第 5 集，并从 15:30 开始

### 场景 2：音乐专辑连续播放

**问题：** 听专辑听到第 8 首，中断后想继续

**解决：**
1. 播放专辑的第 8 首歌
2. 中途退出应用
3. 重新打开，点击恢复按钮
4. 自动从第 8 首继续播放

### 场景 3：多设备切换

**问题：** 在不同时间使用应用，希望保持连续性

**解决：**
- 每次关闭应用都会保存最后的位置
- 下次打开时快速恢复到之前的状态
- 无需手动查找和定位

## 技术实现

### 数据存储结构

```json
{
  "playlistId": "1234567890",
  "songIndex": 5,
  "position": 930000,
  "duration": 1290000,
  "savedAt": "2024-04-17T15:30:00.000Z"
}
```

**字段说明：**
- `playlistId`: 播放列表的唯一标识
- `songIndex`: 歌曲在列表中的索引（从 0 开始）
- `position`: 当前播放进度（毫秒）
- `duration`: 歌曲总时长（毫秒，可选）
- `savedAt`: 保存时间戳

### 核心代码流程

#### 1. 保存播放位置

```dart
// 在 playMedia() 完成后调用
Future<void> _saveCurrentPlaybackPosition() async {
  if (_currentPlayingFile == null || _playlist.isEmpty) return;

  // 智能匹配播放列表
  final playlists = await _databaseService.getPlaylists();
  String playlistId = 'current';
  
  for (final playlist in playlists) {
    final hasCurrentFile = playlist.items.any(
      (item) => item.filePath == _currentPlayingFile!.path,
    );
    if (hasCurrentFile) {
      playlistId = playlist.id;
      break;
    }
  }

  // 保存到数据库
  await _databaseService.saveLastPlayedPosition(
    playlistId: playlistId,
    songIndex: _currentIndex,
    position: _position,
    duration: _duration > Duration.zero ? _duration : null,
  );
}
```

#### 2. 恢复播放位置

```dart
// 应用启动时调用
Future<void> _restoreLastPlayedPosition() async {
  final lastPosition = await _databaseService.getLastPlayedPosition();
  if (lastPosition == null) return;

  final playlistId = lastPosition['playlistId'];
  final songIndex = lastPosition['songIndex'];
  
  // 验证播放列表
  final playlists = await _databaseService.getPlaylists();
  final playlist = playlists.firstWhere(
    (p) => p.id == playlistId,
    orElse: () => Playlist(...),
  );

  if (playlist.items.isEmpty) return;
  
  // 保存待恢复信息
  _pendingRestoreInfo = {
    'playlist': playlist,
    'songIndex': songIndex,
    'positionMs': lastPosition['position'],
  };
}

// 用户点击恢复按钮时执行
Future<void> restoreAndPlay() async {
  final playlist = _pendingRestoreInfo!['playlist'];
  final songIndex = _pendingRestoreInfo!['songIndex'];
  final positionMs = _pendingRestoreInfo!['positionMs'];

  // 1. 连接 SSH（如需要）
  if (playlist.sshConfigSnapshot != null) {
    await connectSSH(config);
  }

  // 2. 加载播放列表
  await loadPlaylist(playlist);
  
  // 3. 设置索引并播放
  _currentIndex = songIndex;
  await playFromPlaylist(songIndex);
  
  // 4. 恢复进度
  await Future.delayed(Duration(milliseconds: 1000));
  await seek(Duration(milliseconds: positionMs));
  
  // 5. 清除待恢复信息
  clearPendingRestoreInfo();
}
```

### UI 交互流程

```
应用启动
  ↓
AppProvider._init()
  ↓
_restoreLastPlayedPosition()
  ↓
读取 SharedPreferences
  ↓
有记录？──否──→ 不显示恢复按钮
  ↓是
验证有效性
  ↓
设置 _pendingRestoreInfo
  ↓
UI 检测到非空
  ↓
显示橙色恢复按钮 🔄
  ↓
用户点击
  ↓
弹出确认对话框
  ↓
选择"恢复播放"
  ↓
显示加载指示器
  ↓
执行 restoreAndPlay()
  ↓
成功 → 绿色提示 ✅
失败 → 红色提示 ❌
```

## 界面展示

### 1. 恢复按钮（AppBar）

```
┌─────────────────────────────────────┐
│  播放列表              🔄 💾 🗑️     │
│  ─────────────────────────────────  │
│  [当前播放]  [已保存]                │
└─────────────────────────────────────┘
         ↑
    橙色恢复按钮
    （仅在有记录时显示）
```

### 2. 恢复确认对话框

```
┌──────────────────────────────────┐
│  🔄 恢复上次播放                  │
├──────────────────────────────────┤
│  检测到上次播放记录：             │
│                                   │
│  📋 播放列表: 我的最爱            │
│  🎵 歌曲位置: 第 6 首             │
│                                   │
│  是否恢复到上次的播放位置？       │
├──────────────────────────────────┤
│        [忽略]  [▶️ 恢复播放]      │
└──────────────────────────────────┘
```

### 3. 加载提示

```
┌──────────────────────┐
│  ⏳ 正在恢复播放...   │
└──────────────────────┘
```

### 4. 成功/失败提示

```
✅ 已恢复到上次播放位置
或
❌ 恢复失败: 未找到 SSH 配置
```

## 数据流图

```
播放歌曲
  ↓
playMedia(file)
  ↓
播放完成
  ↓
_saveCurrentPlaybackPosition()
  ↓
匹配播放列表 ID
  ↓
databaseService.saveLastPlayedPosition()
  ↓
SharedPreferences.setString()
  ↓
JSON 数据持久化存储

---

应用启动
  ↓
AppProvider._init()
  ↓
_restoreLastPlayedPosition()
  ↓
databaseService.getLastPlayedPosition()
  ↓
SharedPreferences.getString()
  ↓
JSON 解析
  ↓
验证有效性
  ↓
设置 _pendingRestoreInfo
  ↓
UI 显示恢复按钮

---

用户点击恢复
  ↓
_showRestoreDialog()
  ↓
用户确认
  ↓
restoreAndPlay()
  ↓
连接 SSH（如需要）
  ↓
loadPlaylist(playlist)
  ↓
playFromPlaylist(index)
  ↓
seek(position)
  ↓
clearPendingRestoreInfo()
  ↓
播放继续
```

## 优势特点

### 1. **用户体验友好**
- 无需手动记录播放位置
- 自动检测和提示
- 一键恢复，操作简单
- 可选择忽略，灵活控制

### 2. **技术可靠性**
- 使用 SharedPreferences 持久化
- 异步操作不阻塞主线程
- 完善的异常处理机制
- 详细的调试日志

### 3. **智能匹配**
- 自动识别歌曲所属的播放列表
- 验证索引有效性，避免越界
- 支持多个播放列表的场景

### 4. **无缝集成**
- 与现有播放逻辑完美融合
- 不影响正常播放流程
- 后台自动保存，无感知

### 5. **资源优化**
- 只保存必要的数据
- JSON 格式轻量高效
- 自动清理过期记录

## 注意事项

### 1. **SSH 连接依赖**
- 恢复播放时需要 SSH 服务器可访问
- 如果服务器配置变更，需要先更新配置
- 密码需要重新输入（安全考虑）

### 2. **文件存在性**
- 如果远程文件被删除或移动，恢复会失败
- 建议定期同步播放列表与实际文件

### 3. **播放列表变更**
- 如果播放列表被删除，记录会自动失效
- 修改播放列表顺序可能影响索引准确性

### 4. **存储空间**
- 每条记录约 200-300 字节
- 只保留最近一次的记录
- 几乎不占用存储空间

## 调试日志示例

```
💾 保存播放位置: 列表=1234567890, 索引=5, 进度=930s
📖 读取播放位置: 列表=1234567890, 索引=5
🔄 发现上次播放位置: 列表=1234567890, 索引=5, 进度=930000ms
✅ 已准备好恢复播放位置，等待用户操作
▶️ 开始恢复播放: 我的最爱, 索引=5
🔗 SFTP 会话已建立（复用模式）
✅ 播放列表已加载: 我的最爱 (24 首歌曲)
⏩ 恢复到进度: 0:15:30.000000
✅ 播放位置恢复成功
```

## 未来改进方向

1. **多位置记忆**
   - 记住多个播放列表的最后位置
   - 为每个列表独立保存进度

2. **自动恢复**
   - 提供选项：自动恢复 vs 手动确认
   - 可配置是否总是询问

3. **进度预览**
   - 在对话框中显示歌曲名称
   - 显示具体的时间位置（如 15:30 / 45:00）

4. **历史记录**
   - 保存最近 N 次的播放位置
   - 可以回退到更早的位置

5. **云同步**
   - 通过云端备份播放位置
   - 多设备间同步进度

6. **智能推荐**
   - 根据播放历史推荐继续观看
   - 统计观看习惯和偏好

## 常见问题

**Q: 为什么有时候没有显示恢复按钮？**
A: 可能的原因：
- 之前没有播放过任何歌曲
- 播放列表已被删除
- 歌曲索引超出范围
- 数据解析失败

**Q: 恢复失败怎么办？**
A: 检查以下几点：
- SSH 服务器是否可访问
- 播放列表是否存在
- 歌曲文件是否还在原位置
- 查看日志获取详细错误信息

**Q: 可以禁用这个功能吗？**
A: 当前版本默认启用。如需禁用，可以在设置中添加开关。

**Q: 保存的记录会过期吗？**
A: 不会自动过期，但只保留最近一次的记录。新的播放会覆盖旧记录。

**Q: 清除缓存会影响播放位置记录吗？**
A: 不会。播放位置记录单独存储，不受缓存清除影响。

---

**更新日期**: 2024-04-17  
**版本**: 1.3.0  
**提交**: e3ae5e8
