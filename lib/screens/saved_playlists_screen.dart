import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/playlist.dart';

class SavedPlaylistsScreen extends StatefulWidget {
  const SavedPlaylistsScreen({super.key});

  @override
  State<SavedPlaylistsScreen> createState() => _SavedPlaylistsScreenState();
}

class _SavedPlaylistsScreenState extends State<SavedPlaylistsScreen> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Playlist>>(
      future: context.read<AppProvider>().databaseService.getPlaylists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('加载失败: ${snapshot.error}'),
              ],
            ),
          );
        }

        final playlists = snapshot.data ?? [];

        if (playlists.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.playlist_play, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('暂无已保存的播放列表'),
                SizedBox(height: 8),
                Text(
                  '在播放列表页面点击保存按钮',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.music_note,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(
                  playlist.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('${playlist.items.length} 首歌曲'),
                    if (playlist.sshConfigSnapshot != null && 
                        playlist.sshConfigSnapshot!['host'] != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.cloud, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${playlist.sshConfigSnapshot!['username']}@${playlist.sshConfigSnapshot!['host']}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (playlist.lastPlayed != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '上次播放: ${_formatDate(playlist.lastPlayed!)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => _handleMenuAction(context, playlist, value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'load',
                      child: Row(
                        children: [
                          Icon(Icons.play_arrow),
                          SizedBox(width: 8),
                          Text('加载并播放'),
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
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit),
                          SizedBox(width: 8),
                          Text('重命名'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('删除', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
                onTap: () => _handleMenuAction(context, playlist, 'load'),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '今天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return '昨天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  void _handleMenuAction(BuildContext context, Playlist playlist, String action) {
    switch (action) {
      case 'load':
        _loadAndPlayPlaylist(context, playlist);
        break;
      case 'view':
        _viewPlaylistDetails(context, playlist);
        break;
      case 'rename':
        _showRenameDialog(context, playlist);
        break;
      case 'delete':
        _showDeleteConfirmDialog(context, playlist);
        break;
    }
  }

  Future<void> _loadAndPlayPlaylist(BuildContext context, Playlist playlist) async {
    final provider = context.read<AppProvider>();
    
    // 显示加载提示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('正在连接 SSH 并加载播放列表...'),
          ],
        ),
      ),
    );

    try {
      // 如果有 SSH 配置快照，先恢复 SSH 配置
      if (playlist.sshConfigSnapshot != null && playlist.sshConfigId != null) {
        debugPrint('🔄 恢复 SSH 配置: ${playlist.sshConfigSnapshot!['host']}');
        
        // 检查是否已经有相同的 SSH 连接
        if (provider.activeSSHConfig?.id != playlist.sshConfigId) {
          // 需要重新连接 SSH
          final sshConfig = await provider.databaseService.getSSHConfigs();
          final config = sshConfig.firstWhere(
            (c) => c.id == playlist.sshConfigId,
            orElse: () => throw Exception('未找到 SSH 配置'),
          );
          
          await provider.connectSSH(config);
        }
      }

      // 加载播放列表到当前播放列表
      await provider.loadPlaylist(playlist);
      
      // 关闭加载对话框
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // 显示成功提示
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已加载播放列表: ${playlist.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 自动播放第一首
      if (playlist.items.isNotEmpty && context.mounted) {
        await provider.playFromPlaylist(0);
      }
    } catch (e) {
      // 关闭加载对话框
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // 显示错误提示
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _viewPlaylistDetails(BuildContext context, Playlist playlist) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(playlist.name),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('歌曲数量: ${playlist.items.length}'),
              const SizedBox(height: 8),
              if (playlist.sshConfigSnapshot != null) ...[
                Text('SSH 主机: ${playlist.sshConfigSnapshot!['host']}'),
                Text('用户名: ${playlist.sshConfigSnapshot!['username']}'),
                const SizedBox(height: 8),
              ],
              const Divider(),
              const Text('歌曲列表:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlist.items.length,
                  itemBuilder: (ctx, index) {
                    final item = playlist.items[index];
                    return ListTile(
                      dense: true,
                      title: Text(item.fileName),
                      subtitle: Text(item.filePath),
                    );
                  },
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

  void _showRenameDialog(BuildContext context, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名播放列表'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '播放列表名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await context.read<AppProvider>().databaseService.updatePlaylistName(
                  playlist.id,
                  controller.text.trim(),
                );
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('重命名成功')),
                  );
                  setState(() {}); // 刷新列表
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, Playlist playlist) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除播放列表 "${playlist.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await context.read<AppProvider>().databaseService.deletePlaylist(playlist.id);
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('删除成功')),
                );
                setState(() {}); // 刷新列表
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
