import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initApp() async {
    await _notificationService.init();
    debugPrint('✅ 应用初始化完成，使用前台服务机制保持后台播放');
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
