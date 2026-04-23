import 'package:flutter/material.dart';
import '../models/media_file.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class FileListItem extends StatelessWidget {
  final MediaFile file;

  const FileListItem({
    super.key,
    required this.file,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildLeadingIcon(),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
        ),
      ),
      subtitle: file.isDirectory
          ? const Text(
              '文件夹',
              style: TextStyle(fontSize: 12),
            )
          : Text(
              _formatFileSize(file.size),
              style: const TextStyle(fontSize: 12),
            ),
      trailing: file.isDirectory
          ? const Icon(Icons.chevron_right)
          : PopupMenuButton<String>(
              onSelected: (value) => _onMenuSelected(context, value),
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
                  value: 'playlist_add',
                  child: Row(
                    children: [
                      Icon(Icons.playlist_add),
                      SizedBox(width: 8),
                      Text('添加到播放列表'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'info',
                  child: Row(
                    children: [
                      Icon(Icons.info),
                      SizedBox(width: 8),
                      Text('文件信息'),
                    ],
                  ),
                ),
              ],
            ),
      onTap: () => _onTap(context),
    );
  }

  Widget _buildLeadingIcon() {
    if (file.isDirectory) {
      return const Icon(Icons.folder, color: Colors.amber);
    } else if (file.isAudio) {
      return const Icon(Icons.audiotrack, color: Colors.blue);
    } else if (file.isVideo) {
      return const Icon(Icons.movie, color: Colors.purple);
    } else {
      return const Icon(Icons.insert_drive_file, color: Colors.grey);
    }
  }

  void _onTap(BuildContext context) {
    final provider = context.read<AppProvider>();

    if (file.isDirectory) {
      provider.navigateTo(file.path);
    } else if (file.isMedia) {
      provider.addToPlaylist(file);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加到播放列表: ${file.name}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _onMenuSelected(BuildContext context, String value) {
    switch (value) {
      case 'play':
        context.read<AppProvider>().playMedia(file);
        break;
      case 'playlist_add':
        context.read<AppProvider>().addToPlaylist(file);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到播放列表')),
        );
        break;
      case 'info':
        _showFileInfo(context);
        break;
    }
  }

  void _showFileInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow('类型', file.isDirectory ? '文件夹' : (file.isAudio ? '音频' : '视频')),
            _InfoRow('路径', file.path),
            if (file.size != null) _InfoRow('大小', _formatFileSize(file.size)),
            if (file.modified != null) _InfoRow('修改时间', file.modified.toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '未知大小';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
