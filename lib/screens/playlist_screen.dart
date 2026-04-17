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
      bottomNavigationBar: const BottomPlayerBar(),
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
            // Prev / Next 控制按钮
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 32),
                    onPressed: provider.currentIndex > 0
                        ? () => provider.playPreviousInPlaylist()
                        : null,
                    tooltip: '上一曲',
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Center(
                      child: Text(
                        provider.currentPlayingFile != null
                            ? '正在播放: ${provider.currentPlayingFile!.name}'
                            : '播放列表 (${provider.playlist.length} 首)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: provider.currentPlayingFile != null
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: provider.currentPlayingFile != null
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 32),
                    onPressed: provider.currentIndex < provider.playlist.length - 1
                        ? () => provider.playNextInPlaylist()
                        : null,
                    tooltip: '下一曲',
                  ),
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
                    subtitle: Text(
                      file.isDirectory ? '文件夹' : '音频文件',
                      style: TextStyle(fontSize: 12),
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
