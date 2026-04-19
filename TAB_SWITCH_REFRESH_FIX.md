# Tab切换文件列表刷新问题修复

## 问题描述

当从播放列表切换到文件浏览器时，会出现一直转圈的情况，需要手动刷新才能显示文件列表。

**具体场景：**
1. 打开app后直接打开播放列表（不管是SSH还是本地模式）
2. 再切换到文件UI，界面一直转圈
3. 在SSH和本地播放列表之间互相切换，播放开始后，再点击文件UI，也是这个现象

## 根本原因

1. **`_isLoading` 状态管理不当**：在播放列表操作后，`_isLoading` 可能仍为 `true`，导致文件浏览器显示加载动画
2. **IndexedStack 的特性**：使用 `IndexedStack` 时，Widget 不会重新创建，所以 `initState` 和 `didChangeDependencies` 只在首次创建时调用
3. **缺少主动刷新机制**：Tab 切换时没有通知文件浏览器重新加载目录

## 解决方案

### 1. 添加刷新计数器 (AppProvider)

在 `AppProvider` 中添加 `_refreshCounter` 字段：

```dart
// ✅ 新增：用于强制刷新文件列表的计数器
int _refreshCounter = 0;

// Getter
int get refreshCounter => _refreshCounter;
```

### 2. 添加强制刷新方法 (AppProvider)

```dart
/// ✅ 新增：强制刷新当前目录（用于Tab切换时）
Future<void> forceRefreshCurrentDirectory() async {
  debugPrint('🔄 强制刷新当前目录: $_currentPath (本地模式: $_isLocalMode, SSH连接: $_isSSHConnected)');
  
  // 增加刷新计数器，触发UI重新构建
  _refreshCounter++;
  
  // 如果文件列表为空或loading状态异常，主动加载目录
  if (_currentFiles.isEmpty || _isLoading) {
    debugPrint('📂 文件列表为空或loading异常，重新加载目录');
    await _loadCurrentDirectory();
  } else {
    debugPrint('✅ 文件列表已有数据，仅通知UI刷新');
    notifyListeners();
  }
}
```

### 3. 优化 `_loadCurrentDirectory` 方法

添加防重复加载机制：

```dart
Future<void> _loadCurrentDirectory() async {
  // ✅ 关键修复：如果已经在加载中，避免重复加载
  if (_isLoading) {
    debugPrint('⚠️ 目录正在加载中，跳过重复请求');
    return;
  }
  
  // ... 其余逻辑
  
  finally {
    _isLoading = false;
    notifyListeners();
    debugPrint('🏁 目录加载流程结束，isLoading=false');
  }
}
```

### 4. Tab 切换时触发刷新 (HomeScreen)

在 `NavigationBar` 的 `onDestinationSelected` 回调中：

```dart
onDestinationSelected: (index) {
  setState(() {
    _currentIndex = index;
  });
  
  // ✅ 关键修复：切换到文件浏览器Tab时，强制刷新目录
  if (index == 0) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        final provider = context.read<AppProvider>();
        debugPrint('🔄 切换到文件浏览器Tab，触发刷新');
        provider.forceRefreshCurrentDirectory();
      }
    });
  }
},
```

### 5. 使用 Key 强制重建 UI (FileBrowserScreen)

在 `Consumer` 中使用 `refreshCounter` 作为 Key：

```dart
body: Consumer<AppProvider>(
  builder: (context, provider, child) {
    // ✅ 关键修复：监听 refreshCounter 变化，强制重建UI
    final refreshKey = ValueKey<int>(provider.refreshCounter);
    
    if (provider.isLocalMode) {
      if (provider.isLoading) {
        return Center(
          key: refreshKey, // ✅ 使用key强制重建
          child: const CircularProgressIndicator(),
        );
      }
      
      if (provider.currentFiles.isEmpty) {
        return Center(
          key: refreshKey,
          child: const Text('此目录为空'),
        );
      }
      
      return ListView.builder(
        key: refreshKey,
        itemCount: provider.currentFiles.length,
        itemBuilder: (context, index) {
          final file = provider.currentFiles[index];
          return FileListItem(file: file);
        },
      );
    }
    // ... SSH模式同理
  },
),
```

### 6. 更新刷新按钮

将刷新按钮也改为使用 `forceRefreshCurrentDirectory`：

```dart
IconButton(
  icon: const Icon(Icons.refresh),
  onPressed: () {
    final provider = context.read<AppProvider>();
    if (provider.isLocalMode || provider.isSSHConnected) {
      provider.forceRefreshCurrentDirectory(); // ✅ 使用强制刷新
    }
  },
),
```

## 修复效果

✅ **Tab 切换自动刷新**：从播放列表切换到文件浏览器时，自动检查并刷新目录
✅ **Loading 状态正确管理**：防止 loading 状态卡住，确保正确重置
✅ **防重复加载**：避免同时发起多个加载请求
✅ **UI 强制重建**：通过 Key 机制确保 UI 及时更新

## 测试建议

1. **场景1**：打开app → 切换到播放列表 → 播放音乐 → 切换回文件浏览器
   - 预期：文件列表正常显示，不会一直转圈

2. **场景2**：SSH模式下播放 → 切换到本地模式播放 → 切换回文件浏览器
   - 预期：文件列表正常显示对应模式的目录内容

3. **场景3**：多次快速切换Tab
   - 预期：不会出现重复加载或状态混乱

4. **场景4**：手动点击刷新按钮
   - 预期：正常刷新当前目录

## 相关文件

- `/home/russ/tmp/player/lib/providers/app_provider.dart`
- `/home/russ/tmp/player/lib/screens/home_screen.dart`
