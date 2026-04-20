import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 网络状态监控服务
class NetworkMonitorService {
  static final NetworkMonitorService _instance = NetworkMonitorService._internal();
  factory NetworkMonitorService() => _instance;
  NetworkMonitorService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  
  // 网络状态控制器
  final _networkStatusController = StreamController<bool>.broadcast();
  Stream<bool> get networkStatusStream => _networkStatusController.stream;
  
  // 当前网络状态
  bool _isConnected = true;
  bool get isConnected => _isConnected;
  
  // 回调函数
  Function(bool isConnected)? onNetworkChanged;

  /// 初始化网络监控
  void initialize() {
    debugPrint('🌐 初始化网络状态监控...');
    
    // 检查初始网络状态
    _checkInitialConnectivity();
    
    // 监听网络状态变化
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _handleConnectivityChange(results);
    });
    
    debugPrint('✅ 网络状态监控已启动');
  }

  /// 检查初始网络连接状态
  Future<void> _checkInitialConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final hasConnection = _hasValidConnection(results);
      
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
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final hasConnection = _hasValidConnection(results);
    
    if (_isConnected != hasConnection) {
      _isConnected = hasConnection;
      _networkStatusController.add(_isConnected);
      onNetworkChanged?.call(_isConnected);
      
      if (hasConnection) {
        debugPrint('✅ 网络已恢复连接');
      } else {
        debugPrint('❌ 网络已断开');
      }
    }
  }

  /// 判断是否有有效的网络连接
  bool _hasValidConnection(List<ConnectivityResult> results) {
    return results.any((result) => 
      result == ConnectivityResult.mobile ||
      result == ConnectivityResult.wifi ||
      result == ConnectivityResult.ethernet ||
      result == ConnectivityResult.vpn
    );
  }

  /// 手动检查网络状态
  Future<bool> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasValidConnection(results);
    } catch (e) {
      debugPrint('⚠️ 检查网络连接失败: $e');
      return false;
    }
  }

  /// 释放资源
  void dispose() {
    _subscription?.cancel();
    _networkStatusController.close();
    debugPrint('🛑 网络状态监控已停止');
  }
}
