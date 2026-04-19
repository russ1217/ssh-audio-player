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

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // ✅ 监听应用生命周期，当页面可见时检查并重置异常的loading状态
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ✅ 当应用恢复前台时，重置可能卡住的loading状态
    if (state == AppLifecycleState.resumed) {
      _checkAndResetLoading();
    }
  }

  /// ✅ 检查并重置异常的loading状态
  void _checkAndResetLoading() {
    final provider = context.read<AppProvider>();
    
    // 如果isLoading为true但文件列表已加载完成，说明状态异常
    if (provider.isLoading && provider.currentFiles.isNotEmpty) {
      debugPrint('⚠️ 检测到异常的loading状态，强制重置');
      provider.resetLoadingState();
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 每次build时也检查一次（处理从其他标签页返回的情况）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAndResetLoading();
      }
    });
    
    return Scaffold(
      appBar: AppBar(
        title: Consumer<AppProvider>(
          builder: (context, provider, child) {
            if (provider.isLocalMode) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_android, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.currentPath,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            } else {
              if (!provider.isSSHConnected) {
                return const Text('未连接');
              }
              return Text(provider.currentPath);
            }
          },
        ),
        leading: Consumer<AppProvider>(
          builder: (context, provider, child) {
            // 不在根目录时显示返回按钮
            final isAtRoot = provider.isLocalMode 
                ? (provider.currentPath == '/storage/emulated/0' || provider.currentPath.endsWith('/Android/data'))
                : (provider.currentPath == '/');
            
            final canNavigateBack = !isAtRoot && (provider.isLocalMode || provider.isSSHConnected);
            
            if (canNavigateBack) {
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
          // ✅ 新增：本地/SSH模式切换按钮
          Consumer<AppProvider>(
            builder: (context, provider, child) {
              return IconButton(
                icon: Icon(
                  provider.isLocalMode ? Icons.cloud : Icons.phone_android,
                  color: provider.isLocalMode ? Colors.blue : Colors.green,
                ),
                tooltip: provider.isLocalMode ? '切换到SSH远程' : '切换到本地文件',
                onPressed: () async {
                  if (provider.isLocalMode) {
                    await provider.switchToSSHMode();
                    if (!provider.isSSHConnected) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('请先配置并连接SSH服务器'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } else {
                    final success = await provider.switchToLocalMode();
                    if (!success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('需要存储权限才能访问本地文件'),
                          action: SnackBarAction(
                            label: '去设置',
                            onPressed: () {
                              // TODO: 打开应用设置页面
                            },
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final provider = context.read<AppProvider>();
              if (provider.isLocalMode || provider.isSSHConnected) {
                provider.navigateTo(provider.currentPath);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            onPressed: () {
              final provider = context.read<AppProvider>();
              if (provider.isLocalMode || provider.isSSHConnected) {
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
          // ✅ 本地模式或SSH已连接时显示文件列表
          if (provider.isLocalMode) {
            // 本地文件模式
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
          } else {
            // SSH远程模式
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
          }
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
          Consumer<AppProvider>(
            builder: (context, provider, child) {
              final isTimerActive = provider.timerService.isSleepTimerActive || 
                                    provider.timerService.isFileCountTimerActive;
              
              return ListTile(
                leading: Icon(
                  isTimerActive ? Icons.timer : Icons.timer_outlined,
                  color: isTimerActive ? Colors.green : null,
                ),
                title: const Text('定时关闭'),
                subtitle: Text(
                  isTimerActive 
                    ? '定时已激活 - 点击管理或取消'
                    : '设置播放定时关闭',
                  style: TextStyle(
                    color: isTimerActive ? Colors.green : null,
                    fontWeight: isTimerActive ? FontWeight.w600 : null,
                  ),
                ),
                trailing: isTimerActive
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () {
                              provider.stopTimer();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已取消定时关闭'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.cancel, size: 18),
                            label: const Text('取消'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade50,
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right),
                        ],
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () {
                  _showTimerDialog(context);
                },
              );
            },
          ),
          const Divider(),
          Consumer<AppProvider>(
            builder: (context, provider, child) {
              return FutureBuilder<int>(
                future: provider.getCacheSize(),
                builder: (context, snapshot) {
                  final cacheSize = snapshot.data ?? 0;
                  final cacheSizeText = cacheSize > 0 
                      ? '${provider.cacheFileCount} 个文件 (${_formatFileSize(cacheSize)})'
                      : '${provider.cacheFileCount} 个文件';
                  
                  return ListTile(
                    leading: const Icon(Icons.delete_sweep),
                    title: const Text('清除缓存'),
                    subtitle: Text('当前缓存: $cacheSizeText'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _showClearCacheDialog(context);
                    },
                  );
                },
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于'),
            subtitle: const Text('SSH Player for Russ v1.0.0'),
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

  void _showClearCacheDialog(BuildContext context) {
    final provider = context.read<AppProvider>();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: FutureBuilder<int>(
          future: provider.getCacheSize(),
          builder: (context, snapshot) {
            final cacheSize = snapshot.data ?? 0;
            final sizeText = cacheSize > 0 ? _formatFileSize(cacheSize) : '0 B';
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前缓存: ${provider.cacheFileCount} 个文件 ($sizeText)'),
                const SizedBox(height: 16),
                const Text(
                  '清除后将释放磁盘空间，但下次播放需要重新下载。',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                const Text(
                  '提示：包括所有临时文件和历史下载记录。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              // 显示加载指示器
              if (context.mounted) {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const AlertDialog(
                    content: Row(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 20),
                        Text('正在清除缓存...'),
                      ],
                    ),
                  ),
                );
              }
              
              await provider.clearDownloadCache();
              
              if (context.mounted) {
                Navigator.pop(context); // 关闭加载对话框
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ 缓存已清除'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
  
  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class TimerPickerSheet extends StatelessWidget {
  const TimerPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isTimerActive = provider.timerService.isSleepTimerActive || provider.timerService.isFileCountTimerActive;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '设置定时关闭',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (isTimerActive)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '定时已设置',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
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
          TextButton.icon(
            onPressed: isTimerActive
                ? () {
                    context.read<AppProvider>().stopTimer();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已取消定时关闭')),
                    );
                  }
                : null,
            icon: const Icon(Icons.cancel),
            label: const Text('取消定时'),
            style: TextButton.styleFrom(
              foregroundColor: isTimerActive ? Colors.red : Colors.grey,
            ),
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
