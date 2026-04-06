import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/bottom_player_bar.dart';

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放列表'),
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
      body: Consumer<AppProvider>(
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

          return ReorderableListView.builder(
            itemCount: provider.playlist.length,
            onReorder: (oldIndex, newIndex) {
              // 这里可以实现拖拽重排序
            },
            itemBuilder: (context, index) {
              final file = provider.playlist[index];
              final isCurrentPlaying = index == provider.currentIndex && provider.isPlaying;

              return Card(
                key: ValueKey(file.path),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(
                    file.isAudio ? Icons.audiotrack : Icons.movie,
                    color: isCurrentPlaying ? Colors.deepPurple : null,
                  ),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isCurrentPlaying
                        ? const TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.bold,
                          )
                        : null,
                  ),
                  subtitle: Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index == provider.currentIndex)
                        const Icon(Icons.play_arrow, color: Colors.deepPurple),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          provider.removeFromPlaylist(index);
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    provider.playMedia(file);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showSaveDialog(BuildContext context) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存播放列表'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '播放列表名称',
            hintText: '输入播放列表名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<AppProvider>().savePlaylistToDatabase(controller.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('播放列表已保存')),
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
