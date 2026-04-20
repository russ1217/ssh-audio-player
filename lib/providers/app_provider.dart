import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:path_provider/path_provider.dart';
import '../models/ssh_config.dart';
import '../models/media_file.dart';
import '../models/playlist.dart';
import '../services/ssh_service.dart';
import '../services/database_service.dart';
import '../services/audio_player_service.dart';
import '../services/audio_player_base.dart';
import '../services/timer_service.dart';
import '../services/streaming_audio_service.dart';
import '../services/background_service.dart';
import '../services/storage_permission_service.dart';
import '../services/network_monitor_service.dart';

class AppProvider extends ChangeNotifier {
  final SSHService _sshService = SSHService();
  final DatabaseService _databaseService = DatabaseService();
  final AudioPlayerServiceBase _audioPlayerService = createAudioPlayerService();
  final StreamingAudioService _streamingService = StreamingAudioService();
  final TimerService _timerService = TimerService();
  final StoragePermissionService _permissionService = StoragePermissionService();
  final NetworkMonitorService _networkMonitor = NetworkMonitorService();

  // ✅ 新增：本地文件模式标志
  bool _isLocalMode = false; // true=本地文件, false=SSH远程文件

  // SSH 状态
  List<SSHConfig> _sshConfigs = [];
  SSHConfig? _activeSSHConfig;
  bool _isSSHConnected = false;

  // 文件浏览
  List<MediaFile> _currentFiles = [];
  String _currentPath = '/';
  bool _isLoading = false;
  
  // ✅ 新增：用于强制刷新文件列表的计数器
  int _refreshCounter = 0;

  // Getters
  bool get isLocalMode => _isLocalMode;

  // 播放列表
  String? _currentPlaylistId; // ✅ 当前播放列表ID，用于按列表记录断点
  List<MediaFile> _playlist = [];
  int _currentIndex = 0;
  MediaFile? _currentPlayingFile; // 当前正在播放的文件

  // 后台预下载
  final Map<String, String> _downloadCache = {}; // 文件路径 -> 本地路径
  bool _isPredownloading = false;
  int _predownloadIndex = -1;
  int _predownloadMaxIndex = 0; // 预下载的最大索引

  // 播放器状态
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastPositionForStateCheck = Duration.zero; // ✅ 用于智能判断播放状态的上一次位置

  // Getters
  SSHService get sshService => _sshService;
  DatabaseService get databaseService => _databaseService;
  AudioPlayerServiceBase get audioPlayerService => _audioPlayerService;
  TimerService get timerService => _timerService;

  List<SSHConfig> get sshConfigs => _sshConfigs;
  SSHConfig? get activeSSHConfig => _activeSSHConfig;
  bool get isSSHConnected => _isSSHConnected;
  List<MediaFile> get currentFiles => _currentFiles;
  String get currentPath => _currentPath;
  bool get isLoading => _isLoading;
  int get refreshCounter => _refreshCounter;
  List<MediaFile> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  MediaFile? get currentPlayingFile => _currentPlayingFile;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;

  AppProvider() {
    _init();
    _setupStreamingServiceListener();
    _setupNetworkMonitor();
  }

  Future<void> _init() async {
    await _loadSSHConfigs();
    _setupSSHHeartbeatListener();
    _setupAudioPlayerListeners();
    _setupTimerListeners();
    // ✅ 移除：不再在初始化时恢复播放位置，改为在打开播放列表时恢复
    // _restoreLastPlayedPosition();
  }

  /// 设置网络状态监控
  void _setupNetworkMonitor() {
    debugPrint('🌐 设置网络状态监控...');
    
    // 初始化网络监控服务
    _networkMonitor.initialize();
    
    // 监听网络状态变化
    _networkMonitor.onNetworkChanged = (isConnected) {
      debugPrint('🔄 网络状态变化: ${isConnected ? "已连接" : "已断开"}');
      
      if (!isConnected) {
        // 网络断开
        _handleNetworkDisconnected();
      } else {
        // 网络恢复
        _handleNetworkReconnected();
      }
    };
    
    debugPrint('✅ 网络状态监控已设置');
  }

  /// 处理网络断开
  void _handleNetworkDisconnected() {
    debugPrint('⚠️ 网络已断开，保存播放状态...');
    
    // 如果正在播放且是SSH模式，保存当前播放状态
    if (_isPlaying && !_isLocalMode && _currentPlayingFile != null) {
      debugPrint('💾 网络断开，保存播放进度以备恢复');
      // SSH心跳检测会自动处理重连，这里只做标记
      _shouldResumeAfterReconnect = true;
    }
  }

  /// 处理网络恢复
  Future<void> _handleNetworkReconnected() async {
    debugPrint('✅ 网络已恢复，检查是否需要重连和恢复播放...');
    
    // 如果之前应该恢复播放，但现在SSH未连接，尝试重新连接
    if (_shouldResumeAfterReconnect && !_sshService.isConnected && _activeSSHConfig != null) {
      debugPrint('🔄 网络恢复，尝试重新连接SSH...');
      
      try {
        final success = await _sshService.reconnect().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('SSH 重连超时');
          },
        );
        
        if (success) {
          debugPrint('✅ SSH 重连成功，准备恢复播放');
          _isSSHConnected = true;
          notifyListeners();
          
          // 延迟一下确保连接稳定
          await Future.delayed(const Duration(milliseconds: 500));
          
          // 恢复播放
          await _resumePlaybackAfterReconnect();
        } else {
          debugPrint('❌ SSH 重连失败');
          _isSSHConnected = false;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('❌ SSH 重连异常: $e');
        _isSSHConnected = false;
        _shouldResumeAfterReconnect = false;
        _isAutoResuming = false;
        notifyListeners();
      }
    } else if (_sshService.isConnected) {
      debugPrint('✅ SSH 连接正常，无需重连');
      _isSSHConnected = true;
      notifyListeners();
    }
  }

  /// 设置流式服务 SSH 断开监听
  void _setupStreamingServiceListener() {
    _streamingService.onSshDisconnected = () {
      debugPrint('🔄 流式服务检测到 SSH 断开，准备恢复播放...');
      // 流式服务的 SSH 断开，触发自动恢复
      if (_isPlaying && _currentPlayingFile != null) {
        _autoResumePlayback();
      }
    };
  }

  /// 确保 SSH 连接有效（自动重连）
  Future<bool> _ensureSSHConnection() async {
    if (!_sshService.isConnected) {
      if (_activeSSHConfig != null) {
        debugPrint('🔄 SSH 未连接，尝试重连...');
        return await _sshService.reconnect();
      }
      return false;
    }

    final isValid = await _sshService.checkConnection();
    if (!isValid && _activeSSHConfig != null) {
      debugPrint('🔄 SSH 连接已失效，尝试重连...');
      return await _sshService.reconnect();
    }

    return isValid;
  }

  /// 设置 SSH 心跳检测监听
  void _setupSSHHeartbeatListener() {
    _sshService.connectionStatusStream.listen((isConnected) {
      _isSSHConnected = isConnected;
      if (!isConnected) {
        debugPrint('⚠️ SSH 连接已断开');
        // SSH 断开时，如果正在使用流式播放，尝试自动恢复
        if (_isPlaying && _currentPlayingFile != null && !_isAutoResuming) {
          debugPrint('🔄 心跳检测：SSH 断开，自动恢复播放');
          _autoResumePlayback();
        }
      } else {
        debugPrint('✅ SSH 连接已恢复');
        // SSH 重连成功后，如果之前正在播放，自动恢复播放
        if (_shouldResumeAfterReconnect) {
          debugPrint('🔄 心跳检测：SSH 已恢复，自动恢复播放...');
          _resumePlaybackAfterReconnect();
        }
      }
      notifyListeners();
    });
  }

  // 自动恢复播放相关
  bool _shouldResumeAfterReconnect = false;
  Duration? _playbackPositionBeforeDisconnect;
  bool _isAutoResuming = false; // 防抖标志

  /// SSH 断开时保存播放状态
  Future<void> _autoResumePlayback() async {
    if (_isAutoResuming) {
      debugPrint('⚠️ 已经在自动恢复中，忽略重复请求');
      return;
    }
    
    _isAutoResuming = true;
    _shouldResumeAfterReconnect = true;
    _playbackPositionBeforeDisconnect = _audioPlayerService.currentPosition;
    debugPrint('💾 保存播放进度: ${_playbackPositionBeforeDisconnect}');
    
    // 停止当前播放（因为 SSH 已断开，流式服务无法工作）
    try {
      await _audioPlayerService.stop();
      await _streamingService.stop();
    } catch (e) {
      debugPrint('⚠️ 停止播放异常（可忽略）: $e');
    }
    _isPlaying = false;
    
    // 主动触发 SSH 重连（不等心跳检测）
    if (_activeSSHConfig != null) {
      debugPrint('🔄 主动触发 SSH 重连...');
      // 后台重试，不阻塞当前流程
      _retrySshReconnect();
    } else {
      debugPrint('❌ 没有活动的 SSH 配置，无法重连');
      _isAutoResuming = false;
    }
  }

  /// 后台重试 SSH 重连（最多5次，间隔10秒）
  Future<void> _retrySshReconnect() async {
    const maxAttempts = 5;
    const retryInterval = Duration(seconds: 10);
    
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint('🔄 SSH 重连尝试 ($attempt/$maxAttempts)...');
        final success = await _sshService.reconnect().timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            throw TimeoutException('SSH 连接超时');
          },
        );
        
        if (success) {
          debugPrint('✅ SSH 重连成功（尝试 $attempt 次）');
          // 重连成功，立即恢复播放
          await _resumePlaybackAfterReconnect();
          return;
        } else {
          debugPrint('❌ SSH 重连失败（尝试 $attempt/$maxAttempts）');
        }
      } catch (e) {
        debugPrint('❌ SSH 重连异常（尝试 $attempt/$maxAttempts）: $e');
      }
      
      // 如果不是最后一次尝试，等待后重试
      if (attempt < maxAttempts) {
        debugPrint('⏳ ${retryInterval.inSeconds}秒后重试...');
        await Future.delayed(retryInterval);
      }
    }
    
    debugPrint('⛔ SSH 重连失败（已尝试 $maxAttempts 次），请手动重连');
    _isAutoResuming = false;
    _shouldResumeAfterReconnect = false;
  }

  /// SSH 重连成功后恢复播放
  Future<void> _resumePlaybackAfterReconnect() async {
    if (_currentPlayingFile == null) {
      _shouldResumeAfterReconnect = false;
      _isAutoResuming = false;
      return;
    }

    try {
      debugPrint('🔄 正在恢复播放: ${_currentPlayingFile!.name}');
      
      final file = _currentPlayingFile!;
      
      // ✅ 更新 MediaSession 元数据（蓝牙设备显示曲目名称）
      _updateMediaSessionMetadata(file);
      
      // ✅ 关键修复：统一使用流式播放，不再区分文件大小
      debugPrint('🌐 重新启动流式服务...');
      await _playMediaStreaming(file);

      // 恢复播放进度
      if (_playbackPositionBeforeDisconnect != null && _playbackPositionBeforeDisconnect! > Duration.zero) {
        // 等待播放器加载完成
        await Future.delayed(const Duration(milliseconds: 500));
        await _audioPlayerService.seek(_playbackPositionBeforeDisconnect!);
        debugPrint('⏩ 恢复到进度: $_playbackPositionBeforeDisconnect');
      }

      _shouldResumeAfterReconnect = false;
      _playbackPositionBeforeDisconnect = null;
      _isAutoResuming = false;
      _isPlaying = true;
      
      // ✅ 更新 MediaSession 播放状态为播放中
      _updateMediaSessionPlaybackState(isPlaying: true);
      
      debugPrint('✅ 播放已恢复');
    } catch (e) {
      debugPrint('❌ 恢复播放失败: $e');
      _shouldResumeAfterReconnect = false;
      _isAutoResuming = false;
      rethrow;
    }
  }

  void _setupAudioPlayerListeners() {
    _audioPlayerService.playbackStateStream.listen((state) {
      // ✅ 最简单直接的方案：监听器根据实际播放器状态更新 _isPlaying
      // 不要有任何复杂的判断逻辑，相信底层播放器的状态
      final wasPlaying = _isPlaying;
      
      if (state == PlayerState.playing) {
        _isPlaying = true;
      } else if (state == PlayerState.paused || state == PlayerState.completed || state == PlayerState.idle) {
        _isPlaying = false;
      }
      // loading/buffering 状态不改变 _isPlaying
      
      if (wasPlaying != _isPlaying) {
        debugPrint('📊 播放器状态变化: $state, isPlaying: $wasPlaying → $_isPlaying');
      } else {
        debugPrint('📊 播放器状态: $state, isPlaying: $_isPlaying (无变化)');
      }
      
      _lastPositionForStateCheck = _audioPlayerService.currentPosition;
      
      // ✅ 更新 MediaSession 播放状态
      _updateMediaSessionPlaybackState(isPlaying: _isPlaying);
      
      notifyListeners();
    });

    _audioPlayerService.positionStream.listen((position) {
      _position = position;
      
      // ✅ 定期更新 MediaSession 位置（每秒更新一次，避免频繁调用）
      if (_isPlaying && position.inSeconds % 1 == 0) {
        _updateMediaSessionPosition();
      }
      
      notifyListeners();
    });

    _audioPlayerService.durationStream.listen((duration) {
      _duration = duration;
      notifyListeners();
    });

    _audioPlayerService.currentIndexStream.listen((index) {
      _currentIndex = index;
      notifyListeners();
    });

    _audioPlayerService.completeStream.listen((_) {
      _onFileComplete();
    });
  }

  void _setupTimerListeners() {
    _timerService.timerCompleteStream.listen((type) {
      _onTimerComplete(type);
    });
  }

  void _onFileComplete() {
    _timerService.incrementPlayedFiles();
    playNextInPlaylist();
  }

  void _onTimerComplete(TimerType type) {
    _audioPlayerService.stop();
    _isPlaying = false;
    notifyListeners();
  }

  // SSH 配置管理
  Future<void> _loadSSHConfigs() async {
    try {
      _sshConfigs = await _databaseService.getSSHConfigs();
      notifyListeners();
    } catch (e) {
      debugPrint('加载 SSH 配置失败: $e');
    }
  }

  /// 恢复上次播放位置

  Future<void> addSSHConfig(SSHConfig config) async {
    await _databaseService.insertSSHConfig(config);
    await _loadSSHConfigs();
  }

  Future<void> updateSSHConfig(SSHConfig config) async {
    await _databaseService.updateSSHConfig(config);
    await _loadSSHConfigs();
  }

  Future<void> deleteSSHConfig(String id) async {
    await _databaseService.deleteSSHConfig(id);
    if (_activeSSHConfig?.id == id) {
      await disconnectSSH();
    }
    await _loadSSHConfigs();
  }

  /// ✅ 强制重置加载状态（用于修复UI卡住的问题）
  void resetLoadingState() {
    if (_isLoading) {
      debugPrint('⚠️ 强制重置加载状态');
      _isLoading = false;
      notifyListeners();
    }
  }

  // SSH 连接管理
  Future<bool> connectSSH(SSHConfig config) async {
    try {
      _isLoading = true;
      notifyListeners();

      final success = await _sshService.connect(config);
      if (success) {
        _activeSSHConfig = config;
        _isSSHConnected = true;
        _currentPath = config.initialPath ?? '/';
        await _loadCurrentDirectory();
      }
      return success;
    } catch (e) {
      debugPrint('SSH 连接失败: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> disconnectSSH() async {
    await _sshService.disconnect();
    _activeSSHConfig = null;
    _isSSHConnected = false;
    
    // 如果当前不是本地模式，则清空文件列表
    if (!_isLocalMode) {
      _currentFiles.clear();
      _currentPath = '/';
    }
    
    notifyListeners();
  }

  /// ✅ 切换到本地文件模式
  Future<bool> switchToLocalMode() async {
    if (_isLocalMode) return true;
    
    debugPrint('🔄 切换到本地文件模式');
    
    // ✅ 请求存储权限
    final hasPermission = await _permissionService.ensureStoragePermission();
    if (!hasPermission) {
      debugPrint('❌ 存储权限被拒绝，无法切换到本地模式');
      return false;
    }
    
    _isLocalMode = true;
    
    // ✅ 设置默认可访问的公共目录
    // 优先级：Download > Music > 应用专属目录
    try {
      // 首先尝试常用的公共目录
      final downloadDir = Directory('/storage/emulated/0/Download');
      final musicDir = Directory('/storage/emulated/0/Music');
      
      if (await downloadDir.exists()) {
        _currentPath = '/storage/emulated/0/Download';
        debugPrint('✅ 使用Download目录: $_currentPath');
      } else if (await musicDir.exists()) {
        _currentPath = '/storage/emulated/0/Music';
        debugPrint('✅ 使用Music目录: $_currentPath');
      } else {
        // 回退到内部存储根目录
        _currentPath = '/storage/emulated/0';
        debugPrint('⚠️ 使用内部存储根目录: $_currentPath');
      }
    } catch (e) {
      debugPrint('⚠️ 检查目录失败: $e，使用默认路径');
      _currentPath = '/storage/emulated/0';
    }
    
    await _loadCurrentDirectory();
    notifyListeners();
    return true;
  }
  
  /// ✅ 切换到SSH远程模式
  Future<void> switchToSSHMode() async {
    if (!_isLocalMode) return;
    
    debugPrint('🔄 切换到SSH远程模式');
    _isLocalMode = false;
    
    // ✅ 修复：根据SSH配置设置初始路径
    if (_activeSSHConfig != null) {
      _currentPath = _activeSSHConfig!.initialPath ?? '/';
      debugPrint('📍 使用SSH配置的初始路径: $_currentPath');
    } else {
      _currentPath = '/';
      debugPrint('📍 无SSH配置，使用根目录');
    }
    
    // 如果SSH已连接，加载当前目录
    if (_isSSHConnected) {
      await _loadCurrentDirectory();
    } else {
      _currentFiles.clear();
      debugPrint('⚠️ SSH未连接，显示空列表');
    }
    
    notifyListeners();
  }

  /// ✅ 新增：强制刷新当前目录（用于Tab切换时）
  Future<void> forceRefreshCurrentDirectory() async {
    debugPrint('🔄 强制刷新当前目录: $_currentPath (本地模式: $_isLocalMode, SSH连接: $_isSSHConnected)');
    
    // ✅ 关键修复：如果loading状态异常卡住，无论文件列表是否为空，都强制重置
    if (_isLoading) {
      debugPrint('⚠️ 检测到异常的loading状态，强制重置');
      _isLoading = false;
      notifyListeners();
    }
    
    // 增加刷新计数器，触发UI重新构建
    _refreshCounter++;
    
    // 如果文件列表为空，主动加载目录
    if (_currentFiles.isEmpty) {
      debugPrint('📂 文件列表为空，重新加载目录');
      await _loadCurrentDirectory();
    } else {
      debugPrint('✅ 文件列表已有数据，仅通知UI刷新');
      notifyListeners();
    }
  }

  // 文件浏览
  Future<void> _loadCurrentDirectory() async {
    // ✅ 关键修复：如果已经在加载中，避免重复加载
    if (_isLoading) {
      debugPrint('⚠️ 目录正在加载中，跳过重复请求');
      return;
    }
    
    // 如果是本地模式，不需要 SSH 连接
    if (!_isLocalMode && !_isSSHConnected) {
      debugPrint('⚠️ 未连接任何模式（本地/SSH），无法加载目录');
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();
      
      debugPrint('📂 开始加载目录: $_currentPath (本地模式: $_isLocalMode)');

      if (_isLocalMode) {
        // ✅ 本地文件模式加载逻辑
        debugPrint('📁 加载本地目录: $_currentPath');
        await Future.delayed(Duration.zero);
        
        try {
          final directory = Directory(_currentPath);
          
          if (!await directory.exists()) {
            debugPrint('❌ 目录不存在: $_currentPath');
            _currentFiles = [];
            
            // 尝试回退到根目录
            if (_currentPath != '/storage/emulated/0') {
              debugPrint('🔄 尝试回退到内部存储根目录...');
              _currentPath = '/storage/emulated/0';
              await _loadCurrentDirectory();
              return;
            }
            notifyListeners();
            return;
          }
          
          // 检查读取权限
          try {
            await directory.list().first.timeout(Duration(seconds: 2));
          } catch (e) {
            debugPrint('❌ 无权限读取目录: $e');
            _currentFiles = [];
            notifyListeners();
            return;
          }
          
          // 列出所有文件和文件夹
          final entities = await directory.list().toList();
          debugPrint('📊 找到 ${entities.length} 个项目');
          
          _currentFiles = entities.map((entity) {
            try {
              final stat = entity.statSync();
              final isDir = stat.type == FileSystemEntityType.directory;
              
              // ✅ 正确提取文件名：从完整路径中提取最后一部分
              final fileName = entity.path.split('/').lastWhere(
                (segment) => segment.isNotEmpty,
                orElse: () => entity.path,
              );
              
              debugPrint('📄 文件: path=${entity.path}, name=$fileName, isDir=$isDir');
              
              return MediaFile(
                path: entity.path,
                name: fileName,
                isDirectory: isDir,
                size: isDir ? null : stat.size,
                sourceType: FileSourceType.local, // ✅ 明确标识为本地文件
              );

            } catch (e) {
              debugPrint('⚠️ 跳过无法访问的项目: ${entity.path}, 错误: $e');
              // 返回一个占位对象或跳过
              return null;
            }
          }).whereType<MediaFile>().toList(); // 过滤掉null值
          
          debugPrint('✅ 成功加载 ${_currentFiles.length} 个有效项目');
          
        } catch (e, stackTrace) {
          debugPrint('❌ 加载本地目录失败: $e');
          debugPrint('📚 堆栈: $stackTrace');
          _currentFiles = [];
        }
      } else {
        // ✅ SSH 远程模式加载逻辑
        // 在加载目录前确保 SSH 连接有效
        final isConnected = await _ensureSSHConnection();
        if (!isConnected) {
          _isSSHConnected = false;
          _currentFiles = [];
          debugPrint('❌ SSH 连接失败，无法加载目录');
          return;
        }

        // ✅ 关键修复：将耗时的SSH操作放到后台执行，避免阻塞UI线程
        await Future.delayed(Duration.zero);
        
        final sshFiles = await _sshService.listDirectory(_currentPath);
        
        // ✅ 关键修复：将SSH获取的文件标记为远程文件
        _currentFiles = sshFiles.map((file) => MediaFile(
          path: file.path,
          name: file.name,
          isDirectory: file.isDirectory,
          size: file.size,
          modified: file.modified,
          duration: file.duration,
          sourceType: FileSourceType.ssh, // ✅ 明确标识为SSH远程文件
        )).toList();
      }
      
      // ✅ 排序操作也可能耗时，让出控制权
      await Future.delayed(Duration.zero);
      
      // 排序：目录在前，文件在后
      _currentFiles.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.compareTo(b.name);
      });
      
      debugPrint('✅ 目录加载完成，共 ${_currentFiles.length} 个项目');
    } catch (e) {
      debugPrint('❌ 加载目录失败: $e');
      _currentFiles = [];
    } finally {
      _isLoading = false;
      notifyListeners();
      debugPrint('🏁 目录加载流程结束，isLoading=false');
    }
  }

  Future<void> navigateTo(String path) async {
    _currentPath = path;
    await _loadCurrentDirectory();
  }

  Future<void> navigateToParent() async {
    if (_currentPath == '/' || _currentPath.isEmpty) {
      _currentPath = '/';
      return;
    }

    // 移除末尾的斜杠（如果有）
    String cleanPath = _currentPath.endsWith('/') 
        ? _currentPath.substring(0, _currentPath.length - 1) 
        : _currentPath;
    
    final parts = cleanPath.split('/');
    parts.removeLast();
    _currentPath = parts.isEmpty ? '/' : parts.join('/');
    await _loadCurrentDirectory();
  }

  // 播放控制
  Future<void> playMedia(MediaFile file, {bool syncPlaylistIndex = true}) async {
    debugPrint('🎬 ========== playMedia 开始 ==========');
    debugPrint('📄 文件: ${file.name}');
    debugPrint('📍 路径: ${file.path}');
    debugPrint('🎵 isMedia: ${file.isMedia}');
    debugPrint('📂 isAudio: ${file.isAudio}, isVideo: ${file.isVideo}');

    if (!file.isMedia) {
      debugPrint('❌ 文件不是媒体文件，跳过播放');
      return;
    }

    // ✅ 关键修复：确保前台服务已启动（首次播放时）
    await _ensureForegroundServiceStarted();

    // 如果文件在播放列表中，同步 currentIndex（仅当 syncPlaylistIndex 为 true 时）
    if (syncPlaylistIndex) {
      final playlistIndex = _playlist.indexWhere((f) => f.path == file.path);
      if (playlistIndex >= 0) {
        debugPrint('🔗 文件在播放列表中，同步索引: $playlistIndex');
        _currentIndex = playlistIndex;
      }
    }

    debugPrint('▶️ playMedia 调用: 文件=${file.name}, 当前 _currentIndex=$_currentIndex, _playlist 长度=${_playlist.length}');

    try {
      _isLoading = true;
      _currentPlayingFile = file;
      notifyListeners();

      // ✅ 更新 MediaSession 元数据（蓝牙设备显示曲目名称）
      _updateMediaSessionMetadata(file);

      // ✅ 关键修复：根据模式选择播放方式
      if (_isLocalMode) {
        // 本地文件模式：直接播放本地文件
        debugPrint('📁 本地模式：直接播放文件 ${file.path}');
        await _audioPlayerService.playFile(file.path, isVideo: file.isVideo);
      } else {
        // SSH远程模式：使用流式播放
        debugPrint('🌐 SSH模式：启动 HTTP 流式服务...');
        await _playMediaStreaming(file);
      }

      // 等待播放器就绪（解决首次播放无声问题）
      final isReady = await _waitForPlayerReady(timeout: const Duration(seconds: 15));
      
      if (isReady) {
        _isPlaying = true;
        debugPrint('✅ 播放完成设置: _currentIndex=$_currentIndex');
        
        // ✅ 更新播放状态为播放中
        _updateMediaSessionPlaybackState(isPlaying: true);
        
        // ✅ 关键修复：由于统一使用流式播放，不再需要预下载
        // 流式播放会边下边播，预下载已无意义
        debugPrint('📌 使用${_isLocalMode ? "本地" : "流式"}播放，无需预下载');
      } else {
        debugPrint('⚠️ 播放器未就绪，尝试重新播放');
        await _audioPlayerService.play();
        final retryReady = await _waitForPlayerReady(timeout: const Duration(seconds: 5));
        _isPlaying = retryReady;
        
        // ✅ 更新播放状态
        _updateMediaSessionPlaybackState(isPlaying: retryReady);
      }
      
      // 保存播放位置
      await _saveCurrentPlaybackPosition();
    } catch (e, stackTrace) {
      debugPrint('❌ 播放失败: $e');
      debugPrint('📚 堆栈: $stackTrace');
      _isPlaying = false;
      
      // ✅ 播放失败时更新状态为暂停
      _updateMediaSessionPlaybackState(isPlaying: false);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 大文件：真正的流式下载边下边播（现在所有文件都用这个方法）
  Future<void> _playMediaStreaming(MediaFile file) async {
    debugPrint('🌐 启动 HTTP 流式服务...');

    final fileSize = file.size ?? await _sshService.getFileSize(file.path) ?? 0;

    // 启动流式服务（使用独立的 SSH 连接）
    final streamUrl = await _streamingService.startStreaming(
      sshClient: _sshService.getClient()!,
      remotePath: file.path,
      fileSize: fileSize,
      createNewSshClient: _sshService.createNewConnection,
    );

    debugPrint('🎵 开始播放流式媒体: $streamUrl');
    final isVideo = file.isVideo;
    await _audioPlayerService.playUrl(streamUrl, isVideo: isVideo);
  }

  /// 开始后台预下载（最多预下载当前曲目后3个）
  void _startPredownloading() {
    if (_isPredownloading) {
      debugPrint('⚠️ 预下载正在进行中，跳过');
      return;
    }
    
    // 计算需要预下载的范围：从 currentIndex + 1 开始，最多3个
    final startDownloadIndex = _currentIndex + 1;
    final maxDownloadIndex = startDownloadIndex + 3; // 最多下载后面3个
    
    if (startDownloadIndex >= _playlist.length) {
      debugPrint('✅ 已经是最后一个曲目，无需预下载');
      return;
    }
    
    _predownloadIndex = startDownloadIndex;
    _predownloadMaxIndex = maxDownloadIndex.clamp(0, _playlist.length);
    debugPrint('🚀 开始预下载: 索引 $_predownloadIndex 到 $_predownloadMaxIndex');
    _predownloadNext();
  }

  /// 预下载下一个文件（限制最多3个）
  Future<void> _predownloadNext() async {
    // 检查是否超出预下载范围或播放列表范围
    if (_predownloadIndex >= _predownloadMaxIndex || _predownloadIndex >= _playlist.length) {
      _isPredownloading = false;
      debugPrint('✅ 预下载完成（已达到限制）');
      return;
    }

    _isPredownloading = true;
    final nextFile = _playlist[_predownloadIndex];

    // 检查是否已缓存
    if (_downloadCache.containsKey(nextFile.path)) {
      debugPrint('✅ 文件已缓存: ${nextFile.name} (索引: $_predownloadIndex)');
      _predownloadIndex++;
      _isPredownloading = false;
      _predownloadNext();
      return;
    }

    try {
      debugPrint('⬇️ 后台预下载: ${nextFile.name} (索引: $_predownloadIndex/$_predownloadMaxIndex)');
      final fileData = await _sshService.readFile(nextFile.path);
      final tempFile = await _createTempFile(fileData, nextFile.name);
      _downloadCache[nextFile.path] = tempFile.path;
      debugPrint('✅ 预下载完成: ${nextFile.name}');

      // 继续下载下一个
      _predownloadIndex++;
      _isPredownloading = false;
      _predownloadNext();
    } catch (e) {
      debugPrint('❌ 预下载失败: ${nextFile.name}: $e');
      _isPredownloading = false;
    }
  }

  /// 停止预下载
  void _stopPredownloading() {
    _isPredownloading = false;
    _predownloadIndex = -1;
    _predownloadMaxIndex = 0;
  }

  /// 等待播放器就绪（解决首次播放无声问题）
  Future<bool> _waitForPlayerReady({Duration timeout = const Duration(seconds: 10)}) async {
    final startTime = DateTime.now();
    
    // ✅ 关键修复：优先使用 processingStateStream 监听（更可靠）
    try {
      final completer = Completer<bool>();
      StreamSubscription? subscription;
      
      subscription = _audioPlayerService.playbackStateStream.listen((state) {
        debugPrint('📊 等待就绪 - 当前状态: $state, isPlaying: ${_audioPlayerService.isPlaying}');
        
        // 当状态变为 playing 且位置有进展时，认为就绪
        if (state == PlayerState.playing && _audioPlayerService.currentPosition >= Duration.zero) {
          if (!completer.isCompleted) {
            debugPrint('✅ 播放器已就绪 (状态: $state, 位置: ${_audioPlayerService.currentPosition})');
            completer.complete(true);
          }
        }
      });
      
      // 设置超时
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          debugPrint('⚠️ 等待播放器就绪超时 (${timeout.inSeconds}秒)，尝试兜底检查');
          
          // 兜底：轮询检查
          subscription?.cancel();
          
          // 即使 position 为 0，只要 isPlaying 为 true 也认为成功
          if (_audioPlayerService.isPlaying) {
            debugPrint('✅ 兜底检查通过: isPlaying=true');
            completer.complete(true);
          } else {
            completer.complete(false);
          }
        }
      });
      
      final result = await completer.future;
      subscription?.cancel();
      timer.cancel();
      return result;
    } catch (e) {
      debugPrint('⚠️ 监听播放状态失败: $e，使用兜底轮询');
      
      // 兜底方案：轮询检查
      while (DateTime.now().difference(startTime) < timeout) {
        // 直接检查播放器的实际状态
        if (_audioPlayerService.isPlaying) {
          debugPrint('✅ 播放器已就绪 (位置: ${_audioPlayerService.currentPosition})');
          return true;
        }
        
        // 短暂等待后再次检查
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      debugPrint('⚠️ 等待播放器就绪超时 (${timeout.inSeconds}秒)');
      return false;
    }
  }

  Future<void> togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayerService.pause();
        _isPlaying = false;
        debugPrint('⏸️ 已调用 pause()，_isPlaying = false');
        
        // ✅ 更新 MediaSession 播放状态为暂停
        _updateMediaSessionPlaybackState(isPlaying: false);
      } else {
        await _audioPlayerService.play();
        _isPlaying = true;
        debugPrint('▶️ 已调用 play()，_isPlaying = true');
        
        // ✅ 更新 MediaSession 播放状态为播放中
        _updateMediaSessionPlaybackState(isPlaying: true);
      }
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> stopPlayback() async {
    debugPrint('🛑 开始停止播放...');
    
    await _audioPlayerService.stop();
    await _streamingService.stop();
    
    _isPlaying = false;
    _currentPlayingFile = null;
    _stopPredownloading();
    
    // ✅ 更新 MediaSession 播放状态为停止
    _updateMediaSessionPlaybackState(isPlaying: false);
    
    // ✅ 关键修复：停止后台前台服务，防止杀掉app后继续播放
    try {
      await BackgroundService.stop();
      debugPrint('🛑 后台服务已停止');
    } catch (e) {
      debugPrint('⚠️ 停止后台服务失败: $e');
    }
    
    notifyListeners();
    debugPrint('✅ 停止播放完成');
  }

  Future<void> seekTo(Duration position) async {
    await _audioPlayerService.seek(position);
  }

  Future<void> seekForward(Duration duration) async {
    await _audioPlayerService.seekForward(duration);
  }

  Future<void> seekBackward(Duration duration) async {
    await _audioPlayerService.seekBackward(duration);
  }

  // 播放列表管理
  Future<void> addToPlaylist(MediaFile file) async {
    if (!file.isMedia) return;
    _playlist.add(file);
    notifyListeners();
  }

  Future<void> addDirectoryToPlaylist(String path) async {
    // ✅ 修复：支持本地模式和SSH模式
    if (!_isLocalMode && !_isSSHConnected) {
      debugPrint('❌ 未连接到SSH服务器且不在本地模式');
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      List<MediaFile> files;
      
      if (_isLocalMode) {
        // ✅ 本地模式：使用Dart Directory API
        debugPrint('📁 本地模式：扫描目录 $path');
        await Future.delayed(Duration.zero);
        
        final directory = Directory(path);
        if (!await directory.exists()) {
          debugPrint('❌ 目录不存在: $path');
          _isLoading = false;
          notifyListeners();
          return;
        }
        
        final entities = await directory.list().toList();
        files = entities.map((entity) {
          try {
            final stat = entity.statSync();
            final isDir = stat.type == FileSystemEntityType.directory;
            final fileName = entity.path.split('/').lastWhere(
              (segment) => segment.isNotEmpty,
              orElse: () => entity.path,
            );
            
            return MediaFile(
              path: entity.path,
              name: fileName,
              isDirectory: isDir,
              size: isDir ? null : stat.size,
              sourceType: FileSourceType.local, // ✅ 明确标识为本地文件
            );
          } catch (e) {
            debugPrint('⚠️ 跳过无法访问的项目: ${entity.path}');
            return null;
          }
        }).whereType<MediaFile>().toList();
        
        debugPrint('📊 本地目录扫描完成，找到 ${files.length} 个项目');
      } else {
        // ✅ SSH模式：使用SSH服务
        debugPrint('🌐 SSH模式：扫描目录 $path');
        await Future.delayed(Duration.zero);
        files = await _sshService.listDirectory(path);
        
        // ✅ 关键修复：将SSH获取的文件标记为远程文件
        files = files.map((file) => MediaFile(
          path: file.path,
          name: file.name,
          isDirectory: file.isDirectory,
          size: file.size,
          modified: file.modified,
          duration: file.duration,
          sourceType: FileSourceType.ssh, // ✅ 明确标识为SSH远程文件
        )).toList();
      }
      
      final mediaFiles = files.where((f) => f.isMedia).toList();
      mediaFiles.sort((a, b) => a.name.compareTo(b.name));
      
      debugPrint('🎵 发现 ${mediaFiles.length} 个媒体文件');
      
      // ✅ 分批添加到播放列表，每次添加后让出控制权给UI线程
      const batchSize = 50; // 每批处理50个文件
      for (int i = 0; i < mediaFiles.length; i += batchSize) {
        final end = (i + batchSize < mediaFiles.length) ? i + batchSize : mediaFiles.length;
        final batch = mediaFiles.sublist(i, end);
        _playlist.addAll(batch);
        
        // 让出控制权给UI线程，保持界面响应
        await Future.delayed(Duration.zero);
        notifyListeners();
        
        debugPrint('📋 已添加 ${end}/${mediaFiles.length} 个文件到播放列表');
      }
      
      debugPrint('✅ 播放列表添加完成，共 ${mediaFiles.length} 个文件');
    } catch (e, stackTrace) {
      debugPrint('❌ 添加目录到播放列表失败: $e');
      debugPrint('📚 堆栈: $stackTrace');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playNextInPlaylist() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
      debugPrint('⏭️ 下一曲: 索引 $_currentIndex, 文件 ${_playlist[_currentIndex].name}');
      await playMedia(_playlist[_currentIndex]);
    }
  }

  Future<void> playPreviousInPlaylist() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
      debugPrint('⏮️ 上一曲: 索引 $_currentIndex, 文件 ${_playlist[_currentIndex].name}');
      await playMedia(_playlist[_currentIndex]);
    }
  }

  /// 从播放列表指定索引开始播放
  Future<void> playFromPlaylistIndex(int index) async {
    if (index >= 0 && index < _playlist.length) {
      debugPrint('🎵 从播放列表索引 $index 开始播放: ${_playlist[index].name}');
      _currentIndex = index;
      await playMedia(_playlist[_currentIndex]);
    } else {
      debugPrint('⚠️ 无效的播放列表索引: $index (列表长度: ${_playlist.length})');
    }
  }

  void clearPlaylist() {
    _playlist.clear();
    _currentIndex = 0;
    _stopPredownloading();
    notifyListeners();
  }

  void removeFromPlaylist(int index) {
    if (index >= 0 && index < _playlist.length) {
      _playlist.removeAt(index);
      if (_currentIndex >= _playlist.length) {
        _currentIndex = _playlist.length - 1;
      }
      notifyListeners();
    }
  }

  /// 重排播放列表（拖拽排序）
  void reorderPlaylist(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _playlist.length || 
        newIndex < 0 || newIndex >= _playlist.length) {
      return;
    }

    // 保存当前播放的文件
    final wasPlayingCurrent = _currentIndex == oldIndex;
    
    // 移动项目
    final item = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, item);
    
    // 更新当前播放索引
    if (wasPlayingCurrent) {
      _currentIndex = newIndex;
    } else {
      // 如果移动的项目在当前播放项之前，需要调整索引
      if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
      }
    }
    
    notifyListeners();
    debugPrint('🔄 播放列表重排: $oldIndex -> $newIndex');
  }

  /// 清除下载缓存（包括所有临时文件）
  Future<void> clearDownloadCache() async {
    debugPrint('🗑️ 开始清除下载缓存...');
    _stopPredownloading();
    
    int deletedCount = 0;
    int totalSize = 0;
    
    // 1. 清除已追踪的缓存文件
    for (final localPath in _downloadCache.values) {
      try {
        final file = File(localPath);
        if (await file.exists()) {
          totalSize += await file.length();
          await file.delete();
          deletedCount++;
          debugPrint('  📄 删除: ${file.path}');
        }
      } catch (e) {
        debugPrint('⚠️ 删除缓存文件失败: $e');
      }
    }
    
    _downloadCache.clear();
    
    // 2. ✅ 关键修复：清除临时目录中的所有历史文件
    try {
      final tempDir = await getTemporaryDirectory();
      debugPrint('📁 扫描临时目录: ${tempDir.path}');
      
      final entities = await tempDir.list().toList();
      
      for (final entity in entities) {
        if (entity is File) {
          // 只删除我们的临时文件（以 temp_ 开头或 .mp3/.mp4/.wav 等音频扩展名）
          final fileName = entity.uri.pathSegments.last;
          if (fileName.startsWith('temp_') || 
              fileName.endsWith('.mp3') || 
              fileName.endsWith('.mp4') || 
              fileName.endsWith('.wav') ||
              fileName.endsWith('.flac') ||
              fileName.endsWith('.aac') ||
              fileName.endsWith('.m4a')) {
            try {
              final fileSize = await entity.length();
              totalSize += fileSize;
              await entity.delete();
              deletedCount++;
              debugPrint('  📄 删除历史文件: $fileName (${_formatFileSize(fileSize)})');
            } catch (e) {
              debugPrint('⚠️ 删除历史文件失败: $e');
            }
          }
        } else if (entity is Directory) {
          // 递归删除子目录中的文件
          try {
            final subEntities = await entity.list().toList();
            for (final subEntity in subEntities) {
              if (subEntity is File) {
                final fileName = subEntity.uri.pathSegments.last;
                if (fileName.startsWith('temp_') || 
                    fileName.endsWith('.mp3') || 
                    fileName.endsWith('.mp4') || 
                    fileName.endsWith('.wav') ||
                    fileName.endsWith('.flac') ||
                    fileName.endsWith('.aac') ||
                    fileName.endsWith('.m4a')) {
                  final fileSize = await subEntity.length();
                  totalSize += fileSize;
                  await subEntity.delete();
                  deletedCount++;
                  debugPrint('  📄 删除子目录文件: $fileName (${_formatFileSize(fileSize)})');
                }
              }
            }
          } catch (e) {
            debugPrint('⚠️ 扫描子目录失败: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ 扫描临时目录失败: $e');
    }
    
    // 3. ✅ 新增：扫描应用缓存目录（getCacheDirectory）
    try {
      final cacheDir = await getApplicationCacheDirectory();
      debugPrint('📁 扫描应用缓存目录: ${cacheDir.path}');
      
      if (await cacheDir.exists()) {
        final entities = await cacheDir.list(recursive: true).toList();
        
        for (final entity in entities) {
          if (entity is File) {
            try {
              final fileSize = await entity.length();
              totalSize += fileSize;
              await entity.delete();
              deletedCount++;
              debugPrint('  📄 删除缓存目录文件: ${entity.path} (${_formatFileSize(fileSize)})');
            } catch (e) {
              debugPrint('⚠️ 删除缓存目录文件失败: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ 扫描应用缓存目录失败: $e');
    }
    
    // 4. ✅ 新增：清除应用支持目录中的临时文件（可选，谨慎使用）
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      debugPrint('📁 扫描应用支持目录: ${appSupportDir.path}');
      
      if (await appSupportDir.exists()) {
        // 只删除明确的临时文件，避免误删重要数据
        final entities = await appSupportDir.list(recursive: true).toList();
        
        for (final entity in entities) {
          if (entity is File) {
            final fileName = entity.uri.pathSegments.last;
            // 只删除明显的临时文件
            if (fileName.startsWith('temp_') || 
                fileName.startsWith('cache_') ||
                fileName.endsWith('.tmp')) {
              try {
                final fileSize = await entity.length();
                totalSize += fileSize;
                await entity.delete();
                deletedCount++;
                debugPrint('  📄 删除支持目录临时文件: $fileName (${_formatFileSize(fileSize)})');
              } catch (e) {
                debugPrint('⚠️ 删除支持目录文件失败: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ 扫描应用支持目录失败: $e');
    }
    
    // 5. ✅ 新增：清除应用缓存目录中的临时文件（谨慎操作，避免删除系统文件）
    try {
      final cacheDir = await getApplicationCacheDirectory();
      debugPrint('📁 扫描应用缓存目录: ${cacheDir.path}');
      
      if (await cacheDir.exists()) {
        // 只删除明显的临时文件，避免误删系统文件
        final entities = await cacheDir.list(recursive: false).toList();
        
        for (final entity in entities) {
          if (entity is File) {
            final fileName = entity.uri.pathSegments.last;
            // 只删除我们的临时文件模式
            if (fileName.startsWith('temp_') || 
                fileName.startsWith('cache_') ||
                fileName.endsWith('.tmp') ||
                fileName.endsWith('.mp3') ||
                fileName.endsWith('.mp4') ||
                fileName.endsWith('.wav') ||
                fileName.endsWith('.flac') ||
                fileName.endsWith('.aac') ||
                fileName.endsWith('.m4a')) {
              try {
                final fileSize = await entity.length();
                totalSize += fileSize;
                await entity.delete();
                deletedCount++;
                debugPrint('  📄 删除缓存目录文件: $fileName (${_formatFileSize(fileSize)})');
              } catch (e) {
                debugPrint('⚠️ 删除缓存目录文件失败: $e');
              }
            }
          } else if (entity is Directory) {
            // 递归删除子目录中的临时文件
            try {
              final subEntities = await entity.list(recursive: true).toList();
              for (final subEntity in subEntities) {
                if (subEntity is File) {
                  final fileName = subEntity.uri.pathSegments.last;
                  if (fileName.startsWith('temp_') || 
                      fileName.startsWith('cache_') ||
                      fileName.endsWith('.tmp') ||
                      fileName.endsWith('.mp3') ||
                      fileName.endsWith('.mp4') ||
                      fileName.endsWith('.wav') ||
                      fileName.endsWith('.flac') ||
                      fileName.endsWith('.aac') ||
                      fileName.endsWith('.m4a')) {
                    try {
                      final fileSize = await subEntity.length();
                      totalSize += fileSize;
                      await subEntity.delete();
                      deletedCount++;
                      debugPrint('  📄 删除缓存子目录文件: $fileName (${_formatFileSize(fileSize)})');
                    } catch (e) {
                      debugPrint('⚠️ 删除缓存子目录文件失败: $e');
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('⚠️ 扫描缓存子目录失败: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ 扫描应用缓存目录失败: $e');
    }
    
    // 6. ✅ 新增：扫描应用缓存目录中的临时文件
    try {
      final cacheDir = await getApplicationCacheDirectory();
      if (await cacheDir.exists()) {
        // 只扫描明显的临时文件，避免统计系统文件
        final entities = await cacheDir.list(recursive: false).toList();
        
        for (final entity in entities) {
          if (entity is File) {
            final fileName = entity.uri.pathSegments.last;
            // 匹配我们的临时文件模式
            if (fileName.startsWith('temp_') || 
                fileName.startsWith('cache_') ||
                fileName.endsWith('.tmp') ||
                fileName.endsWith('.mp3') ||
                fileName.endsWith('.mp4') ||
                fileName.endsWith('.wav') ||
                fileName.endsWith('.flac') ||
                fileName.endsWith('.aac') ||
                fileName.endsWith('.m4a')) {
              try {
                totalSize += await entity.length();
              } catch (e) {
                // 静默失败
              }
            }
          } else if (entity is Directory) {
            // 递归扫描子目录
            try {
              final subEntities = await entity.list(recursive: true).toList();
              for (final subEntity in subEntities) {
                if (subEntity is File) {
                  final fileName = subEntity.uri.pathSegments.last;
                  if (fileName.startsWith('temp_') || 
                      fileName.startsWith('cache_') ||
                      fileName.endsWith('.tmp') ||
                      fileName.endsWith('.mp3') ||
                      fileName.endsWith('.mp4') ||
                      fileName.endsWith('.wav') ||
                      fileName.endsWith('.flac') ||
                      fileName.endsWith('.aac') ||
                      fileName.endsWith('.m4a')) {
                    try {
                      totalSize += await subEntity.length();
                    } catch (e) {
                      // 静默失败
                    }
                  }
                }
              }
            } catch (e) {
              // 静默失败
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ 扫描应用缓存目录失败: $e');
    }
    
    debugPrint('✅ 缓存清除完成: 删除 $deletedCount 个文件，释放 ${_formatFileSize(totalSize)} 空间');
    notifyListeners();
  }
  
  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 获取缓存大小（包括所有临时文件）
  Future<int> getCacheSize() async {
    int totalSize = 0;
    
    // 1. 计算已追踪的缓存文件
    for (final localPath in _downloadCache.values) {
      try {
        final file = File(localPath);
        if (await file.exists()) {
          totalSize += await file.length();
        }
      } catch (e) {
        debugPrint('⚠️ 获取缓存大小失败: $e');
      }
    }
    
    // 2. ✅ 扫描临时目录中的所有历史文件
    try {
      final tempDir = await getTemporaryDirectory();
      final entities = await tempDir.list().toList();
      
      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          // 匹配我们的临时文件模式
          if (fileName.startsWith('temp_') || 
              fileName.endsWith('.mp3') || 
              fileName.endsWith('.mp4') || 
              fileName.endsWith('.wav') ||
              fileName.endsWith('.flac') ||
              fileName.endsWith('.aac') ||
              fileName.endsWith('.m4a')) {
            try {
              totalSize += await entity.length();
            } catch (e) {
              // 静默失败
            }
          }
        } else if (entity is Directory) {
          // 递归扫描子目录
          try {
            final subEntities = await entity.list().toList();
            for (final subEntity in subEntities) {
              if (subEntity is File) {
                final fileName = subEntity.uri.pathSegments.last;
                if (fileName.startsWith('temp_') || 
                    fileName.endsWith('.mp3') || 
                    fileName.endsWith('.mp4') || 
                    fileName.endsWith('.wav') ||
                    fileName.endsWith('.flac') ||
                    fileName.endsWith('.aac') ||
                    fileName.endsWith('.m4a')) {
                  try {
                    totalSize += await subEntity.length();
                  } catch (e) {
                    // 静默失败
                  }
                }
              }
            }
          } catch (e) {
            // 静默失败
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ 扫描临时目录失败: $e');
    }
    
    // 3. ✅ 新增：扫描应用缓存目录
    try {
      final cacheDir = await getApplicationCacheDirectory();
      if (await cacheDir.exists()) {
        final entities = await cacheDir.list(recursive: true).toList();
        for (final entity in entities) {
          if (entity is File) {
            try {
              totalSize += await entity.length();
            } catch (e) {
              // 静默失败
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ 扫描应用缓存目录失败: $e');
    }
    
    // 4. ✅ 新增：扫描应用支持目录中的临时文件
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      if (await appSupportDir.exists()) {
        final entities = await appSupportDir.list(recursive: true).toList();
        for (final entity in entities) {
          if (entity is File) {
            final fileName = entity.uri.pathSegments.last;
            // 只统计明显的临时文件
            if (fileName.startsWith('temp_') || 
                fileName.startsWith('cache_') ||
                fileName.endsWith('.tmp')) {
              try {
                totalSize += await entity.length();
              } catch (e) {
                // 静默失败
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ 扫描应用支持目录失败: $e');
    }
    
    return totalSize;
  }

  /// 获取缓存文件数量
  int get cacheFileCount => _downloadCache.length;

  /// 保存当前播放位置
  Future<void> _saveCurrentPlaybackPosition() async {
    if (_currentPlayingFile == null || _playlist.isEmpty) {
      return;
    }

    try {
      // ✅ 优化：直接使用当前播放列表ID，避免遍历查找
      String playlistId = _currentPlaylistId ?? 'current';
      
      await _databaseService.saveLastPlayedPosition(
        playlistId: playlistId,
        songIndex: _currentIndex,
        position: _position,
        duration: _duration > Duration.zero ? _duration : null,
      );
    } catch (e) {
      debugPrint('⚠️ 保存播放位置失败: $e');
    }
  }

  // 定时器
  void setSleepTimer(Duration duration) {
    _timerService.setSleepTimer(duration);
    notifyListeners();
    debugPrint('⏰ 睡眠定时器已设置: ${_formatDuration(duration)}');
  }
  
  /// 获取睡眠定时器剩余时间
  Duration? get sleepTimerRemaining => _timerService.sleepTimerRemaining;
  
  /// 获取倒计时更新流（支持睡眠定时器和文件计数定时器）
  Stream<TimerInfo?> get countdownUpdateStream => _timerService.countdownUpdateStream;
  
  /// 获取文件计数信息
  int get playedFilesCount => _timerService.playedFilesCount;
  int get maxFilesCount => _timerService.maxFilesCount;
  bool get isFileCountTimerActive => _timerService.isFileCountTimerActive;

  void setFileCountTimer(int count) {
    _timerService.setFileCountTimer(count);
    notifyListeners();
    debugPrint('📁 文件计数定时器已设置: $count 个文件');
  }

  void stopTimer() {
    _timerService.stop();
    notifyListeners();
    debugPrint('⏰ 定时器已取消');
  }
  
  /// 格式化时长显示
  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}小时${d.inMinutes % 60}分钟';
    }
    return '${d.inMinutes}分钟';
  }

  // 保存播放列表到数据库
  Future<void> savePlaylistToDatabase(String name) async {
    final playlist = await _databaseService.createPlaylist(name);
    
    // ✅ 修复：根据当前模式保存正确的sshConfigId和路径信息
    String? sshConfigIdToSave;
    Map<String, dynamic>? sshSnapshot;
    
    if (_isLocalMode) {
      // 本地模式：不保存SSH配置
      sshConfigIdToSave = null;
      sshSnapshot = null;
      debugPrint('💾 保存本地播放列表（无SSH配置）');
    } else if (_activeSSHConfig != null) {
      // SSH模式：保存SSH配置快照和当前路径
      sshConfigIdToSave = _activeSSHConfig!.id;
      sshSnapshot = {
        'id': _activeSSHConfig!.id,
        'host': _activeSSHConfig!.host,
        'port': _activeSSHConfig!.port,
        'username': _activeSSHConfig!.username,
        'name': _activeSSHConfig!.name,
        'currentPath': _currentPath,  // ✅ 新增：保存当前浏览路径
        // 注意：不保存密码，用户需要重新输入或使用密钥
      };
      
      await _databaseService.updatePlaylistSSHConfig(
        playlist.id,
        _activeSSHConfig!.id,
        sshSnapshot,
      );
      
      debugPrint('💾 保存SSH播放列表: ${_activeSSHConfig!.name} (${_activeSSHConfig!.host}), 路径=$_currentPath');
    } else {
      // 异常情况：非本地模式但没有活跃SSH配置
      sshConfigIdToSave = null;
      sshSnapshot = null;
      debugPrint('⚠️ 警告：非本地模式但无活跃SSH配置，按本地模式保存');
    }
    
    for (final file in _playlist) {
      final item = PlaylistItem(
        sshConfigId: sshConfigIdToSave ?? '',
        filePath: file.path,
        fileName: file.name,
        addedAt: DateTime.now(),
      );
      await _databaseService.addPlaylistItem(playlist.id, item);
    }
    
    debugPrint('✅ 播放列表已保存: $name (${_playlist.length} 首歌曲), 模式=${_isLocalMode ? "本地" : "SSH"}');
  }

  /// 从数据库加载播放列表
  Future<void> loadPlaylist(Playlist playlist) async {
    debugPrint('📋 ========== 开始加载播放列表 ==========');
    debugPrint('📋 播放列表名称: ${playlist.name}');
    debugPrint('📋 SSH配置ID: ${playlist.sshConfigId ?? "空（本地模式）"}');
    
    // ✅ 关键修复：根据播放列表的sshConfigId判断并切换模式
    final isLocalPlaylist = playlist.sshConfigId == null || playlist.sshConfigId!.isEmpty;
    
    if (isLocalPlaylist) {
      // 本地播放列表：切换到本地模式
      debugPrint('🔄 检测到本地播放列表，切换到本地模式');
      if (!_isLocalMode) {
        await switchToLocalMode();
      }
    } else {
      // SSH播放列表：尝试切换到SSH模式并连接
      debugPrint('🔄 检测到SSH播放列表，尝试切换到SSH模式');
      if (_isLocalMode) {
        await switchToSSHMode();
      }
      
      // 如果有SSH配置快照，尝试恢复连接配置和路径
      if (playlist.sshConfigSnapshot != null && !_isSSHConnected) {
        debugPrint('🔗 尝试使用保存的SSH配置重新连接...');
        try {
          final snapshot = playlist.sshConfigSnapshot!;
          
          // ✅ 提取保存的路径
          final savedPath = snapshot['currentPath'] as String? ?? '/';
          debugPrint('📍 保存的路径: $savedPath');
          
          // 设置活动配置
          _activeSSHConfig = SSHConfig(
            id: playlist.sshConfigId!,
            name: snapshot['name'] as String? ?? '恢复的连接',
            host: snapshot['host'] as String,
            port: snapshot['port'] as int? ?? 22,
            username: snapshot['username'] as String,
            password: '', // 密码需要用户重新输入
            initialPath: savedPath,  // ✅ 恢复保存的路径
          );
          
          // ✅ 恢复当前路径
          _currentPath = savedPath;
          debugPrint('✅ SSH配置已恢复，路径=$_currentPath（需重新输入密码以连接）');
        } catch (e) {
          debugPrint('❌ 恢复SSH配置失败: $e');
        }
      } else if (_isSSHConnected && _activeSSHConfig != null) {
        // 如果已经连接，但快照中有路径信息，也更新路径
        if (playlist.sshConfigSnapshot != null) {
          final savedPath = playlist.sshConfigSnapshot!['currentPath'] as String?;
          if (savedPath != null && savedPath != '/') {
            _currentPath = savedPath;
            debugPrint('📍 恢复到保存的路径: $_currentPath');
          }
        }
      }
    }
    
    // ✅ 关键修复：记录当前播放列表ID，用于查询该列表的断点
    _currentPlaylistId = playlist.id;
    
    // 清空当前播放列表
    _playlist.clear();
    _currentIndex = 0;
    _currentPlayingFile = null;
    
    debugPrint('📊 播放列表中共有 ${playlist.items.length} 个项目');
    
    // ✅ 关键修复：分批添加文件到播放列表，避免UI阻塞
    const batchSize = 100; // 每批处理100个文件
    final totalItems = playlist.items.length;
    
    for (int i = 0; i < totalItems; i += batchSize) {
      final end = (i + batchSize < totalItems) ? i + batchSize : totalItems;
      final batch = playlist.items.sublist(i, end);
      
      for (final item in batch) {
        // ✅ 关键修复：根据 sshConfigId 判断文件来源类型
        final isSSHFile = item.sshConfigId.isNotEmpty;
        final sourceType = isSSHFile ? FileSourceType.ssh : FileSourceType.local;
        
        final mediaFile = MediaFile.file(
          item.filePath, 
          item.fileName,
          sourceType: sourceType, // ✅ 设置正确的来源类型
        );
        
        // ✅ 添加调试日志：验证文件对象属性
        if (i == 0 && batch.indexOf(item) == 0) {
          debugPrint('📄 示例文件: name=${mediaFile.name}, path=${mediaFile.path}, isMedia=${mediaFile.isMedia}, sourceType=${mediaFile.sourceType}');
        }
        
        _playlist.add(mediaFile);
      }

      // 让出控制权给UI线程，保持界面响应
      await Future.delayed(Duration.zero);
      notifyListeners();
      
      if (end % 100 == 0 || end == totalItems) {
        debugPrint('📋 已加载 ${end}/${totalItems} 个文件到播放列表');
      }
    }
    
    debugPrint('✅ 播放列表已加载: ${playlist.name} (${_playlist.length} 首歌曲)');
    debugPrint('✅ 当前模式: ${_isLocalMode ? "本地" : "SSH"}');
    debugPrint('📋 ========== 播放列表加载完成 ==========');
  }

  /// 恢复指定播放列表的上次播放位置

  /// 从播放列表中播放指定索引的歌曲
  Future<void> playFromPlaylist(int index) async {
    if (index < 0 || index >= _playlist.length) {
      debugPrint('❌ 无效的播放列表索引: $index (列表长度: ${_playlist.length})');
      return;
    }
    
    _currentIndex = index;
    final file = _playlist[index];
    _currentPlayingFile = file;
    
    // ✅ 添加详细调试日志
    debugPrint('▶️ 从播放列表播放: ${file.name}');
    debugPrint('📍 文件路径: ${file.path}');
    debugPrint('🎵 isMedia: ${file.isMedia}, isAudio: ${file.isAudio}, isVideo: ${file.isVideo}');
    debugPrint('📂 isDirectory: ${file.isDirectory}');
    
    await playMedia(file);
  }

  // 辅助方法
  Future<File> _createTempFile(List<int> data, String fileName) async {
    final dir = await getTemporaryDirectory();
    // 使用 UUID 作为文件名避免中文/特殊字符问题，但保留扩展名
    final extension = fileName.contains('.') ? fileName.split('.').last : 'mp3';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeFileName = 'temp_${timestamp}.$extension';
    final file = File('${dir.path}/$safeFileName');
    debugPrint('📁 创建临时文件: $safeFileName (原始: $fileName)');
    await file.writeAsBytes(data);
    return file;
  }

  @override
  void dispose() {
    _networkMonitor.dispose();
    _sshService.dispose();
    _audioPlayerService.dispose();
    _timerService.dispose();
    _databaseService.close();
    super.dispose();
  }

  /// 检查当前播放列表是否有上次播放位置记录
  Future<bool> hasPendingRestoreForCurrentPlaylist() async {
    if (_currentPlaylistId == null || _currentPlaylistId!.isEmpty) {
      return false;
    }
    
    final lastPosition = await _databaseService.getLastPlayedPosition(_currentPlaylistId!);
    if (lastPosition == null) {
      return false;
    }
    
    // 验证索引是否有效
    final songIndex = lastPosition['songIndex'] as int;
    if (songIndex < 0 || songIndex >= _playlist.length) {
      debugPrint('⚠️ 播放位置索引超出范围: $songIndex / ${_playlist.length}');
      return false;
    }
    
    return true;
  }

  /// 获取当前播放列表的待恢复信息
  Future<Map<String, dynamic>?> getPendingRestoreInfoForCurrentPlaylist() async {
    if (_currentPlaylistId == null || _currentPlaylistId!.isEmpty) {
      return null;
    }
    
    final lastPosition = await _databaseService.getLastPlayedPosition(_currentPlaylistId!);
    if (lastPosition == null) {
      return null;
    }
    
    final songIndex = lastPosition['songIndex'] as int;
    final positionMs = lastPosition['position'] as int;
    
    // 验证索引有效性
    if (songIndex < 0 || songIndex >= _playlist.length) {
      debugPrint('⚠️ 播放位置索引超出范围: $songIndex / ${_playlist.length}');
      return null;
    }
    
    return {
      'songIndex': songIndex,
      'positionMs': positionMs,
    };
  }

  /// 执行恢复播放（基于当前播放列表的上次位置）
  Future<void> restoreAndPlay() async {
    if (_currentPlaylistId == null || _currentPlaylistId!.isEmpty) {
      debugPrint('⚠️ 没有当前播放列表');
      return;
    }

    try {
      // 获取当前播放列表的上次播放位置
      final restoreInfo = await getPendingRestoreInfoForCurrentPlaylist();
      if (restoreInfo == null) {
        debugPrint('⚠️ 当前播放列表没有待恢复的播放位置');
        return;
      }

      final songIndex = restoreInfo['songIndex'] as int;
      final positionMs = restoreInfo['positionMs'] as int;

      debugPrint('▶️ 开始恢复播放: 索引=$songIndex, 进度=${positionMs}ms');

      // 如果有 SSH 配置，先连接
      if (_activeSSHConfig != null && !_isSSHConnected) {
        await connectSSH(_activeSSHConfig!);
      }

      // 设置当前索引并播放
      if (songIndex >= 0 && songIndex < _playlist.length) {
        _currentIndex = songIndex;
        
        // 播放歌曲
        await playFromPlaylist(songIndex);
        
        // 等待播放器就绪后恢复进度
        await Future.delayed(const Duration(milliseconds: 1000));
        if (positionMs > 0) {
          await seekTo(Duration(milliseconds: positionMs));
          debugPrint('⏩ 恢复到进度: ${Duration(milliseconds: positionMs)}');
        }
      }
      
      debugPrint('✅ 播放位置恢复成功');
    } catch (e) {
      debugPrint('❌ 恢复播放失败: $e');
      rethrow;
    }
  }

  /// ✅ 确保前台服务已启动（首次播放时调用）
  Future<void> _ensureForegroundServiceStarted() async {
    try {
      debugPrint('🔧 检查前台服务状态...');
      await BackgroundService.start();
      
      // ✅ 关键修复：等待服务完全启动并注册到系统
      // 这样可以确保即使立即杀死应用，onTaskRemoved也会被调用
      await Future.delayed(const Duration(milliseconds: 800));
      
      debugPrint('✅ 前台服务已完全启动，MediaSession已初始化');
    } catch (e) {
      debugPrint('⚠️ 启动前台服务失败（可忽略）: $e');
      // 即使启动失败也继续，可能是服务已经运行或其他原因
    }
  }

  /// ✅ 更新 MediaSession 元数据（用于蓝牙设备显示曲目信息）
  void _updateMediaSessionMetadata(MediaFile file) {
    try {
      // 提取文件名作为标题（不含扩展名）
      final title = file.name.contains('.') 
          ? file.name.substring(0, file.name.lastIndexOf('.'))
          : file.name;
      
      // 获取时长（毫秒）
      final durationMs = _duration.inMilliseconds;
      
      // 异步更新，不阻塞主流程
      MediaSessionService.updateMediaMetadata(
        title: title,
        artist: 'SSH Player', // 可以后续从文件元数据中读取
        album: null,
        duration: durationMs,
      ).then((_) {
        debugPrint('📻 MediaSession 元数据已更新: $title');
      }).catchError((e) {
        debugPrint('⚠️ 更新 MediaSession 元数据失败: $e');
      });
    } catch (e) {
      debugPrint('⚠️ 更新 MediaSession 元数据异常: $e');
    }
  }

  /// ✅ 更新 MediaSession 播放状态
  void _updateMediaSessionPlaybackState({required bool isPlaying}) {
    try {
      final state = isPlaying 
          ? MediaSessionService.STATE_PLAYING 
          : MediaSessionService.STATE_PAUSED;
      
      final positionMs = _position.inMilliseconds;
      
      // 异步更新，不阻塞主流程
      MediaSessionService.updatePlaybackState(
        state: state,
        position: positionMs,
        speed: 1.0,
      ).then((_) {
        debugPrint('📻 MediaSession 播放状态已更新: ${isPlaying ? "播放中" : "暂停"}');
      }).catchError((e) {
        debugPrint('⚠️ 更新 MediaSession 播放状态失败: $e');
      });
    } catch (e) {
      debugPrint('⚠️ 更新 MediaSession 播放状态异常: $e');
    }
  }

  /// ✅ 更新 MediaSession 播放位置（节流，避免频繁调用）
  void _updateMediaSessionPosition() {
    try {
      final state = _isPlaying 
          ? MediaSessionService.STATE_PLAYING 
          : MediaSessionService.STATE_PAUSED;
      
      final positionMs = _position.inMilliseconds;
      
      // 异步更新，不阻塞主流程
      MediaSessionService.updatePlaybackState(
        state: state,
        position: positionMs,
        speed: 1.0,
      ).catchError((e) {
        // 静默失败，避免日志过多
      });
    } catch (e) {
      // 静默失败
    }
  }
}




