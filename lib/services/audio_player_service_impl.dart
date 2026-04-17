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
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      debugPrint('✅ 音频会话配置成功');
      
      _audioPlayer = AudioPlayer();
      _setupListeners();
      _isInitialized = true;
      debugPrint('✅ 音频播放器初始化成功');
    } catch (e, stackTrace) {
      debugPrint('❌ 音频播放器初始化失败: $e');
      debugPrint('堆栈: $stackTrace');
      _isInitialized = false;
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
    if (!_isInitialized || _audioPlayer == null) {
      debugPrint('⚠️ 音频播放器未初始化');
      return;
    }
    try {
      await _audioPlayer!.setFilePath(filePath);
      await _audioPlayer!.play();
    } catch (e) {
      debugPrint('播放文件失败: $e');
    }
  }

  @override
  Future<void> playUrl(String url, {bool isVideo = false}) async {
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
