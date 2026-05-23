import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/ssh_config.dart';
import '../services/network_monitor_service.dart';
import 'package:uuid/uuid.dart';

class SSHConfigScreen extends StatefulWidget {
  const SSHConfigScreen({super.key});

  @override
  State<SSHConfigScreen> createState() => _SSHConfigScreenState();
}

class _SSHConfigScreenState extends State<SSHConfigScreen> {
  final _uuid = const Uuid();
  final NetworkMonitorService _networkMonitor = NetworkMonitorService();
  bool _isNetworkConnected = true; // ✅ 跟踪网络状态

  @override
  void initState() {
    super.initState();
    // ✅ 初始化时检查网络状态
    _checkNetworkStatus();
    
    // ✅ 监听网络状态变化
    _networkMonitor.onNetworkChanged = (isConnected) {
      if (mounted) {
        setState(() {
          _isNetworkConnected = isConnected;
        });
        
        if (!isConnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ 网络已断开，SSH连接可能失败'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ 网络已恢复'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    };
  }
  
  /// ✅ 检查当前网络状态
  Future<void> _checkNetworkStatus() async {
    final isConnected = await _networkMonitor.forceCheckConnectivity();
    if (mounted) {
      setState(() {
        _isNetworkConnected = isConnected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH 服务器配置'),
        actions: [
          // ✅ 新增：网络状态指示器
          IconButton(
            icon: Icon(
              _isNetworkConnected ? Icons.wifi : Icons.wifi_off,
              color: _isNetworkConnected ? Colors.green : Colors.red,
            ),
            tooltip: _isNetworkConnected ? '网络已连接' : '网络已断开',
            onPressed: _checkNetworkStatus,
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.sshConfigs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.settings_ethernet,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text('暂无 SSH 配置'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('添加服务器'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: provider.sshConfigs.length,
            itemBuilder: (context, index) {
              final config = provider.sshConfigs[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: provider.activeSSHConfig?.id == config.id
                        ? Colors.green
                        : Colors.grey,
                    child: Icon(
                      provider.activeSSHConfig?.id == config.id
                          ? Icons.check
                          : Icons.computer,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(config.name),
                  subtitle: Text('${config.username}@${config.host}:${config.port}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (provider.activeSSHConfig?.id != config.id)
                        IconButton(
                          icon: Icon(
                            Icons.login,
                            // ✅ 关键修复：断网时显示不同颜色提示用户
                            color: _isNetworkConnected ? null : Colors.orange,
                          ),
                          tooltip: _isNetworkConnected 
                              ? '连接到服务器' 
                              : '网络已断开，点击尝试重连',
                          // ✅ 关键修复：始终启用连接按钮，允许用户手动重连
                          onPressed: () => _connectToServer(context, config),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: '编辑',
                        onPressed: () => _showAddEditDialog(context, config: config),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: '删除',
                        onPressed: () => _deleteConfig(context, config),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _connectToServer(BuildContext context, SSHConfig config) async {
    // ✅ 关键修复：断网时不阻止连接，而是提示用户网络状态
    if (!_isNetworkConnected) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('⚠️ 网络未连接'),
          content: const Text(
            '当前检测到网络已断开，SSH连接可能会失败。\n\n是否仍要尝试连接？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('仍要尝试'),
            ),
          ],
        ),
      );
      
      // 用户选择取消
      if (shouldContinue != true) {
        return;
      }
      
      // 用户选择继续，显示提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 正在尝试连接...'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
    
    final provider = context.read<AppProvider>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await provider.connectSSH(config);
      
      if (mounted) {
        Navigator.pop(context);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ 连接成功'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isNetworkConnected 
                  ? '❌ 连接失败，请检查配置和网络' 
                  : '❌ 连接失败，网络可能未恢复'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 连接异常: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: '重试',
              textColor: Colors.white,
              onPressed: () => _connectToServer(context, config),
            ),
          ),
        );
      }
    }
  }

  void _showAddEditDialog(BuildContext context, {SSHConfig? config}) {
    final isEditing = config != null;
    final nameController = TextEditingController(text: config?.name ?? '');
    final hostController = TextEditingController(text: config?.host ?? '');
    final portController = TextEditingController(text: config?.port.toString());
    final usernameController = TextEditingController(text: config?.username ?? '');
    final passwordController = TextEditingController(text: config?.password ?? '');
    final pathController = TextEditingController(text: config?.initialPath ?? '/');
    
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? '编辑 SSH 配置' : '添加 SSH 配置'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '名称'),
                  validator: (v) => v?.isEmpty ?? true ? '请输入名称' : null,
                ),
                TextFormField(
                  controller: hostController,
                  decoration: const InputDecoration(labelText: '主机地址'),
                  validator: (v) => v?.isEmpty ?? true ? '请输入主机地址' : null,
                ),
                TextFormField(
                  controller: portController,
                  decoration: const InputDecoration(labelText: '端口'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final port = int.tryParse(v ?? '');
                    if (port == null || port <= 0 || port > 65535) {
                      return '请输入有效端口';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: '用户名'),
                  validator: (v) => v?.isEmpty ?? true ? '请输入用户名' : null,
                ),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: '密码'),
                  obscureText: true,
                ),
                TextFormField(
                  controller: pathController,
                  decoration: const InputDecoration(
                    labelText: '初始路径',
                    hintText: '/',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final newConfig = SSHConfig(
                  id: config?.id ?? _uuid.v4(),
                  name: nameController.text,
                  host: hostController.text,
                  port: int.parse(portController.text),
                  username: usernameController.text,
                  password: passwordController.text.isEmpty ? config?.password : passwordController.text,
                  initialPath: pathController.text,
                );

                final provider = context.read<AppProvider>();
                if (isEditing) {
                  await provider.updateSSHConfig(newConfig);
                } else {
                  await provider.addSSHConfig(newConfig);
                }
                
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isEditing ? '已更新' : '已添加')),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _deleteConfig(BuildContext context, SSHConfig config) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${config.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await context.read<AppProvider>().deleteSSHConfig(config.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已删除')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
