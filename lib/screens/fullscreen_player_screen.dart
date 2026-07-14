import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/app_provider.dart';
import '../services/audio_player_base.dart';

/// 全屏播放屏幕
/// 功能：横屏、大字体显示秒数（秒表）、进度条、总时长、防止锁屏
class FullscreenPlayerScreen extends StatefulWidget {
  const FullscreenPlayerScreen({super.key});

  @override
  State<FullscreenPlayerScreen> createState() => _FullscreenPlayerScreenState();
}

class _FullscreenPlayerScreenState extends State<FullscreenPlayerScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // ✅ 启用屏幕常亮，防止锁屏
    WakelockPlus.enable();
    debugPrint('✅ 屏幕常亮已启用');
    
    // ✅ 强制横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // ✅ 隐藏状态栏和导航栏，实现真正的全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // ✅ 恢复竖屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // ✅ 恢复系统UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    // ✅ 禁用屏幕常亮
    WakelockPlus.disable();
    debugPrint('✅ 屏幕常亮已禁用');
    
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // ✅ 当应用恢复到前台时，重新启用屏幕常亮和横屏
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.currentPlayingFile == null) {
            return const Center(
              child: Text(
                '没有正在播放的文件',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            );
          }

          return SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ✅ 顶部：文件名显示
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Text(
                    provider.currentPlayingFile!.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                
                const Spacer(),
                
                // ✅ 中间：超大字体显示当前播放时间（秒表样式）
                StreamBuilder<Duration>(
                  stream: provider.audioPlayerService.positionStream,
                  initialData: provider.position,
                  builder: (context, snapshot) {
                    final currentPosition = snapshot.data ?? Duration.zero;
                    return Text(
                      _formatTimeAsStopwatch(currentPosition),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 80,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    );
                  },
                ),
                
                const Spacer(),
                
                // ✅ 底部：进度条和总时长
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    children: [
                      // 进度条
                      StreamBuilder<Duration>(
                        stream: provider.audioPlayerService.positionStream,
                        initialData: provider.position,
                        builder: (context, positionSnapshot) {
                          final currentPosition = positionSnapshot.data ?? Duration.zero;
                          
                          return StreamBuilder<Duration>(
                            stream: provider.audioPlayerService.durationStream,
                            initialData: provider.duration,
                            builder: (context, durationSnapshot) {
                              final totalDuration = durationSnapshot.data ?? Duration.zero;
                              
                              return Column(
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 6,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                                      activeTrackColor: Colors.blueAccent,
                                      inactiveTrackColor: Colors.grey[800],
                                      thumbColor: Colors.blueAccent,
                                    ),
                                    child: Slider(
                                      value: totalDuration.inMilliseconds > 0
                                          ? currentPosition.inMilliseconds.toDouble()
                                          : 0,
                                      max: totalDuration.inMilliseconds.toDouble() > 0
                                          ? totalDuration.inMilliseconds.toDouble()
                                          : 1,
                                      onChanged: (value) {
                                        provider.seekTo(Duration(milliseconds: value.toInt()));
                                      },
                                    ),
                                  ),
                                  
                                  // 时间显示：当前时间 / 总时长（右侧对齐）
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatDurationShort(currentPosition),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const Text(
                                          ' / ',
                                          style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          _formatDurationShort(totalDuration),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // ✅ 控制按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 快退10秒
                          IconButton(
                            icon: const Icon(Icons.replay_10, size: 40, color: Colors.white),
                            onPressed: () => provider.seekBackward(const Duration(seconds: 10)),
                          ),
                          
                          // 播放/暂停
                          StreamBuilder<PlayerState>(
                            stream: provider.audioPlayerService.playbackStateStream,
                            initialData: provider.isPlaying ? PlayerState.playing : PlayerState.paused,
                            builder: (context, snapshot) {
                              final state = snapshot.data ?? PlayerState.paused;
                              final isPlaying = state == PlayerState.playing;
                              return FloatingActionButton(
                                onPressed: () => provider.togglePlayPause(),
                                backgroundColor: Colors.blueAccent,
                                child: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  size: 50,
                                  color: Colors.white,
                                ),
                              );
                            },
                          ),
                          
                          // 快进10秒
                          IconButton(
                            icon: const Icon(Icons.forward_10, size: 40, color: Colors.white),
                            onPressed: () => provider.seekForward(const Duration(seconds: 10)),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // 退出全屏按钮
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.fullscreen_exit, color: Colors.white70),
                        label: const Text(
                          '退出全屏',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 格式化为秒表样式：HH:MM:SS 或 MM:SS
  String _formatTimeAsStopwatch(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
    }
    return '${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }

  /// 格式化时长（短格式）
  String _formatDurationShort(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
    }
    return '${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
