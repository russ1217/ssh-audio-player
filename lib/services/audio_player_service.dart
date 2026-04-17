import 'dart:async';
import 'dart:io' show Platform;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:audio_session/audio_session.dart';
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

  // ✅ 实现基类的抽象Stream getter（桌面平台返回空流）
  @override
  Stream<PlayerState> get playbackStateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<int> get currentIndexStream => const Stream.empty();
  @override
  Stream<void> get completeStream => const Stream.empty();

  _DesktopAudioPlayerService() {
    debugPrint('⚠️ 桌面平台不支持音频播放（仅用于开发和测试 UI）');
    _isInitialized = false;
  }

  @override
  Future<void> ensureInitialized() async {
    // 桌面平台不需要初始化，直接返回
    _isInitialized = true;
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
    // 桌面平台不需要关闭任何资源
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
  Future<void> ensureInitialized() async {
    // 如果已经初始化，直接返回
    if (_isInitialized) return;
    
    // 等待最多 5 秒
    final timeout = DateTime.now().add(const Duration(seconds: 5));
    while (!_isInitialized && DateTime.now().isBefore(timeout)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    if (!_isInitialized) {
      debugPrint('⚠️ 移动端音频播放器初始化超时');
    }
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

    // ✅ 关键修复：监听播放器状态变化并广播到 Stream
    _audioPlayer!.playerStateStream.listen((state) {
      debugPrint('📊 just_audio 状态变化: processingState=${state.processingState}, playing=${state.playing}');
      
      PlayerState mappedState;
      switch (state.processingState) {
        case ProcessingState.idle:
          mappedState = PlayerState.idle;
          break;
        case ProcessingState.loading:
        case ProcessingState.buffering:
          mappedState = PlayerState.loading;
          break;
        case ProcessingState.ready:
          mappedState = state.playing ? PlayerState.playing : PlayerState.paused;
          break;
        case ProcessingState.completed:
          mappedState = PlayerState.completed;
          _completeController.add(null); // 保留原有的完成事件
          break;
      }
      
      // 广播状态到 Stream
      if (!_playbackStateController.isClosed) {
        _playbackStateController.add(mappedState);
        debugPrint('📻 广播播放器状态: $mappedState');
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
    if (!_isInitialized || _audioPlayer == null) return;
    
    try {
      debugPrint('🎵 准备播放文件: $filePath');
      
      // ✅ 关键修复：在播放前激活音频会话（解决冷启动无声问题）
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
        debugPrint('✅ 音频会话已激活');
      } catch (e) {
        debugPrint('⚠️ 激活音频会话失败: $e');
      }
      
      // 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ 文件不存在: $filePath');
        return;
      }
      final fileSize = await file.length();
      debugPrint('📁 文件大小: ${fileSize ~/ 1024} KB');
      
      // ✅ 关键修复：确保音量为最大值
      debugPrint('🔊 当前音量: ${_audioPlayer!.volume}');
      await _audioPlayer!.setVolume(1.0);
      debugPrint('🔊 设置音量为 1.0');
      
      debugPrint('🎵 正在加载文件到播放器...');
      await _audioPlayer!.setFilePath(filePath);
      debugPrint('🎵 文件加载成功，持续时间: ${_audioPlayer!.duration}');
      
      debugPrint('🎵 正在启动播放...');
      // 使用 play() 但不等待它完成
      await _audioPlayer!.play();
      debugPrint('🎵 播放命令已发送');
      
      // ✅ 关键修复：延迟检查播放状态，便于调试
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint('🔍 播放状态检查 - playing: ${_audioPlayer!.playing}, position: ${_audioPlayer!.position}, volume: ${_audioPlayer!.volume}');
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
      
      // ✅ 关键修复：在播放前激活音频会话
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
        debugPrint('✅ 音频会话已激活');
      } catch (e) {
        debugPrint('⚠️ 激活音频会话失败: $e');
      }
      
      // ✅ 关键修复：确保音量为最大值
      await _audioPlayer!.setVolume(1.0);
      debugPrint('🔊 设置音量为 1.0');
      
      await _audioPlayer!.setUrl(url);
      debugPrint('🎵 URL 加载成功，持续时间: ${_audioPlayer!.duration}');
      await _audioPlayer!.play();
      debugPrint('🎵 播放命令已发送');
    } catch (e, stackTrace) {
      debugPrint('❌ 播放 URL 失败: $e');
      debugPrint('堆栈: $stackTrace');
    }
  }

  @override
  Future<void> play() async {
    if (!_isInitialized || _audioPlayer == null) return;
    
    debugPrint('▶️ 调用 just_audio.play()...');
    await _audioPlayer!.play();
    debugPrint('✅ just_audio.play() 调用完成, playing=${_audioPlayer!.playing}');
    
    // ✅ 立即广播播放状态
    if (!_playbackStateController.isClosed) {
      _playbackStateController.add(PlayerState.playing);
      debugPrint('📻 强制广播播放状态: playing');
    }
  }

  @override
  Future<void> pause() async {
    if (!_isInitialized || _audioPlayer == null) return;
    
    debugPrint('⏸️ 调用 just_audio.pause()...');
    await _audioPlayer!.pause();
    debugPrint('✅ just_audio.pause() 调用完成, playing=${_audioPlayer!.playing}');
    
    // ✅ 立即广播暂停状态
    if (!_playbackStateController.isClosed) {
      _playbackStateController.add(PlayerState.paused);
      debugPrint('📻 强制广播暂停状态: paused');
    }
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
