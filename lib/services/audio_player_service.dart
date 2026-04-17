import 'dart:async';
import 'dart:io' show Platform;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'audio_player_base.dart';

// 根据平台创建不同的音频播放器实现
AudioPlayerServiceBase createAudioPlayerService() {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    debugPrint('🖥️ 检测到桌面平台，使用音频播放器空实现');
    return _DesktopAudioPlayerService();
  } else {
    debugPrint('📱 检测到移动平台，使用音频播放器完整实现');
    return _MobileAudioPlayerService();
  }
}

// 桌面平台空实现
class _DesktopAudioPlayerService extends AudioPlayerServiceBase {
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;
  
  @override
  bool get isPlaying => false;
  
  @override
  Duration get currentPosition => Duration.zero;
  
  @override
  Duration get duration => Duration.zero;
  
  @override
  int get currentIndex => 0;

  _DesktopAudioPlayerService() {
    debugPrint('⚠️ 桌面平台不支持音频播放（仅用于开发和测试 UI）');
    _isInitialized = false;
  }

  @override
  Future<void> playFile(String filePath, {bool isVideo = false}) async {
    debugPrint('⚠️ 桌面平台不支持播放文件: $filePath');
  }

  @override
  Future<void> playUrl(String url, {bool isVideo = false}) async {
    debugPrint('⚠️ 桌面平台不支持播放 URL: $url');
  }

  @override
  Future<void> play() async {
    debugPrint('⚠️ 桌面平台不支持播放');
  }

  @override
  Future<void> pause() async {
    debugPrint('⚠️ 桌面平台不支持暂停');
  }

  @override
  Future<void> stop() async {
    debugPrint('⚠️ 桌面平台不支持停止');
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('⚠️ 桌面平台不支持 seek');
  }

  @override
  Future<void> seekForward(Duration duration) async {
    debugPrint('⚠️ 桌面平台不支持快进');
  }

  @override
  Future<void> seekBackward(Duration duration) async {
    debugPrint('⚠️ 桌面平台不支持快退');
  }

  @override
  Future<void> playNext() async {
    debugPrint('⚠️ 桌面平台不支持下一曲');
  }

  @override
  Future<void> playPrevious() async {
    debugPrint('⚠️ 桌面平台不支持上一曲');
  }

  @override
  Future<void> setVolume(double volume) async {
    debugPrint('⚠️ 桌面平台不支持设置音量');
  }

  @override
  Future<void> setSpeed(double speed) async {
    debugPrint('⚠️ 桌面平台不支持设置播放速度');
  }

  @override
  Future<void> dispose() async {
    closeStreams();
  }
}

// 移动平台完整实现
class _MobileAudioPlayerService extends AudioPlayerServiceBase {
  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;

  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(
    children: [],
  );

  // 流控制器
  final _playbackStateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _currentIndexController = StreamController<int>.broadcast();
  final _completeController = StreamController<void>.broadcast();

  @override
  Stream<PlayerState> get playbackStateStream => _playbackStateController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  @override
  Stream<int> get currentIndexStream => _currentIndexController.stream;
  @override
  Stream<void> get completeStream => _completeController.stream;

  @override
  Duration get currentPosition => _audioPlayer?.position ?? Duration.zero;
  @override
  Duration get duration => _audioPlayer?.duration ?? Duration.zero;
  @override
  int get currentIndex => _audioPlayer?.currentIndex ?? 0;
  @override
  bool get isPlaying => _audioPlayer?.playing ?? false;
  int get playlistLength => _playlist.length;
  @override
  bool get isInitialized => _isInitialized;

  _MobileAudioPlayerService() {
    _initialize();
  }

  @override
  Future<void> dispose() async {
    if (_audioPlayer != null) {
      await _audioPlayer!.dispose();
    }
    _playbackStateController.close();
    _positionController.close();
    _durationController.close();
    _currentIndexController.close();
    _completeController.close();
  }

  Future<void> _initialize() async {
    try {
      _audioPlayer = AudioPlayer();
      _setupListeners();
      _isInitialized = true;
      debugPrint('✅ 移动端音频播放器初始化成功');
    } catch (e, stackTrace) {
      debugPrint('❌ 移动端音频播放器初始化失败: $e');
      debugPrint('堆栈: $stackTrace');
      _isInitialized = false;
    }
  }

  void _setupListeners() {
    if (_audioPlayer == null) return;

    _audioPlayer!.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _completeController.add(null);
      }
    });

    _audioPlayer!.positionStream.listen((position) {
      _positionController.add(position);
    });

    _audioPlayer!.durationStream.listen((duration) {
      if (duration != null) {
        _durationController.add(duration);
      }
    });

    _audioPlayer!.currentIndexStream.listen((index) {
      if (index != null) {
        _currentIndexController.add(index);
      }
    });
  }

  @override
  Future<void> playFile(String filePath, {bool isVideo = false}) async {
    if (!_isInitialized || _audioPlayer == null) {
      debugPrint('⚠️ 音频播放器未初始化');
      return;
    }
    try {
      debugPrint('🎵 准备播放文件: $filePath');
      
      // 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ 文件不存在: $filePath');
        return;
      }
      final fileSize = await file.length();
      debugPrint('📁 文件大小: ${fileSize ~/ 1024} KB');
      
      debugPrint('🎵 正在加载文件到播放器...');
      await _audioPlayer!.setFilePath(filePath);
      debugPrint('🎵 文件加载成功，持续时间: ${_audioPlayer!.duration}');
      
      debugPrint('🎵 正在启动播放...');
      // 使用 play() 但不等待它完成
      _audioPlayer!.play();
      debugPrint('🎵 播放命令已发送');
    } catch (e, stackTrace) {
      debugPrint('❌ 播放文件失败: $e');
      debugPrint('堆栈: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> playUrl(String url, {bool isVideo = false}) async {
    if (!_isInitialized || _audioPlayer == null) return;
    try {
      debugPrint('🎵 准备播放 URL: $url');
      await _audioPlayer!.setUrl(url);
      debugPrint('🎵 URL 加载成功，持续时间: ${_audioPlayer!.duration}');
      _audioPlayer!.play();
      debugPrint('🎵 播放命令已发送');
    } catch (e, stackTrace) {
      debugPrint('❌ 播放 URL 失败: $e');
      debugPrint('堆栈: $stackTrace');
    }
  }

  @override
  Future<void> play() async {
    if (!_isInitialized || _audioPlayer == null) return;
    await _audioPlayer!.play();
  }

  @override
  Future<void> pause() async {
    if (!_isInitialized || _audioPlayer == null) return;
    await _audioPlayer!.pause();
  }

  @override
  Future<void> stop() async {
    if (!_isInitialized || _audioPlayer == null) return;
    await _audioPlayer!.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_isInitialized || _audioPlayer == null) return;
    await _audioPlayer!.seek(position);
  }

  @override
  Future<void> seekForward(Duration duration) async {
    if (!_isInitialized || _audioPlayer == null) return;
    final newPosition = _audioPlayer!.position + duration;
    await _audioPlayer!.seek(newPosition);
  }

  @override
  Future<void> seekBackward(Duration duration) async {
    if (!_isInitialized || _audioPlayer == null) return;
    final newPosition = _audioPlayer!.position - duration;
    final clampedPosition = newPosition < Duration.zero ? Duration.zero : newPosition;
    final maxDuration = _audioPlayer!.duration ?? Duration.zero;
    await _audioPlayer!.seek(
      clampedPosition > maxDuration ? maxDuration : clampedPosition,
    );
  }

  @override
  Future<void> playNext() async {
    if (!_isInitialized || _audioPlayer == null) return;
    if (_audioPlayer!.currentIndex != null &&
        _audioPlayer!.currentIndex! < _playlist.length - 1) {
      await _audioPlayer!.seekToNext();
    }
  }

  @override
  Future<void> playPrevious() async {
    if (!_isInitialized || _audioPlayer == null) return;
    if (_audioPlayer!.currentIndex != null && _audioPlayer!.currentIndex! > 0) {
      await _audioPlayer!.seekToPrevious();
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_isInitialized || _audioPlayer == null) return;
    await _audioPlayer!.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (!_isInitialized || _audioPlayer == null) return;
    await _audioPlayer!.setSpeed(speed.clamp(0.25, 2.0));
  }
}
