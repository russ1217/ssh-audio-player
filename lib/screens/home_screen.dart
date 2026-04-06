import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/file_list_item.dart';
import 'ssh_config_screen.dart';
import 'playlist_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const FileBrowserScreen(),
    const PlaylistScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomPlayerBar(),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.folder),
                label: '文件',
              ),
              NavigationDestination(
                icon: Icon(Icons.playlist_play),
                label: '播放列表',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FileBrowserScreen extends StatelessWidget {
  const FileBrowserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<AppProvider>(
          builder: (context, provider, child) {
            if (!provider.isSSHConnected) {
              return const Text('未连接');
            }
            return Text(provider.currentPath);
          },
        ),
        leading: Consumer<AppProvider>(
          builder: (context, provider, child) {
            // 不在根目录时显示返回按钮
            if (provider.currentPath != '/' && provider.isSSHConnected) {
              return IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  provider.navigateToParent();
                },
              );
            }
            return const SizedBox.shrink();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final provider = context.read<AppProvider>();
              if (provider.isSSHConnected) {
                provider.navigateTo(provider.currentPath);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            onPressed: () {
              final provider = context.read<AppProvider>();
              if (provider.isSSHConnected) {
                provider.addDirectoryToPlaylist(provider.currentPath);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已添加目录到播放列表')),
                );
              }
            },
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (!provider.isSSHConnected) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.cloud_off,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '未连接到 SSH 服务器',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SSHConfigScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_ethernet),
                    label: const Text('配置 SSH'),
                  ),
                ],
              ),
            );
          }

          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.currentFiles.isEmpty) {
            return const Center(
              child: Text('此目录为空'),
            );
          }

          return ListView.builder(
            itemCount: provider.currentFiles.length,
            itemBuilder: (context, index) {
              final file = provider.currentFiles[index];
              return FileListItem(file: file);
            },
          );
        },
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.settings_ethernet),
            title: const Text('SSH 服务器配置'),
            subtitle: const Text('管理 SSH 服务器连接配置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SSHConfigScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('定时关闭'),
            subtitle: const Text('设置播放定时关闭'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _showTimerDialog(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于'),
            subtitle: const Text('SSH 音频播放器 v1.0.0'),
          ),
        ],
      ),
    );
  }

  void _showTimerDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => const TimerPickerSheet(),
    );
  }
}

class TimerPickerSheet extends StatelessWidget {
  const TimerPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '设置定时关闭',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TimerButton(context, duration: const Duration(minutes: 15)),
              _TimerButton(context, duration: const Duration(minutes: 30)),
              _TimerButton(context, duration: const Duration(hours: 1)),
              _TimerButton(context, duration: const Duration(hours: 2)),
              _TimerButton(context, duration: const Duration(hours: 3)),
              _TimerButton(context, duration: const Duration(hours: 6)),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              _showCustomTimerDialog(context);
            },
            icon: const Icon(Icons.timer),
            label: const Text('播放 N 个文件后关闭'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              context.read<AppProvider>().stopTimer();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已取消定时关闭')),
              );
            },
            child: const Text('取消定时'),
          ),
        ],
      ),
    );
  }

  void _showCustomTimerDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('播放 N 个文件后关闭'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '文件数量',
            hintText: '输入要播放的文件数量',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final count = int.tryParse(controller.text);
              if (count != null && count > 0) {
                context.read<AppProvider>().setFileCountTimer(count);
                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('将在播放 $count 个文件后关闭')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _TimerButton extends StatelessWidget {
  final BuildContext context;
  final Duration duration;

  const _TimerButton(this.context, {required this.duration});

  @override
  Widget build(BuildContext context) {
    final label = _formatDuration(duration);
    return ElevatedButton(
      onPressed: () {
        context.read<AppProvider>().setSleepTimer(duration);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('将在 $label 后关闭')),
        );
      },
      child: Text(label),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}小时${d.inMinutes % 60}分钟';
    }
    return '${d.inMinutes}分钟';
  }
}
