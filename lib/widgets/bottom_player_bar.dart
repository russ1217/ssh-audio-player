import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class BottomPlayerBar extends StatelessWidget {
  const BottomPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
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
                  // 上一曲
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: provider.currentIndex > 0
                        ? () => provider.playPreviousInPlaylist()
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
                    onPressed: provider.currentIndex < provider.playlist.length - 1
                        ? () => provider.playNextInPlaylist()
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
              // 当前播放文件信息和定时器
              if (provider.currentPlayingFile != null)
                Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          provider.currentPlayingFile!.isAudio
                              ? Icons.audiotrack
                              : Icons.movie,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.currentPlayingFile!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // 定时器指示器
                        StreamBuilder<Duration?>(
                          stream: provider.countdownUpdateStream,
                          initialData: provider.sleepTimerRemaining,
                          builder: (context, snapshot) {
                            final remaining = snapshot.data;
                            if (remaining == null || remaining <= Duration.zero) {
                              return const SizedBox.shrink();
                            }
                            
                            return GestureDetector(
                              onTap: () {
                                provider.stopTimer();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('⏰ 定时关闭已取消'),
                                    duration: Duration(seconds: 2),
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
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.orange,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
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
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
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
}
