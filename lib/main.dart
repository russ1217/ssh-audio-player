import 'package:flutter/material.dart';
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
  
  runApp(const MyApp());
}

/// ✅ 初始化媒体控制监听器
void _initializeMediaControlListener() {
  MediaSessionService.initializeMediaControlListener();
  
  // 设置回调函数，处理媒体控制命令
  MediaSessionService.onMediaControl = (action) {
    debugPrint('🎮 处理媒体控制命令: $action');
    debugPrint('🔍 全局AppProvider: ${_globalAppProvider != null ? "有效" : "null"}');
    
    if (_globalAppProvider != null) {
      try {
        debugPrint('✅ 使用全局AppProvider实例');
        
        switch (action) {
          case 'play':
          case 'pause':
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
      
      // 停止前台服务
      if (_isForegroundServiceRunning) {
        await BackgroundService.stop();
        _isForegroundServiceRunning = false;
        debugPrint('✅ 前台服务已停止');
      }
      
      // 隐藏通知
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
