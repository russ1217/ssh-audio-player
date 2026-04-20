import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/bottom_player_bar.dart';
import 'saved_playlists_screen.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  /// ✅ 显示退出确认对话框
  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.exit_to_app, color: Colors.red),
              SizedBox(width: 8),
              Text('退出应用'),
            ],
          ),
          content: const Text(
            '确定要退出应用吗？\n\n将会停止当前播放并断开SSH连接。',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _exitApp(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('退出'),
            ),
          ],
        );
      },
    );
  }

  /// ✅ 退出应用：先停止播放，再断开连接，最后退出
  Future<void> _exitApp(BuildContext context) async {
    final provider = context.read<AppProvider>();
    
    try {
      // 显示加载提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 16),
              Text('正在停止播放并退出...'),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );
      
      debugPrint('🛑 用户主动退出应用');
      
      // 第1步：停止播放
      debugPrint('⏹️ 第1步：停止音频播放');
      await provider.stopPlayback();
      await Future.delayed(const Duration(milliseconds: 300));
      
      // 第2步：断开SSH连接（如果已连接）
      if (provider.isSSHConnected) {
        debugPrint('🔌 第2步：断开SSH连接');
        await provider.disconnectSSH();
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      // 第3步：停止后台服务
      debugPrint('🛑 第3步：停止后台服务');
      try {
        const MethodChannel('com.example.player/background_service')
            .invokeMethod('stopService');
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('⚠️ 停止后台服务失败: $e');
      }
      
      // 第4步：退出应用
      debugPrint('💀 第4步：退出应用');
      
      // 使用 SystemNavigator.pop() 退出应用
      await SystemNavigator.pop(animated: true);
      
      // 如果上面的方法不起作用，强制退出
      await Future.delayed(const Duration(milliseconds: 500));
      exit(0);
      
    } catch (e, stackTrace) {
      debugPrint('❌ 退出应用时出错: $e');
      debugPrint('堆栈: $stackTrace');
      
      // 即使出错也尝试退出
      try {
        await SystemNavigator.pop(animated: true);
      } catch (_) {
        exit(1);
      }
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放列表'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '当前播放', icon: Icon(Icons.queue_music)),
            Tab(text: '已保存', icon: Icon(Icons.library_music)),
          ],
        ),
        actions: [
          // ✅ 恢复上次播放位置按钮（基于当前播放列表）
          Consumer<AppProvider>(
            builder: (context, provider, child) {
              return FutureBuilder<bool>(
                future: provider.hasPendingRestoreForCurrentPlaylist(),
                builder: (context, snapshot) {
                  final hasRestore = snapshot.data ?? false;
                  if (!hasRestore) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    icon: const Icon(Icons.restore, color: Colors.orange),
                    tooltip: '恢复当前列表的上次播放位置',
                    onPressed: () => _showRestoreDialog(context),
                  );
                },
              );
            },
          ),
          Consumer<AppProvider>(
            builder: (context, provider, child) {
              if (provider.playlist.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.save),
                tooltip: '保存播放列表',
                onPressed: () => _showSaveDialog(context),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空播放列表',
            onPressed: () {
              context.read<AppProvider>().clearPlaylist();
            },
          ),
          // ✅ 新增：退出应用按钮（在最右侧）
          IconButton(
            icon: const Icon(
              Icons.exit_to_app,
              color: Colors.red,
            ),
            tooltip: '退出应用',
            onPressed: () => _showExitDialog(context),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 当前播放列表
          _CurrentPlaylistTab(),
          // 已保存的播放列表
          const SavedPlaylistsScreen(),
        ],
      ),
    );
  }

  void _showSaveDialog(BuildContext context) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存播放列表'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '播放列表名称',
            hintText: '例如：我的最爱',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<AppProvider>().savePlaylistToDatabase(controller.text);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('已保存: ${controller.text}')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRestoreDialog(BuildContext context) async {
    final provider = context.read<AppProvider>();
    
    // ✅ 获取当前播放列表的待恢复信息
    final restoreInfo = await provider.getPendingRestoreInfoForCurrentPlaylist();
    
    if (restoreInfo == null || !context.mounted) return;
    
    final songIndex = restoreInfo['songIndex'] as int;
    final positionMs = restoreInfo['positionMs'] as int;
    final position = Duration(milliseconds: positionMs);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.restore, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('恢复上次播放'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '检测到当前播放列表的上次播放记录：',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('🎵 歌曲位置: 第 ${songIndex + 1} 首'),
            Text('⏱️ 播放进度: ${_formatDuration(position)}'),
            const SizedBox(height: 16),
            const Text(
              '是否恢复到上次的播放位置？',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              
              // 显示加载提示
              if (context.mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (loadingCtx) => const AlertDialog(
                    content: Row(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 20),
                        Text('正在恢复播放...'),
                      ],
                    ),
                  ),
                );
              }
              
              try {
                await provider.restoreAndPlay();
                
                if (context.mounted) {
                  Navigator.of(context).pop(); // 关闭加载对话框
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ 已恢复到上次播放位置'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop(); // 关闭加载对话框
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ 恢复失败: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('恢复播放'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

// 当前播放列表标签页
class _CurrentPlaylistTab extends StatefulWidget {
  @override
  State<_CurrentPlaylistTab> createState() => _CurrentPlaylistTabState();
}

class _CurrentPlaylistTabState extends State<_CurrentPlaylistTab> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentPlaying(AppProvider provider) {
    print('📜 点击滚动 - currentIndex: ${provider.currentIndex}, playlist长度: ${provider.playlist.length}');
    
    if (provider.currentIndex >= 0 && provider.currentIndex < provider.playlist.length) {
      // 延迟一帧确保widget已渲染
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _getItemKey(provider.currentIndex);
        print('📜 GlobalKey currentContext: ${key.currentContext}');
        
        if (key.currentContext != null) {
          print('📜 开始滚动到索引: ${provider.currentIndex}');
          Scrollable.ensureVisible(
            key.currentContext!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.5, // 滚动到视口中间位置
          );
        } else {
          print('❌ GlobalKey没有关联的context,使用ScrollController直接滚动');
          
          // 获取当前滚动位置和视口信息
          final currentScroll = _scrollController.offset;
          final viewportHeight = _scrollController.position.viewportDimension;
          final maxScroll = _scrollController.position.maxScrollExtent;
          
          // 使用固定的item高度(与Container设置的height一致)
          const fixedItemHeight = 72.0;
          final totalItems = provider.playlist.length.toDouble();
          
          // 计算目标项的顶部位置
          final itemTopPosition = provider.currentIndex * fixedItemHeight;
          
          // 要让目标项居中: 滚动位置 = 目标项顶部 - (视口高度/2 - item高度/2)
          // 这样目标项的中心会对齐到视口中心
          final centerOffset = (viewportHeight / 2) - (fixedItemHeight / 2);
          var targetPosition = itemTopPosition - centerOffset;
          
          // 关键修正: 如果目标位置会超出最大滚动范围,就调整策略
          // 对于靠近末尾的项,确保它能完全显示在视口中即可
          if (targetPosition > maxScroll) {
            // 目标项在视口底部附近,滚动到能让它完全显示的位置
            targetPosition = maxScroll;
          } else if (targetPosition < 0) {
            // 目标项在视口顶部附近
            targetPosition = 0;
          }
          
          // 确保不超出边界(双重保险)
          final clampedPosition = targetPosition.clamp(0.0, maxScroll);
          
          print('📜 固定高度 - item高度: $fixedItemHeight, 项目数: $totalItems');
          print('📜 计算详情 - itemTopPosition: ${itemTopPosition.toStringAsFixed(2)}, centerOffset: ${centerOffset.toStringAsFixed(2)}');
          print('📜 滚动参数 - 目标位置: ${targetPosition.toStringAsFixed(2)}, 夹紧后: ${clampedPosition.toStringAsFixed(2)}');
          print('📜 视口高度: ${viewportHeight.toStringAsFixed(2)}, 最大滚动: ${maxScroll.toStringAsFixed(2)}');
          print('📜 当前滚动: ${currentScroll.toStringAsFixed(2)}, 需要移动: ${(clampedPosition - currentScroll).toStringAsFixed(2)}');
          
          _scrollController.animateTo(
            clampedPosition,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      });
    } else {
      print('❌ currentIndex超出范围: ${provider.currentIndex}');
    }
  }

  GlobalKey _getItemKey(int index) {
    if (!_itemKeys.containsKey(index)) {
      _itemKeys[index] = GlobalKey();
    }
    return _itemKeys[index]!;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        if (provider.playlist.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.playlist_play,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text('播放列表为空'),
                SizedBox(height: 8),
                Text(
                  '从文件浏览器中添加媒体文件',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // ✅ 新增：正在播放的曲目信息显示区域（高亮居中）
            if (provider.currentPlayingFile != null)
              GestureDetector(
                onTap: () => _scrollToCurrentPlaying(provider),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                        Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      // 音频/视频图标
                      Icon(
                        provider.currentPlayingFile!.isVideo
                            ? Icons.movie
                            : Icons.music_note,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      // 文件名称
                      Expanded(
                        child: Text(
                          provider.currentPlayingFile!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1),
            // 播放列表
            Expanded(
              child: PrimaryScrollController(
                controller: _scrollController,
                child: ReorderableListView.builder(
                  itemCount: provider.playlist.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    provider.reorderPlaylist(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final file = provider.playlist[index];
                    final isPlaying = index == provider.currentIndex;

                    return Container(
                      key: _getItemKey(index),
                      height: 72, // 固定高度,确保计算准确
                      child: ListTile(
                        onTap: () {
                          provider.playFromPlaylist(index);
                        },
                        leading: CircleAvatar(
                          backgroundColor: isPlaying
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.secondaryContainer,
                          child: Icon(
                            isPlaying ? Icons.play_arrow : Icons.music_note,
                            color: isPlaying
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                        ),
                        title: Text(
                          file.name,
                          maxLines: 1, // 限制为一行
                          overflow: TextOverflow.ellipsis, // 超出部分显示省略号
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isPlaying ? Theme.of(context).colorScheme.primary : null,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            // ✅ 新增：显示文件来源标识
                            if (file.isSSHFile)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blue.shade200, width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.cloud, size: 12, color: Colors.blue.shade700),
                                    const SizedBox(width: 3),
                                    Text(
                                      'SSH',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (file.isLocalFile)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.green.shade200, width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.phone_android, size: 12, color: Colors.green.shade700),
                                    const SizedBox(width: 3),
                                    Text(
                                      '本地',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                file.isDirectory ? '文件夹' : '音频文件',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'remove') {
                              provider.removeFromPlaylist(index);
                            } else if (value == 'play') {
                              provider.playFromPlaylist(index);
                            } else if (value == 'view') {
                              _viewFileDetails(context, file);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'play',
                              child: Row(
                                children: [
                                  Icon(Icons.play_arrow),
                                  SizedBox(width: 8),
                                  Text('播放'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'view',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility),
                                  SizedBox(width: 8),
                                  Text('查看内容'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Row(
                                children: [
                                  Icon(Icons.remove_circle_outline),
                                  SizedBox(width: 8),
                                  Text('移除'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 查看文件详细信息
  void _viewFileDetails(BuildContext context, dynamic file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              file.isVideo ? Icons.movie : Icons.music_note,
              color: Theme.of(ctx).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.name,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 文件类型
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 16),
                  const SizedBox(width: 8),
                  Text('类型: ${file.isDirectory ? "文件夹" : (file.isVideo ? "视频文件" : "音频文件")}'),
                ],
              ),
              const SizedBox(height: 8),
              // 文件来源
              Row(
                children: [
                  Icon(
                    file.isSSHFile ? Icons.cloud : Icons.phone_android,
                    size: 16,
                    color: file.isSSHFile ? Colors.blue : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text('来源: ${file.isSSHFile ? "SSH 远程" : "本地存储"}'),
                ],
              ),
              const SizedBox(height: 8),
              // 文件路径
              const Divider(),
              const Text('完整路径:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  file.path ?? '未知路径',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
