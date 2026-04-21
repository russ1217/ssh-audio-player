import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';

// ✅ 全局AppProvider引用，用于在静态上下文中访问
AppProvider? _globalAppProvider;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ 初始化媒体控制监听器（处理通知栏和蓝牙设备的控制命令）
  _initializeMediaControlListener();
  
  // ✅ 初始化SSH检查MethodChannel（处理Native Service的定时检查请求）
  _initializeSshCheckChannel();
  
  runApp(const MyApp());
}

/// ✅ 初始化SSH检查MethodChannel
void _initializeSshCheckChannel() {
  const channel = MethodChannel('com.audioplayer.ssh_audio_player/ssh_check');
  
  channel.setMethodCallHandler((call) async {
    debugPrint('📡 [Flutter] 收到Native SSH检查请求: ${call.method}');
    
    if (call.method == 'checkAndReconnect') {
      try {
        if (_globalAppProvider != null) {
          debugPrint('✅ [Flutter] 调用handleNetworkReconnected...');
          await _globalAppProvider!.handleNetworkReconnected();
          debugPrint('✅ [Flutter] SSH检查完成');
          return true;
        } else {
          debugPrint('⚠️ [Flutter] AppProvider为null，无法执行SSH检查');
          return false;
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [Flutter] SSH检查失败: $e');
        debugPrint('📋 [Flutter] 堆栈跟踪: $stackTrace');
        return false;
      }
    }
    
    return null;
  });
  
  debugPrint('✅ SSH检查MethodChannel已注册');
}

/// ✅ 初始化媒体控制监听器
void _initializeMediaControlListener() {
  MediaSessionService.initializeMediaControlListener();
  
  // 设置回调函数，处理媒体控制命令
  MediaSessionService.onMediaControl = (action, {bool isSystemForced = false}) {
    debugPrint('🎮 处理媒体控制命令: $action (isSystemForced=$isSystemForced)');
    debugPrint('🔍 全局AppProvider: ${_globalAppProvider != null ? "有效" : "null"}');
    
    if (_globalAppProvider != null) {
      try {
        debugPrint('✅ 使用全局AppProvider实例');
        
        switch (action) {
          case 'play':
            // ✅ 关键修复：play 命令应该明确执行播放操作
            debugPrint('▶️ 执行播放命令');
            debugPrint('🔍 当前状态: isPlaying=${_globalAppProvider!.isPlaying}, hasCurrentFile=${_globalAppProvider!.currentPlayingFile != null}');
            
            // ✅ 严格检查：只有在未播放且有文件时才执行播放
            if (!_globalAppProvider!.isPlaying && _globalAppProvider!.currentPlayingFile != null) {
              debugPrint('✅ 满足播放条件，执行播放');
              _globalAppProvider!.togglePlayPause();
            } else if (_globalAppProvider!.isPlaying) {
              debugPrint('⚠️ 已经在播放中，忽略 play 命令');
            } else {
              debugPrint('⚠️ 没有正在播放的文件，忽略 play 命令（可能是误触发）');
            }
            break;
          case 'pause':
            // ✅ 关键修复：区分用户主动暂停和系统强制暂停
            if (isSystemForced) {
              debugPrint('⏸️ 执行系统强制暂停命令');
              if (_globalAppProvider!.isPlaying) {
                _globalAppProvider!.pauseBySystem();
              } else {
                debugPrint('⚠️ 已经暂停，忽略 pause 命令');
              }
            } else {
              debugPrint('⏸️ 执行用户主动暂停命令');
              if (_globalAppProvider!.isPlaying) {
                _globalAppProvider!.togglePlayPause();
              } else {
                debugPrint('⚠️ 已经暂停，忽略 pause 命令');
              }
            }
            break;
          case 'toggle_play_pause':
            // ✅ toggle_play_pause 用于通知栏按钮等场景，直接切换状态
            debugPrint('▶️/⏸️ 执行播放/暂停切换命令');
            _globalAppProvider!.togglePlayPause();
            break;
          case 'stop':
            debugPrint('⏹️ 执行停止命令');
            _globalAppProvider!.stopPlayback();
            break;
          case 'next':
            debugPrint('⏭️ 执行下一曲命令');
            _globalAppProvider!.playNextInPlaylist();
            break;
          case 'previous':
            debugPrint('⏮️ 执行上一曲命令');
            _globalAppProvider!.playPreviousInPlaylist();
            break;
          default:
            debugPrint('⚠️ 未知的控制命令: $action');
        }
      } catch (e, stackTrace) {
        debugPrint('❌ 处理媒体控制命令失败: $e');
        debugPrint('📋 堆栈跟踪: $stackTrace');
      }
    } else {
      debugPrint('⚠️ 全局AppProvider为null，跳过控制命令');
    }
  };
  
  debugPrint('✅ 媒体控制监听器已初始化并设置回调');
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _notificationService = NotificationService();
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _isForegroundServiceRunning = false;

  @override
  void initState() {
    super.initState();
    
    // ✅ 暂时不在initState中启动服务，改为在首次播放时启动
    debugPrint('✅ 应用已初始化，服务将在首次播放时启动');
  }
  
  /// ✅ 初始化前台服务（确保MediaSession和通知正常工作）
  Future<void> _initializeForegroundService() async {
    try {
      if (!_isForegroundServiceRunning) {
        // ✅ 关键修复：延迟500ms，确保MethodChannel handler已注册
        await Future.delayed(const Duration(milliseconds: 500));
        await BackgroundService.start();
        _isForegroundServiceRunning = true;
        debugPrint('✅ 前台服务已启动，MediaSession已初始化');
      }
    } catch (e) {
      debugPrint('❌ 启动前台服务失败: $e');
      // ✅ 即使启动失败，也标记为已运行，避免重复尝试
      _isForegroundServiceRunning = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initApp() async {
    await _notificationService.init();
    
    // ✅ Android 13+ 请求通知权限
    await _requestNotificationPermission();
    
    debugPrint('✅ 应用初始化完成，使用前台服务机制保持后台播放');
  }
  
  /// ✅ 请求通知权限（Android 13+ 必需）
  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      
      if (status.isDenied || status.isPermanentlyDenied) {
        debugPrint('📱 请求通知权限...');
        final result = await Permission.notification.request();
        
        if (result.isGranted) {
          debugPrint('✅ 通知权限已授予');
        } else if (result.isPermanentlyDenied) {
          debugPrint('⚠️ 通知权限被永久拒绝，请在设置中手动开启');
        } else {
          debugPrint('❌ 通知权限被拒绝');
        }
      } else if (status.isGranted) {
        debugPrint('✅ 通知权限已存在');
      }
    } catch (e) {
      debugPrint('⚠️ 请求通知权限失败: $e');
    }
  }

  /// 停止前台服务和播放器
  Future<void> _stopForegroundServiceAndPlayer() async {
    debugPrint('🛑 应用被销毁，停止前台服务和播放器...');
    
    try {
      // ✅ 关键修复：先获取 AppProvider 并停止音频播放
      final context = _navigatorKey.currentContext;
      if (context != null) {
        try {
          final provider = context.read<AppProvider>();
          await provider.stopPlayback();
          debugPrint('✅ 音频播放器已停止');
        } catch (e) {
          debugPrint('⚠️ 停止音频播放器失败: $e');
        }
      }
      
      // ✅ 关键修复：停止前台服务
      if (_isForegroundServiceRunning) {
        await BackgroundService.stop();
        _isForegroundServiceRunning = false;
        debugPrint('✅ 前台服务已停止');
      }
      
      // ✅ 隐藏通知
      _notificationService.hideNotification();
      debugPrint('✅ 通知已隐藏');
    } catch (e) {
      debugPrint('⚠️ 停止服务时出错: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      // 进入后台，显示通知并启动前台服务
      debugPrint('📱 应用进入后台');
      _notificationService.showRunningNotification();
      
      // 启动前台服务以保持 SSH 连接和网络活动
      if (!_isForegroundServiceRunning) {
        BackgroundService.start().then((_) {
          _isForegroundServiceRunning = true;
          debugPrint('✅ 前台服务已启动，SSH 连接将在后台保持活跃');
        }).catchError((e) {
          debugPrint('❌ 启动前台服务失败: $e');
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      // 回到前台，隐藏通知
      debugPrint('📱 应用回到前台');
      _notificationService.hideNotification();
      
      // ✅ 关键修复：应用恢复到前台时，检查网络状态并尝试恢复SSH连接
      _checkAndRecoverNetworkConnection();
      
      // 可以选择停止前台服务以节省资源（可选）
      // BackgroundService.stop().then((_) {
      //   _isForegroundServiceRunning = false;
      //   debugPrint('✅ 前台服务已停止');
      // });
    } else if (state == AppLifecycleState.detached) {
      // ✅ 关键修复：应用被销毁时（用户杀死app），停止前台服务和播放器
      _stopForegroundServiceAndPlayer();
    }
  }

  /// ✅ 检查并恢复网络连接
  Future<void> _checkAndRecoverNetworkConnection() async {
    debugPrint('🔍 应用恢复到前台，检查SSH连接状态...');
    
    try {
      // 获取AppProvider实例
      final context = _navigatorKey.currentContext;
      if (context == null) {
        debugPrint('⚠️ 无法获取BuildContext，跳过SSH检查');
        return;
      }
      
      final provider = context.read<AppProvider>();
      
      // ✅ 关键修复：不依赖网络层检测，直接检查SSH连接有效性
      if (!provider.isLocalMode && provider.activeSSHConfig != null) {
        debugPrint('📡 检测到SSH模式，检查连接有效性...');
        
        // 检查SSH是否已连接
        if (!provider.isSSHConnected) {
          debugPrint('⚠️ SSH未连接，尝试重连...');
          await provider.handleNetworkReconnected();
        } else {
          // SSH已连接，但需要验证连接是否真正有效
          debugPrint('✅ SSH已连接，验证连接有效性...');
          final isValid = await provider.sshService.checkConnection();
          
          if (!isValid) {
            debugPrint('❌ SSH连接已失效，触发重连...');
            await provider.handleNetworkReconnected();
          } else {
            debugPrint('✅ SSH连接有效，无需重连');
          }
        }
      } else {
        debugPrint('ℹ️ 本地模式或无SSH配置，跳过SSH检查');
      }
    } catch (e) {
      debugPrint('❌ 检查SSH连接失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final provider = AppProvider();
        // ✅ 设置全局AppProvider引用
        _globalAppProvider = provider;
        debugPrint('✅ 全局AppProvider已设置');
        return provider;
      },
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'SSH Player for Russ',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            elevation: 8,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
