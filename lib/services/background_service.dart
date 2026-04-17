import 'package:flutter/services.dart';

class BackgroundService {
  static const MethodChannel _channel = MethodChannel('com.example.player/background_service');

  /// Starts the foreground service to keep SSH and Playback alive
  static Future<void> start() async {
    try {
      await _channel.invokeMethod('startService');
    } on PlatformException catch (e) {
      print("Failed to start service: '${e.message}'.");
    }
  }

  /// Stops the foreground service
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      print("Failed to stop service: '${e.message}'.");
    }
  }
}

/// ✅ MediaSession 服务，用于向蓝牙设备广播媒体信息
class MediaSessionService {
  static const MethodChannel _channel = MethodChannel('com.example.player/media_session');

  /// 播放状态常量（对应 Android PlaybackState）
  static const int STATE_NONE = 0;
  static const int STATE_STOPPED = 1;
  static const int STATE_PAUSED = 2;
  static const int STATE_PLAYING = 3;
  static const int STATE_FAST_FORWARDING = 4;
  static const int STATE_REWINDING = 5;
  static const int STATE_BUFFERING = 6;
  static const int STATE_ERROR = 7;

  /// 更新媒体元数据（曲目标题、艺术家、专辑等）
  /// 
  /// [title] 曲目标题（必填）
  /// [artist] 艺术家名称（可选）
  /// [album] 专辑名称（可选）
  /// [duration] 曲目时长（毫秒）
  static Future<void> updateMediaMetadata({
    required String title,
    String? artist,
    String? album,
    int duration = 0,
  }) async {
    try {
      await _channel.invokeMethod('updateMediaMetadata', {
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
      });
    } on PlatformException catch (e) {
      print("Failed to update media metadata: '${e.message}'.");
    }
  }

  /// 更新播放状态
  /// 
  /// [state] 播放状态（使用 STATE_* 常量）
  /// [position] 当前播放位置（毫秒）
  /// [speed] 播放速度（1.0 为正常速度）
  static Future<void> updatePlaybackState({
    required int state,
    required int position,
    double speed = 1.0,
  }) async {
    try {
      await _channel.invokeMethod('updatePlaybackState', {
        'state': state,
        'position': position,
        'speed': speed,
      });
    } on PlatformException catch (e) {
      print("Failed to update playback state: '${e.message}'.");
    }
  }
}