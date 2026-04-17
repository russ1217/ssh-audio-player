import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ 初始化媒体控制监听器
  MediaSessionService.initializeMediaControlListener();
  
  runApp(const MyApp());
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
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    
    // ✅ 设置媒体控制回调
    MediaSessionService.onMediaControl = _handleMediaControl;
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

  /// ✅ 处理来自通知栏的媒体控制命令
  Future<void> _handleMediaControl(String action) async {
    debugPrint('🎮 处理媒体控制命令: $action');
    
    // 获取 AppProvider 实例
    final context = _navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ 无法获取 context，忽略控制命令');
      return;
    }
    
    final provider = context.read<AppProvider>();
    
    switch (action) {
      case 'play':
        if (!provider.isPlaying) {
          await provider.togglePlayPause();
        }
        break;
      case 'pause':
        if (provider.isPlaying) {
          await provider.togglePlayPause();
        }
        break;
      case 'stop':
        await provider.stopPlayback();
        break;
      case 'next':
        await provider.playNextInPlaylist();
        break;
      case 'previous':
        await provider.playPreviousInPlaylist();
        break;
      default:
        debugPrint('⚠️ 未知的媒体控制命令: $action');
    }
  }

  /// 停止前台服务和播放器
  Future<void> _stopForegroundServiceAndPlayer() async {
    debugPrint('🛑 应用被销毁，停止前台服务和播放器...');
    
    try {
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
      create: (_) => AppProvider(),
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
