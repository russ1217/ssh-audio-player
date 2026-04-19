import 'package:flutter/material.dart';
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
class _CurrentPlaylistTab extends StatelessWidget {
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: provider.currentPlayingFile != null
                      ? [
                          Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                          Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
                        ]
                      : [
                          Colors.grey.shade100,
                          Colors.grey.shade50,
                        ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: provider.currentPlayingFile != null
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                        : Colors.grey.shade300,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.currentPlayingFile != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note,
                          color: Theme.of(context).colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '正在播放',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      provider.currentPlayingFile!.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.3,
                      ),
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.grey.shade600,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '暂无正在播放的曲目',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            // 播放列表
            Expanded(
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
                  
                  return ListTile(
                    key: ValueKey(file.path),
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
                      style: TextStyle(
                        fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
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
                    onTap: () {
                      provider.playFromPlaylist(index);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
