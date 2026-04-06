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
  }

  Future<void> _init() async {
    await _loadSSHConfigs();
    _setupAudioPlayerListeners();
    _setupTimerListeners();
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

    try {
      _isLoading = true;
      _currentPlayingFile = file;
      notifyListeners();

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
    } catch (e) {
      debugPrint('播放失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 小文件：下载完成后播放
  Future<void> _playMediaAfterDownload(MediaFile file) async {
    final fileData = await _sshService.readFile(file.path);
    final tempFile = await _createTempFile(fileData, file.name);

    final isVideo = file.isVideo;
    await _audioPlayerService.playFile(tempFile.path, isVideo: isVideo);
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
    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
      await playMedia(_playlist[_currentIndex]);
    }
  }

  Future<void> playPreviousInPlaylist() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      await playMedia(_playlist[_currentIndex]);
    }
  }

  /// 从播放列表指定索引开始播放
  Future<void> playFromPlaylistIndex(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _currentIndex = index;
      await playMedia(_playlist[_currentIndex]);
    }
  }

  void clearPlaylist() {
    _playlist.clear();
    _currentIndex = 0;
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
    _sshService.disconnect();
    _audioPlayerService.dispose();
    _timerService.dispose();
    _databaseService.close();
    super.dispose();
  }
}
