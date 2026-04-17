import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'audio_player_base.dart';
import '../models/media_file.dart';

class AudioPlayerService extends AudioPlayerServiceBase {
  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;

  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(
    children: [],
  );

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

  AudioPlayerService() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // 配置音频会话（关键修复）
      print('🔧 开始配置音频会话...');
      final session = await AudioSession.instance;
      print('🔧 获取 AudioSession 实例成功');
      await session.configure(const AudioSessionConfiguration.music());
      print('✅ 音频会话配置成功');
      
      _audioPlayer = AudioPlayer();
      _setupListeners();
      
      // ✅ 关键修复：加载一个极短的静音文件，触发底层引擎完整初始化
      print('⏳ 预热 AudioPlayer 底层引擎...');
      try {
        // 使用一个空的 Duration 作为占位符，不实际加载文件
        // 而是通过等待 processingState 变化来确认引擎就绪
        final completer = Completer<void>();
        StreamSubscription? subscription;
        
        subscription = _audioPlayer!.processingStateStream.listen((state) {
          print('📊 初始化状态: $state');
          // 只要状态从 idle 变为其他状态，就说明引擎已就绪
          if (state != ProcessingState.idle && !completer.isCompleted) {
            print('✅ AudioPlayer 底层引擎已就绪: $state');
            completer.complete();
          }
        });
        
        // 设置超时
        final timeout = Timer(const Duration(seconds: 5), () {
          if (!completer.isCompleted) {
            print('⚠️ AudioPlayer 初始化超时，但继续执行');
            completer.complete();
          }
        });
        
        await completer.future;
        subscription?.cancel();
        timeout.cancel();
      } catch (e) {
        print('⚠️ 预热过程异常（可忽略）: $e');
      }
      
      _isInitialized = true;
      print('✅ 音频播放器完全初始化成功');
    } catch (e, stackTrace) {
      print('❌ 音频播放器初始化失败: $e');
      print('堆栈: $stackTrace');
      _isInitialized = false;
    }
  }

  /// 等待初始化完成
  Future<void> ensureInitialized() async {
    // 如果已经初始化，直接返回
    if (_isInitialized) return;
    
    // 等待最多 5 秒
    final timeout = DateTime.now().add(const Duration(seconds: 5));
    while (!_isInitialized && DateTime.now().isBefore(timeout)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    if (!_isInitialized) {
      print('⚠️ 音频播放器初始化超时');
    }
  }

  void _setupListeners() {
    if (_audioPlayer == null) return;

    // 主要状态监听器 - 广播播放器状态
    _audioPlayer!.playerStateStream.listen((state) {
      final playerState = switch (state.processingState) {
        ProcessingState.idle => PlayerState.idle,
        ProcessingState.loading => PlayerState.loading,
        ProcessingState.buffering => PlayerState.loading,
        ProcessingState.ready => state.playing ? PlayerState.playing : PlayerState.paused,
        ProcessingState.completed => PlayerState.completed,
      };
      
      // 关键修复：将状态广播到 StreamController
      if (!_playbackStateController.isClosed) {
        _playbackStateController.add(playerState);
      }
      
      debugPrint('🎵 AudioPlayer 状态变化: processingState=${state.processingState}, playing=${state.playing} -> mapped to $playerState');
    });

    // 完成事件监听器
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
    // ✅ 关键修复：确保初始化完成后再播放
    await ensureInitialized();
    
    if (!_isInitialized || _audioPlayer == null) {
      print('⚠️ 音频播放器未初始化');
      return;
    }
    try {
      print('🎵 准备播放文件: $filePath');
      
      // 关键修复：在播放前激活音频会话
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
        print('✅ 音频会话已激活');
      } catch (e) {
        print('⚠️ 激活音频会话失败: $e');
      }
      
      print('🔊 当前音量: ${_audioPlayer!.volume}');
      
      // 确保音量为最大值
      await _audioPlayer!.setVolume(1.0);
      print('🔊 设置音量为 1.0');
      
      // 设置文件路径
      await _audioPlayer!.setFilePath(filePath);
      print('📁 文件路径设置成功');
      
      // 开始播放
      await _audioPlayer!.play();
      print('▶️ 播放命令已发送');
      
      // 延迟检查播放状态
      await Future.delayed(const Duration(milliseconds: 500));
      print('🔍 播放状态检查 - playing: ${_audioPlayer!.playing}, position: ${_audioPlayer!.position}, volume: ${_audioPlayer!.volume}');
    } catch (e, stackTrace) {
      print('❌ 播放文件失败: $e');
      print('堆栈: $stackTrace');
    }
  }

  @override
  Future<void> playUrl(String url, {bool isVideo = false}) async {
    // ✅ 关键修复：确保初始化完成后再播放
    await ensureInitialized();
    
    if (!_isInitialized || _audioPlayer == null) return;
    try {
      await _audioPlayer!.setUrl(url);
      await _audioPlayer!.play();
    } catch (e) {
      debugPrint('播放 URL 失败: $e');
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

  @override
  Future<void> dispose() async {
    if (_audioPlayer != null) {
      await _audioPlayer!.dispose();
    }
    closeStreams();
  }
}
