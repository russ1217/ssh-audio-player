import 'dart:async';
import 'package:flutter/foundation.dart';

class TimerService {
  Timer? _sleepTimer;
  Timer? _fileCountTimer;
  Timer? _countdownUpdateTimer; // 用于每秒更新倒计时的定时器
  
  int _maxFiles = 0;
  int _playedFiles = 0;
  Duration? _sleepTimerDuration; // 保存初始的定时时长
  DateTime? _sleepTimerStartTime; // 记录定时器开始时间
  
  final _timerCompleteController = StreamController<TimerType>.broadcast();
  Stream<TimerType> get timerCompleteStream => _timerCompleteController.stream;
  
  // 倒计时更新流，每秒发送一次剩余时间
  final _countdownUpdateController = StreamController<Duration?>.broadcast();
  Stream<Duration?> get countdownUpdateStream => _countdownUpdateController.stream;

  bool get isSleepTimerActive => _sleepTimer?.isActive ?? false;
  bool get isFileCountTimerActive => _maxFiles > 0;
  int get playedFilesCount => _playedFiles;
  int get maxFilesCount => _maxFiles;
  
  /// 获取睡眠定时器剩余时间
  Duration? get sleepTimerRemaining {
    if (_sleepTimer == null || !_sleepTimer!.isActive || _sleepTimerStartTime == null) {
      return null;
    }
    
    final elapsed = DateTime.now().difference(_sleepTimerStartTime!);
    final remaining = _sleepTimerDuration! - elapsed;
    
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  void setFileCountTimer(int maxFiles) {
    _maxFiles = maxFiles;
    _playedFiles = 0;
  }

  void clearFileCountTimer() {
    _maxFiles = 0;
    _playedFiles = 0;
  }

  void incrementPlayedFiles() {
    _playedFiles++;
    
    if (_maxFiles > 0 && _playedFiles >= _maxFiles) {
      _timerCompleteController.add(TimerType.fileCount);
      stop();
    }
  }

  void setSleepTimer(Duration duration) {
    // 取消之前的定时器
    _sleepTimer?.cancel();
    _countdownUpdateTimer?.cancel();
    
    // 保存初始设置
    _sleepTimerDuration = duration;
    _sleepTimerStartTime = DateTime.now();
    
    debugPrint('⏰ 设置睡眠定时器: ${_formatDuration(duration)}');
    
    // 启动主定时器（到时触发）
    _sleepTimer = Timer(duration, () {
      debugPrint('⏰ 睡眠定时器到期');
      _timerCompleteController.add(TimerType.sleep);
      _cleanupTimers();
    });
    
    // 启动倒计时更新定时器（每秒更新）
    _countdownUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = sleepTimerRemaining;
      if (remaining != null) {
        _countdownUpdateController.add(remaining);
        
        // 如果时间到了，停止更新定时器
        if (remaining <= Duration.zero) {
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
    
    // 立即发送一次当前剩余时间
    _countdownUpdateController.add(sleepTimerRemaining);
  }

  void stop() {
    _cleanupTimers();
    clearFileCountTimer();
  }

  void stopSleepTimer() {
    debugPrint('⏰ 取消睡眠定时器');
    _cleanupTimers();
  }
  
  /// 清理所有定时器
  void _cleanupTimers() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _countdownUpdateTimer?.cancel();
    _countdownUpdateTimer = null;
    _sleepTimerDuration = null;
    _sleepTimerStartTime = null;
    _countdownUpdateController.add(null); // 通知 UI 定时器已清除
  }

  void dispose() {
    stop();
    _timerCompleteController.close();
    _countdownUpdateController.close();
  }
  
  /// 格式化时长显示
  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}小时${d.inMinutes % 60}分钟';
    }
    return '${d.inMinutes}分钟';
  }
}

enum TimerType {
  sleep,
  fileCount,
}
