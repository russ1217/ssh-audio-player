package com.audioplayer.ssh_audio_player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val BATTERY_CHANNEL = "com.ssh_audio_player/battery_optimization"
    private val BACKGROUND_SERVICE_CHANNEL = "com.example.player/background_service"
    // ✅ 新增：媒体会话通道，用于更新曲目信息
    private val MEDIA_SESSION_CHANNEL = "com.example.player/media_session"
    // ✅ 新增：Android版本查询通道
    private val ANDROID_VERSION_CHANNEL = "android_version"
    
    // ✅ 媒体控制广播接收器
    private var mediaControlReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // ✅ Android版本查询通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ANDROID_VERSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidVersion" -> {
                    // 返回真实的Android API Level
                    result.success(Build.VERSION.SDK_INT)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // 电池优化通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // 后台服务通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        val serviceIntent = Intent(this, BackgroundPlayerService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopService" -> {
                    try {
                        val serviceIntent = Intent(this, BackgroundPlayerService::class.java)
                        stopService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // ✅ 媒体会话通道 - 用于更新蓝牙设备显示的曲目信息
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SESSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateMediaMetadata" -> {
                    try {
                        val title = call.argument<String>("title") ?: ""
                        val artist = call.argument<String>("artist")
                        val album = call.argument<String>("album")
                        val duration = call.argument<Int>("duration") ?: 0
                        
                        // 获取正在运行的服务实例
                        val serviceIntent = Intent(this, BackgroundPlayerService::class.java)
                        // 注意：这里需要通过静态方法或广播来更新服务中的 MediaSession
                        // 简化方案：直接通过 Application Context 访问单例
                        updateMediaSessionMetadata(title, artist, album, duration.toLong())
                        
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MEDIA_SESSION_ERROR", e.message, null)
                    }
                }
                "updatePlaybackState" -> {
                    try {
                        val state = call.argument<Int>("state") ?: 0
                        val position = call.argument<Int>("position") ?: 0
                        val speed = call.argument<Double>("speed") ?: 1.0
                        
                        updateMediaSessionPlaybackState(state, position.toLong(), speed.toFloat())
                        
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MEDIA_SESSION_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // ✅ 注册媒体控制广播接收器
        registerMediaControlReceiver()
    }
    
    /**
     * ✅ 注册媒体控制广播接收器
     */
    private fun registerMediaControlReceiver() {
        mediaControlReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.getStringExtra("action")
                println("📡 MainActivity 收到媒体控制命令: $action")
                
                // 通过 MethodChannel 将命令转发到 Flutter 层
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    val channel = MethodChannel(messenger, "com.audioplayer.ssh_audio_player/media_control")
                    channel.invokeMethod("onMediaControl", mapOf("action" to action))
                }
            }
        }
        
        val filter = IntentFilter("com.audioplayer.ssh_audio_player.MEDIA_CONTROL")
        
        // ✅ Android 14+ (API 34+) 要求指定 RECEIVER_EXPORTED 或 RECEIVER_NOT_EXPORTED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(mediaControlReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(mediaControlReceiver, filter)
        }
        
        println("✅ 媒体控制广播接收器已注册")
    }
    
    /**
     * ✅ 注销媒体控制广播接收器
     */
    private fun unregisterMediaControlReceiver() {
        mediaControlReceiver?.let {
            try {
                unregisterReceiver(it)
                println("🗑️ 媒体控制广播接收器已注销")
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        mediaControlReceiver = null
    }
    
    /**
     * ✅ 更新 MediaSession 元数据（曲目标题等）
     */
    private fun updateMediaSessionMetadata(title: String, artist: String?, album: String?, duration: Long) {
        // 由于 Service 是独立组件，我们需要通过静态引用或单例模式访问
        // 这里使用简单的方式：通过 Application 上下文保存引用
        MediaSessionHelper.updateMetadata(title, artist, album, duration)
    }
    
    /**
     * ✅ 更新播放状态
     */
    private fun updateMediaSessionPlaybackState(state: Int, position: Long, speed: Float) {
        MediaSessionHelper.updatePlaybackState(state, position, speed)
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true
        } else {
            true // Android 6.0 以下不需要电池优化
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent().apply {
                action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        println("🗑️ MainActivity onDestroy 被调用")
        
        try {
            // ✅ 关键修复：Activity销毁时也要停止前台服务
            // 这确保了即使服务还在启动过程中，也能被正确停止
            val serviceIntent = Intent(this, BackgroundPlayerService::class.java)
            stopService(serviceIntent)
            println("✅ MainActivity: 已请求停止后台服务")
        } catch (e: Exception) {
            println("⚠️ MainActivity: 停止服务失败: ${e.message}")
        }
        
        try {
            // ✅ 注销广播接收器
            unregisterMediaControlReceiver()
        } catch (e: Exception) {
            println("⚠️ MainActivity: 注销广播接收器失败: ${e.message}")
        }
        
        println("✅ MainActivity 清理完成")
        
        // ✅ 关键修复：立即强制杀死进程，不等待任何延迟
        println("💀 MainActivity: 立即强制杀死应用进程")
        android.os.Process.killProcess(android.os.Process.myPid())
    }

}

/**
 * ✅ MediaSession 辅助类，用于在 Activity 和 Service 之间共享 MediaSession
 */
object MediaSessionHelper {
    var backgroundService: BackgroundPlayerService? = null
    
    fun updateMetadata(title: String, artist: String?, album: String?, duration: Long) {
        println("📡 MediaSessionHelper.updateMetadata 被调用: title=$title")
        if (backgroundService == null) {
            println("❌ backgroundService 为 null，无法更新元数据")
        } else {
            println("✅ 找到 backgroundService 实例，开始更新")
            backgroundService?.updateMediaMetadata(title, artist, album, duration)
        }
    }
    
    fun updatePlaybackState(state: Int, position: Long, speed: Float) {
        println("📡 MediaSessionHelper.updatePlaybackState 被调用: state=$state")
        backgroundService?.updatePlaybackState(state, position, speed)
    }
}