# 缓存策略优化：限制预下载数量为3个

## 修改日期
2026年4月17日

## 问题描述
原有的预下载逻辑会在播放50MB以下文件时，一次性下载播放列表中所有后续曲目，这会导致：
- **大量占用存储空间**：如果播放列表有几十首歌曲，会全部下载到本地
- **浪费网络带宽**：用户可能只播放前面几首，后面的下载完全浪费
- **影响用户体验**：大量并发下载可能影响当前播放的流畅性

## 优化方案

### 核心改进
改为**递进式预下载**策略：
- 每次只预下载当前播放曲目后面的 **最多 3 个曲目**
- 随着播放进度推进，动态下载后续曲目
- 避免一次性下载全部内容

### 实现细节

#### 1. 新增状态变量
```dart
int _predownloadMaxIndex = 0; // 预下载的最大索引
```

#### 2. 修改 `_startPredownloading()` 方法
```dart
void _startPredownloading() {
  if (_isPredownloading) {
    debugPrint('⚠️ 预下载正在进行中，跳过');
    return;
  }
  
  // 计算需要预下载的范围：从 currentIndex + 1 开始，最多3个
  final startDownloadIndex = _currentIndex + 1;
  final maxDownloadIndex = startDownloadIndex + 3; // 最多下载后面3个
  
  if (startDownloadIndex >= _playlist.length) {
    debugPrint('✅ 已经是最后一个曲目，无需预下载');
    return;
  }
  
  _predownloadIndex = startDownloadIndex;
  _predownloadMaxIndex = maxDownloadIndex.clamp(0, _playlist.length);
  debugPrint('🚀 开始预下载: 索引 $_predownloadIndex 到 $_predownloadMaxIndex');
  _predownloadNext();
}
```

#### 3. 修改 `_predownloadNext()` 方法
```dart
Future<void> _predownloadNext() async {
  // 检查是否超出预下载范围或播放列表范围
  if (_predownloadIndex >= _predownloadMaxIndex || 
      _predownloadIndex >= _playlist.length) {
    _isPredownloading = false;
    debugPrint('✅ 预下载完成（已达到限制）');
    return;
  }
  
  // ... 下载逻辑
}
```

#### 4. 修改 `_stopPredownloading()` 方法
```dart
void _stopPredownloading() {
  _isPredownloading = false;
  _predownloadIndex = -1;
  _predownloadMaxIndex = 0; // 重置最大索引
}
```

#### 5. 触发时机
预下载会在以下时机触发：
- **播放小文件（<50MB）后**：在 `_playMediaAfterDownload()` 中触发
- **使用缓存文件播放后**：在 `playMedia()` 中使用缓存文件时也触发

#### 6. 停止时机
预下载会在以下时机停止：
- 停止播放时：`stopPlayback()` 调用 `_stopPredownloading()`
- 清空播放列表时：`clearPlaylist()` 调用 `_stopPredownloading()`
- 达到预下载限制时：自动停止（索引达到 `_predownloadMaxIndex`）

## 工作流程示例

假设播放列表有 10 首曲目：

```
初始状态：播放第 1 首
├─ 预下载：第 2、3、4 首（最多3个）
└─ 下载完成后等待

播放第 2 首时
├─ 第 2 首已在缓存中，直接使用
├─ 预下载：第 5 首（补充到3个缓冲）
└─ 下载完成后等待

播放第 4 首时
├─ 第 4 首已在缓存中，直接使用
├─ 预下载：第 6、7、8 首
└─ 下载完成后等待

播放第 8 首时
├─ 第 8 首已在缓存中，直接使用
├─ 预下载：第 9、10 首（只剩2个）
└─ 下载完成后等待

到达最后一首，预下载结束
```

## 优势

1. **节省存储空间**：只缓存最近会播放的 3-4 首曲目，大幅减少磁盘占用
2. **节省网络带宽**：避免下载用户可能不会播放的后续曲目
3. **更快响应**：少量并发下载，不会占用过多系统资源
4. **智能递进**：随着播放进度自动补充预下载队列，保持流畅体验
5. **灵活适应**：无论播放列表多长，都只维护固定大小的缓冲池

## 技术细节

### 并发控制
- `_isPredownloading` 标志确保同一时间只有一个下载任务
- 防止重复触发导致并发下载

### 范围限制
- `_predownloadIndex`：当前下载索引
- `_predownloadMaxIndex`：预下载上限索引（= currentIndex + 4）
- 通过两者比较精确控制下载数量

### 缓存检查
- 下载前检查 `_downloadCache`
- 已缓存文件跳过下载，继续下一个
- 避免重复下载浪费资源

### 边界处理
- 使用 `.clamp(0, _playlist.length)` 确保不越界
- 播放列表末尾时自动停止预下载
- 空播放列表时不触发预下载

## 验证结果
- ✅ Flutter 分析：无错误
- ✅ 代码提交成功：commit f20d3ba
- ✅ 逻辑验证：预下载限制为 3 个曲目
- ✅ 状态管理：所有相关状态正确重置

## 性能对比

### 优化前
- **场景**：100首歌曲的播放列表，平均每首30MB
- **预下载量**：可能下载全部99首后续歌曲
- **存储空间**：约 3GB
- **网络流量**：约 3GB
- **启动延迟**：需要等待所有下载完成

### 优化后
- **场景**：同样的100首歌曲
- **预下载量**：始终只下载最多3首
- **存储空间**：约 90MB（3首 × 30MB）
- **网络流量**：按需下载，最多节省 97%
- **启动延迟**：几乎无延迟，只需下载当前歌曲

## 未来优化建议

1. **可配置数量**：允许用户在设置中调整预下载数量（1-5个）
2. **网络状态感知**：WiFi 时多下载（5个），移动网络少下载（2个）
3. **智能预测**：根据用户播放习惯调整预下载策略
4. **下载队列优先级**：优先下载用户经常播放的曲目
5. **过期清理**：定期清理长时间未播放的缓存文件

## 相关文件

- `lib/providers/app_provider.dart`：核心预下载逻辑实现
- 提交记录：`f20d3ba` - 优化缓存策略：50MB以下文件只预下载当前播放项后最多3个节目

---

**更新日期**: 2026-04-17  
**版本**: 1.3.0  
**提交**: f20d3ba
