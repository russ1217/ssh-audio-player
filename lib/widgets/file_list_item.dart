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
      ),
      subtitle: file.isDirectory
          ? const Text('文件夹')
          : Text(_formatFileSize(file.size)),
      trailing: file.isDirectory
          ? const Icon(Icons.chevron_right)
          : const Icon(Icons.more_vert),
      onTap: () => _onTap(context),
      onLongPress: file.isMedia ? () => _onLongPress(context) : null,
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
      provider.playMedia(file);
    }
  }

  void _onLongPress(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('播放'),
              onTap: () {
                Navigator.pop(context);
                context.read<AppProvider>().playMedia(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('添加到播放列表'),
              onTap: () {
                Navigator.pop(context);
                context.read<AppProvider>().addToPlaylist(file);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已添加到播放列表')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('文件信息'),
              onTap: () {
                Navigator.pop(context);
                _showFileInfo(context);
              },
            ),
          ],
        ),
      ),
    );
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
