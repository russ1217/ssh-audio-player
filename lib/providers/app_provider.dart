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

class AppProvider extends ChangeNotifier {
  final SSHService _sshService = SSHService();
  final DatabaseService _databaseService = DatabaseService();
  final AudioPlayerServiceBase _audioPlayerService = createAudioPlayerService();
  final StreamingAudioService _streamingService = StreamingAudioService();
  final TimerService _timerService = TimerService();

  // SSH 状态
  List<SSHConfig> _sshConfigs = [];
  SSHConfig? _activeSSHConfig;
  bool _isSSHConnected = false;

  // 文件浏览
  List<MediaFile> _currentFiles = [];
  String _currentPath = '/';
  bool _isLoading = false;

  // 播放列表
  List<MediaFile> _playlist = [];
  int _currentIndex = 0;
  MediaFile? _currentPlayingFile; // 当前正在播放的文件

  // 后台预下载
  final Map<String, String> _downloadCache = {}; // 文件路径 -> 本地路径
  bool _isPredownloading = false;
  int _predownloadIndex = -1;

  // 播放器状态
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

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
  List<MediaFile> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  MediaFile? get currentPlayingFile => _currentPlayingFile;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;

  AppProvider() {
    _init();
    _setupStreamingServiceListener();
  }

  Future<void> _init() async {
    await _loadSSHConfigs();
    _setupSSHHeartbeatListener();
    _setupAudioPlayerListeners();
    _setupTimerListeners();
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
      final fileSize = file.size ?? await _sshService.getFileSize(file.path) ?? 0;
      final sizeInMB = fileSize ~/ (1024 * 1024);

      // 恢复播放
      if (sizeInMB > 50) {
        // 大文件：重新启动流式服务
        debugPrint('🌐 重新启动流式服务...');
        await _playMediaStreaming(file);
      } else {
        // 小文件：检查缓存
        if (_downloadCache.containsKey(file.path)) {
          final cachedPath = _downloadCache[file.path]!;
          await _audioPlayerService.playFile(cachedPath, isVideo: file.isVideo);
        } else {
          // 重新下载
          await _playMediaAfterDownload(file);
        }
      }

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
      debugPrint('✅ 播放已恢复');
    } catch (e) {
      debugPrint('❌ 恢复播放失败: $e');
      _shouldResumeAfterReconnect = false;
      _isAutoResuming = false;
    }
  }

  void _setupAudioPlayerListeners() {
    _audioPlayerService.playbackStateStream.listen((state) {
      _isPlaying = _audioPlayerService.isPlaying;
      notifyListeners();
    });

    _audioPlayerService.positionStream.listen((position) {
      _position = position;
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
    _currentFiles.clear();
    _currentPath = '/';
    notifyListeners();
  }

  // 文件浏览
  Future<void> _loadCurrentDirectory() async {
    if (!_isSSHConnected) return;

    try {
      _isLoading = true;
      notifyListeners();

      // 在加载目录前确保 SSH 连接有效
      final isConnected = await _ensureSSHConnection();
      if (!isConnected) {
        _isSSHConnected = false;
        _currentFiles = [];
        debugPrint('❌ SSH 连接失败，无法加载目录');
        return;
      }

      _currentFiles = await _sshService.listDirectory(_currentPath);
      // 排序：目录在前，文件在后
      _currentFiles.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.compareTo(b.name);
      });
    } catch (e) {
      debugPrint('加载目录失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
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
  Future<void> playMedia(MediaFile file) async {
    if (!file.isMedia) return;

    // 如果文件在播放列表中，同步 currentIndex
    final playlistIndex = _playlist.indexWhere((f) => f.path == file.path);
    if (playlistIndex >= 0) {
      debugPrint('🔗 文件在播放列表中，同步索引: $playlistIndex');
      _currentIndex = playlistIndex;
    }

    debugPrint('▶️ playMedia 调用: 文件=${file.name}, 当前 _currentIndex=$_currentIndex, _playlist 长度=${_playlist.length}');

    try {
      _isLoading = true;
      _currentPlayingFile = file;
      notifyListeners();

      // 检查是否已缓存
      if (_downloadCache.containsKey(file.path)) {
        final cachedPath = _downloadCache[file.path]!;
        debugPrint('📁 使用缓存文件: $cachedPath');
        final isVideo = file.isVideo;
        await _audioPlayerService.playFile(cachedPath, isVideo: isVideo);
        _isPlaying = true;
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 获取文件大小
      final fileSize = file.size ?? await _sshService.getFileSize(file.path) ?? 0;
      final sizeInMB = fileSize ~/ (1024 * 1024);

      // 大于 50MB 使用流式下载边下边播，小于 50MB 整体下载后播放
      if (sizeInMB > 50) {
        debugPrint('🎵 大文件 (${sizeInMB}MB)，使用流式下载播放');
        await _playMediaStreaming(file);
      } else {
        debugPrint('🎵 小文件 (${sizeInMB}MB)，下载后播放');
        await _playMediaAfterDownload(file);
      }

      _isPlaying = true;
      debugPrint('✅ 播放完成设置: _currentIndex=$_currentIndex');
    } catch (e) {
      debugPrint('❌ 播放失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 小文件：下载完成后播放（同时后台预下载后续剧集）
  Future<void> _playMediaAfterDownload(MediaFile file) async {
    final fileData = await _sshService.readFile(file.path);
    final tempFile = await _createTempFile(fileData, file.name);
    
    // 加入缓存
    _downloadCache[file.path] = tempFile.path;

    final isVideo = file.isVideo;
    await _audioPlayerService.playFile(tempFile.path, isVideo: isVideo);
    
    // 后台预下载后续剧集（如果当前文件小于 50MB）
    final fileSize = file.size ?? await _sshService.getFileSize(file.path) ?? 0;
    final sizeInMB = fileSize ~/ (1024 * 1024);
    if (sizeInMB < 50) {
      _startPredownloading();
    }
  }

  // 大文件：真正的流式下载边下边播
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

  /// 开始后台预下载
  void _startPredownloading() {
    if (_isPredownloading) return;
    if (_currentIndex >= _playlist.length - 1) return; // 已经是最后一个
    
    _predownloadIndex = _currentIndex + 1;
    _predownloadNext();
  }

  /// 预下载下一个文件
  Future<void> _predownloadNext() async {
    if (_predownloadIndex >= _playlist.length) {
      _isPredownloading = false;
      return;
    }

    _isPredownloading = true;
    final nextFile = _playlist[_predownloadIndex];

    // 检查是否已缓存
    if (_downloadCache.containsKey(nextFile.path)) {
      debugPrint('✅ 文件已缓存: ${nextFile.name}');
      _predownloadIndex++;
      _isPredownloading = false;
      _predownloadNext();
      return;
    }

    try {
      debugPrint('⬇️ 后台预下载: ${nextFile.name} (索引: $_predownloadIndex)');
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
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayerService.pause();
    } else {
      await _audioPlayerService.play();
    }
  }

  Future<void> stopPlayback() async {
    await _audioPlayerService.stop();
    await _streamingService.stop();
    _isPlaying = false;
    _currentPlayingFile = null;
    _stopPredownloading();
    notifyListeners();
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
    if (!_isSSHConnected) return;

    try {
      _isLoading = true;
      notifyListeners();

      final files = await _sshService.listDirectory(path);
      final mediaFiles = files.where((f) => f.isMedia).toList();
      mediaFiles.sort((a, b) => a.name.compareTo(b.name));
      
      _playlist.addAll(mediaFiles);
      notifyListeners();
    } catch (e) {
      debugPrint('添加目录到播放列表失败: $e');
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

  /// 清除下载缓存
  Future<void> clearDownloadCache() async {
    debugPrint('🗑️ 清除下载缓存...');
    _stopPredownloading();
    
    for (final localPath in _downloadCache.values) {
      try {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('⚠️ 删除缓存文件失败: $e');
      }
    }
    
    _downloadCache.clear();
    debugPrint('✅ 下载缓存已清除');
    notifyListeners();
  }

  /// 获取缓存大小
  Future<int> getCacheSize() async {
    int totalSize = 0;
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
    return totalSize;
  }

  /// 获取缓存文件数量
  int get cacheFileCount => _downloadCache.length;

  // 定时器
  void setSleepTimer(Duration duration) {
    _timerService.setSleepTimer(duration);
    notifyListeners();
  }

  void setFileCountTimer(int count) {
    _timerService.setFileCountTimer(count);
    notifyListeners();
  }

  void stopTimer() {
    _timerService.stop();
    notifyListeners();
  }

  // 保存播放列表到数据库
  Future<void> savePlaylistToDatabase(String name) async {
    final playlist = await _databaseService.createPlaylist(name);
    
    for (final file in _playlist) {
      final item = PlaylistItem(
        sshConfigId: _activeSSHConfig?.id ?? '',
        filePath: file.path,
        fileName: file.name,
        addedAt: DateTime.now(),
      );
      await _databaseService.addPlaylistItem(playlist.id, item);
    }
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
    _sshService.dispose();
    _audioPlayerService.dispose();
    _timerService.dispose();
    _databaseService.close();
    super.dispose();
  }
}
