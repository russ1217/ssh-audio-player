import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/battery_optimization_service.dart';
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
  final _batteryService = BatteryOptimizationService();
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
    // 延迟检查电池优化，确保 UI 已加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBatteryOptimization();
    });
  }

  /// 检查电池优化并提示用户
  Future<void> _checkBatteryOptimization() async {
    try {
      debugPrint('🔍 开始电池优化检查');
      
      // 检查是否已提示过（暂时跳过，避免 SharedPreferences 问题）
      // final hasPrompted = await _batteryService.hasPrompted();
      // if (hasPrompted) return;

      // 检查电池优化状态
      debugPrint('🔍 正在检查电池优化状态...');
      final isIgnoring = await _batteryService.isIgnoringBatteryOptimizations();
      debugPrint('🔍 电池优化状态: $isIgnoring');
      if (isIgnoring) return;

      // 显示提示对话框
      if (!mounted) return;
      debugPrint('🔍 显示电池优化对话框');
      _showBatteryOptimizationDialog();
    } catch (e, stackTrace) {
      debugPrint('⚠️ 电池优化检查失败: $e');
      debugPrint('⚠️ 错误堆栈: $stackTrace');
    }
  }

  /// 显示电池优化提示对话框
  void _showBatteryOptimizationDialog() {
    // 使用 navigatorKey 的 context，确保在异步回调中也能正确获取 Navigator
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) {
      debugPrint('⚠️ Navigator context 不可用');
      return;
    }

    showDialog(
      context: navigatorContext,
      barrierDismissible: false, // 必须用户手动选择
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.battery_alert, color: Theme.of(dialogContext).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('后台播放优化'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '为了确保应用在后台播放音频时不被中断，建议关闭电池优化。',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text('设置步骤：'),
              SizedBox(height: 8),
              Text('1. 点击"去设置"按钮'),
              Text('2. 选择"无限制"或"不受限制"'),
              Text('3. 返回应用继续播放'),
              SizedBox(height: 16),
              Text(
                '提示：不同品牌手机路径略有不同，如已设置过可忽略此提示。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // 标记已提示，不再重复显示
              await _batteryService.markAsPrompted();
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('知道了'),
          ),
          FilledButton.icon(
            onPressed: () async {
              // 跳转到电池优化设置
              await _batteryService.requestIgnoreBatteryOptimizations();
              // 标记已提示
              await _batteryService.markAsPrompted();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.settings),
            label: const Text('去设置'),
          ),
        ],
      ),
    );
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
