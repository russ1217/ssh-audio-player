import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart' as app_provider;
import '../services/timer_service.dart';

class BottomPlayerBar extends StatelessWidget {
  const BottomPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<app_provider.AppProvider>(
      builder: (context, provider, child) {
        // 如果没有正在播放的文件，隐藏底部栏
        if (provider.currentPlayingFile == null) {
          return const SizedBox.shrink();
        }

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: provider.position.inMilliseconds.toDouble(),
                      max: provider.duration.inMilliseconds.toDouble() > 0
                          ? provider.duration.inMilliseconds.toDouble()
                          : 1,
                      onChanged: (value) {
                        provider.seekTo(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(provider.position),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          _formatDuration(provider.duration),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 播放控制按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ✅ 新增：循环模式切换按钮
                  IconButton(
                    icon: _buildRepeatIcon(provider.repeatMode),
                    onPressed: () => provider.toggleRepeatMode(),
                    tooltip: _getRepeatTooltip(provider.repeatMode),
                    color: provider.repeatMode != app_provider.RepeatMode.none 
                        ? Theme.of(context).colorScheme.primary 
                        : null,
                  ),
                  // 上一曲
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: provider.currentIndex > 0 || provider.repeatMode == app_provider.RepeatMode.all
                        ? () {
                            if (provider.currentIndex > 0) {
                              provider.playPreviousInPlaylist();
                            } else if (provider.repeatMode == app_provider.RepeatMode.all && provider.playlist.isNotEmpty) {
                              // 循环模式下，从第一首可以跳到最后一首
                              provider.playFromPlaylistIndex(provider.playlist.length - 1);
                            }
                          }
                        : null,
                    tooltip: '上一曲',
                  ),
                  // 快退
                  IconButton(
                    icon: const Icon(Icons.replay_10),
                    onPressed: () => provider.seekBackward(const Duration(seconds: 10)),
                    tooltip: '快退10秒',
                  ),
                  // 播放/暂停
                  FloatingActionButton(
                    onPressed: () => provider.togglePlayPause(),
                    mini: true,
                    child: Icon(
                      provider.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  // 快进
                  IconButton(
                    icon: const Icon(Icons.forward_10),
                    onPressed: () => provider.seekForward(const Duration(seconds: 10)),
                    tooltip: '快进10秒',
                  ),
                  // 下一曲
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: provider.playlist.isNotEmpty &&
                            (provider.currentIndex < provider.playlist.length - 1 ||
                                provider.repeatMode == app_provider.RepeatMode.all ||
                                provider.repeatMode == app_provider.RepeatMode.one)
                        ? () {
                            if (provider.currentIndex < provider.playlist.length - 1) {
                              provider.playNextInPlaylist();
                            } else if (provider.repeatMode == app_provider.RepeatMode.all ||
                                provider.repeatMode == app_provider.RepeatMode.one) {
                              // 循环模式下（全部或单曲），从最后一首可以跳到第一首
                              provider.playFromPlaylistIndex(0);
                            }
                          }
                        : null,
                    tooltip: '下一曲',
                  ),
                  // 停止
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: () => provider.stopPlayback(),
                    tooltip: '停止',
                  ),
                ],
              ),
              // 定时器指示器和退出按钮 (居右对齐)
              if (provider.currentPlayingFile != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Spacer(),
                      // 定时器指示器
                      StreamBuilder<TimerInfo?>(
                        stream: provider.countdownUpdateStream,
                        initialData: provider.sleepTimerRemaining != null 
                            ? TimerInfo.sleep(remaining: provider.sleepTimerRemaining)
                            : null,
                        builder: (context, snapshot) {
                          final timerInfo = snapshot.data;
                          if (timerInfo == null) {
                            return const SizedBox.shrink();
                          }
                          
                          // 根据定时器类型显示不同的内容
                          Widget indicator;
                          
                          if (timerInfo.type == TimerType.sleep) {
                            // 睡眠定时器：显示倒计时
                            final remaining = timerInfo.remaining;
                            if (remaining == null || remaining <= Duration.zero) {
                              return const SizedBox.shrink();
                            }
                            
                            indicator = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.timer,
                                  size: 14,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatCountdown(remaining),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            );
                          } else {
                            // 文件计数定时器：显示进度
                            indicator = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.playlist_play,
                                  size: 14,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${timerInfo.played}/${timerInfo.total}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            );
                          }
                          
                          return GestureDetector(
                            onTap: () {
                              provider.stopTimer();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    timerInfo.type == TimerType.sleep
                                        ? '⏰ 定时关闭已取消'
                                        : '📁 文件计数定时器已取消',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: timerInfo.type == TimerType.sleep
                                    ? Colors.orange.withOpacity(0.2)
                                    : Colors.blue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: timerInfo.type == TimerType.sleep
                                      ? Colors.orange
                                      : Colors.blue,
                                  width: 1,
                                ),
                              ),
                              child: indicator,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  
  String _formatCountdown(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// ✅ 新增：根据循环模式构建图标
  Widget _buildRepeatIcon(app_provider.RepeatMode mode) {
    switch (mode) {
      case app_provider.RepeatMode.none:
        return const Icon(Icons.repeat, color: Colors.grey);
      case app_provider.RepeatMode.all:
        return const Icon(Icons.repeat, color: Colors.blue);
      case app_provider.RepeatMode.one:
        return Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.repeat_one, color: Colors.blue),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '1',
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  /// ✅ 新增：获取循环模式的提示文本
  String _getRepeatTooltip(app_provider.RepeatMode mode) {
    switch (mode) {
      case app_provider.RepeatMode.none:
        return '点击开启循环播放';
      case app_provider.RepeatMode.all:
        return '当前：循环播放列表（点击切换单曲循环）';
      case app_provider.RepeatMode.one:
        return '当前：单曲循环（点击关闭循环）';
    }
  }
}
