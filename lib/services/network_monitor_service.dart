import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 网络状态监控服务
class NetworkMonitorService {
  static final NetworkMonitorService _instance = NetworkMonitorService._internal();
  factory NetworkMonitorService() => _instance;
  NetworkMonitorService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription; // ✅ 修复：使用单个ConnectivityResult（兼容5.x版本）
  
  // 网络状态控制器
  final _networkStatusController = StreamController<bool>.broadcast();
  Stream<bool> get networkStatusStream => _networkStatusController.stream;
  
  // 当前网络状态
  bool _isConnected = true;
  bool get isConnected => _isConnected;
  
  // 回调函数
  Function(bool isConnected)? onNetworkChanged;
  
  // ✅ 新增：最后检查时间戳，用于防抖
  DateTime? _lastCheckTime;
  static const _checkDebounceMs = 2000; // 2秒内不重复触发

  /// 初始化网络监控
  void initialize() {
    debugPrint('🌐 初始化网络状态监控...');
    
    // 检查初始网络状态
    _checkInitialConnectivity();
    
    // ✅ 修复：监听网络状态变化（5.x版本返回单个ConnectivityResult）
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      _handleConnectivityChange(result);
    });
    
    debugPrint('✅ 网络状态监控已启动');
  }

  /// 检查初始网络连接状态
  Future<void> _checkInitialConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final hasConnection = _hasValidConnection(result);
      
      if (_isConnected != hasConnection) {
        _isConnected = hasConnection;
        _networkStatusController.add(_isConnected);
        onNetworkChanged?.call(_isConnected);
        
        debugPrint(hasConnection ? '✅ 初始网络状态：已连接' : '❌ 初始网络状态：未连接');
      }
    } catch (e) {
      debugPrint('⚠️ 检查初始网络状态失败: $e');
    }
  }

  /// 处理网络状态变化
  void _handleConnectivityChange(ConnectivityResult result) {
    // ✅ 新增：防抖检查
    final now = DateTime.now();
    if (_lastCheckTime != null) {
      final timeSinceLastCheck = now.difference(_lastCheckTime!).inMilliseconds;
      if (timeSinceLastCheck < _checkDebounceMs) {
        debugPrint('⏱️ 网络状态变化防抖: 距离上次检查仅 ${timeSinceLastCheck}ms - 忽略');
        return;
      }
    }
    _lastCheckTime = now;
    
    debugPrint('📡 网络状态变化事件: $result');
    final hasConnection = _hasValidConnection(result);
    
    debugPrint('   - 当前状态: ${_isConnected ? "已连接" : "未连接"}');
    debugPrint('   - 检测结果: ${hasConnection ? "有连接" : "无连接"}');
    debugPrint('   - ConnectivityResult: $result');
    
    if (_isConnected != hasConnection) {
      _isConnected = hasConnection;
      _networkStatusController.add(_isConnected);
      onNetworkChanged?.call(_isConnected);
      
      if (hasConnection) {
        debugPrint('✅ 网络已恢复连接');
      } else {
        debugPrint('❌ 网络已断开');
      }
    } else {
      debugPrint('ℹ️ 网络状态未变化，忽略');
    }
  }

  /// 判断是否有有效的网络连接
  bool _hasValidConnection(ConnectivityResult result) {
    // ✅ 关键改进：增加对none状态的明确判断
    return result == ConnectivityResult.mobile ||
           result == ConnectivityResult.wifi ||
           result == ConnectivityResult.ethernet ||
           result == ConnectivityResult.vpn;
  }

  /// 手动检查网络状态
  Future<bool> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final hasConnection = _hasValidConnection(result);
      
      debugPrint('🔍 手动检查网络状态: $result -> ${hasConnection ? "已连接" : "未连接"}');
      return hasConnection;
    } catch (e) {
      debugPrint('⚠️ 检查网络连接失败: $e');
      return false;
    }
  }

  /// ✅ 新增：强制立即检查网络状态（供UI调用）
  Future<bool> forceCheckConnectivity() async {
    debugPrint('🔄 强制检查网络状态...');
    return await checkConnectivity();
  }

  /// 释放资源
  void dispose() {
    _subscription?.cancel();
    _networkStatusController.close();
    debugPrint('🛑 网络状态监控已停止');
  }
}
