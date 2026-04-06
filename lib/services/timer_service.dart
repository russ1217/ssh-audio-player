import 'dart:async';

class TimerService {
  Timer? _sleepTimer;
  Timer? _fileCountTimer;
  
  int _maxFiles = 0;
  int _playedFiles = 0;
  
  final _timerCompleteController = StreamController<TimerType>.broadcast();
  Stream<TimerType> get timerCompleteStream => _timerCompleteController.stream;

  bool get isSleepTimerActive => _sleepTimer?.isActive ?? false;
  bool get isFileCountTimerActive => _maxFiles > 0;
  int get playedFilesCount => _playedFiles;
  int get maxFilesCount => _maxFiles;

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
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, () {
      _timerCompleteController.add(TimerType.sleep);
    });
  }

  Duration? getSleepTimerRemaining() {
    if (_sleepTimer == null || !_sleepTimer!.isActive) {
      return null;
    }
    // 这里需要跟踪剩余时间，简化实现
    return null;
  }

  void stop() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    clearFileCountTimer();
  }

  void stopSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  void dispose() {
    stop();
    _timerCompleteController.close();
  }
}

enum TimerType {
  sleep,
  fileCount,
}
