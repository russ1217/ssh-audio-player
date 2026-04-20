package com.audioplayer.ssh_audio_player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.util.Log
import androidx.core.app.NotificationCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

class BackgroundPlayerService : Service() {

    companion object {
        private const val TAG = "BackgroundPlayerService"
        // ✅ SSH监控定时器间隔（30秒）
        private const val SSH_CHECK_INTERVAL_MS = 30_000L
    }

    private lateinit var wakeLock: PowerManager.WakeLock
    private val CHANNEL_ID = "PlayerServiceChannel"
    private val NOTIFICATION_ID = 1
    
    // ✅ MethodChannel用于向Flutter层发送媒体控制命令
    private var mediaControlChannel: MethodChannel? = null
    
    // ✅ SSH监控MethodChannel
    private var sshCheckChannel: MethodChannel? = null
    
    // 网络回调，用于保持网络连接活跃
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var connectivityManager: ConnectivityManager? = null
    
    // ✅ MediaSessionCompat 用于向蓝牙设备广播媒体信息
    private var mediaSession: MediaSessionCompat? = null
    
    // ✅ 当前播放状态（用于构建通知）
    private var currentTitle: String = "SSH Player"
    private var isCurrentlyPlaying: Boolean = false
    
    // ✅ SSH监控定时器
    private val handler = Handler(Looper.getMainLooper())
    private var sshCheckRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        println("🚀 BackgroundPlayerService onCreate 被调用")
        createNotificationChannel()
        
        // Acquire Wake Lock to keep CPU running
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Player::WakeLock")
        wakeLock.setReferenceCounted(false)
        
        // Register network callback to keep network active
        registerNetworkCallback()
        
        // ✅ 初始化 MediaSessionCompat
        initializeMediaSession()
        
        // ✅ 关键修复：将当前服务实例保存到 MediaSessionHelper
        MediaSessionHelper.backgroundService = this
        println("✅ MediaSessionHelper.backgroundService 已设置为当前服务实例")
        
        // ✅ 启动SSH监控定时器
        startSshMonitoring()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Start Foreground with Notification
        val notification = buildMediaStyleNotification().build()
        startForeground(NOTIFICATION_ID, notification)
        
        // Keep CPU on indefinitely (until service is stopped)
        if (!wakeLock.isHeld) {
            wakeLock.acquire() // 无超时限制，直到手动释放
        }

        return START_NOT_STICKY // ✅ 关键修复：改为 NOT_STICKY，避免系统自动重启服务
    }

    /**
     * ✅ 关键修复：当用户从最近任务中移除应用时调用
     * 必须在此停止播放和服务，防止后台继续播放
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "🛑 应用被用户从最近任务中移除，停止服务和播放")
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "🗑️ BackgroundPlayerService onDestroy 被调用")
        
        // ✅ 停止SSH监控定时器
        stopSshMonitoring()
        
        // ✅ 确保释放 Wake Lock
        if (wakeLock.isHeld) {
            wakeLock.release()
            Log.d(TAG, "🔓 Wake Lock 已释放")
        }
        
        // ✅ 取消网络回调
        unregisterNetworkCallback()
        
        // ✅ 清理 MediaSession
        releaseMediaSession()
        
        // ✅ 清除引用
        MediaSessionHelper.backgroundService = null
        
        // ✅ 停止前台服务
        try {
            stopForeground(true)
            Log.d(TAG, "✅ 前台服务已停止")
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ 停止前台服务失败: ${e.message}")
        }
        
        Log.d(TAG, "✅ BackgroundPlayerService 完全销毁")
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    /**
     * ✅ 初始化 MediaSessionCompat，使蓝牙设备能获取播放信息
     */
    private fun initializeMediaSession() {
        try {
            mediaSession = MediaSessionCompat(this, "RussSSHPlayer").apply {
                // 设置会话标志位
                setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or 
                        MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
                
                // 设置初始播放状态（暂停）
                val initialState = PlaybackStateCompat.Builder()
                    .setState(PlaybackStateCompat.STATE_PAUSED, 0, 1.0f)
                    .build()
                setPlaybackState(initialState)
                
                // ✅ 设置 MediaSession 回调，处理来自通知栏和蓝牙设备的控制命令
                setCallback(object : MediaSessionCompat.Callback() {
                    override fun onPlay() {
                        super.onPlay()
                        println("▶️ MediaSession: 收到播放命令")
                        handleMediaControl("play")
                    }
                    
                    override fun onPause() {
                        super.onPause()
                        println("⏸️ MediaSession: 收到暂停命令")
                        handleMediaControl("pause")
                    }
                    
                    override fun onStop() {
                        super.onStop()
                        println("⏹️ MediaSession: 收到停止命令")
                        handleMediaControl("stop")
                    }
                    
                    override fun onSkipToNext() {
                        super.onSkipToNext()
                        println("⏭️ MediaSession: 收到下一曲命令")
                        handleMediaControl("next")
                    }
                    
                    override fun onSkipToPrevious() {
                        super.onSkipToPrevious()
                        println("⏮️ MediaSession: 收到上一曲命令")
                        handleMediaControl("previous")
                    }
                })
                
                // 激活会话
                isActive = true
                
                println("✅ MediaSessionCompat 已初始化")
            }
        } catch (e: Exception) {
            e.printStackTrace()
            println("❌ MediaSessionCompat 初始化失败: ${e.message}")
        }
    }

    /**
     * ✅ 处理媒体控制命令（通过 MethodChannel 转发到 Flutter 层）
     */
    private fun handleMediaControl(action: String) {
        try {
            Log.d(TAG, "📡 准备发送媒体控制命令到Flutter: $action")
            
            // ✅ 通过广播发送媒体控制命令
            val intent = Intent("com.audioplayer.ssh_audio_player.MEDIA_CONTROL").apply {
                putExtra("action", action)
                setPackage(packageName)
            }
            sendBroadcast(intent)
            Log.d(TAG, "📤 已广播媒体控制命令: $action")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 发送媒体控制命令失败: ${e.message}")
        }
    }

    /**
     * ✅ 构建带媒体控制按钮的通知
     */
    private fun buildMediaStyleNotification(): NotificationCompat.Builder {
        // 创建点击通知时打开应用的 PendingIntent
        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        // ✅ 创建媒体控制动作的 PendingIntent
        val playIntent = createMediaControlPendingIntent("play")
        val pauseIntent = createMediaControlPendingIntent("pause")
        val stopIntent = createMediaControlPendingIntent("stop")
        val nextIntent = createMediaControlPendingIntent("next")
        val previousIntent = createMediaControlPendingIntent("previous")
        
        // 根据播放状态选择显示播放或暂停按钮
        val playbackAction = if (isCurrentlyPlaying) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause,
                "Pause",
                pauseIntent
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play,
                "Play",
                playIntent
            )
        }
        
        // 恢复使用标准的 NotificationCompat，移除 MediaStyle 依赖
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(currentTitle)
            .setContentText("SSH Player - Playing")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true) // 设置为持续通知，防止被清除
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // 锁屏可见
            // 添加媒体控制按钮
            .addAction(
                android.R.drawable.ic_media_previous,
                "Previous",
                previousIntent
            )
            .addAction(playbackAction)
            .addAction(
                android.R.drawable.ic_media_next,
                "Next",
                nextIntent
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopIntent
            )
    }
    
    /**
     * ✅ 创建媒体控制 PendingIntent
     */
    private fun createMediaControlPendingIntent(action: String): PendingIntent {
        val intent = Intent("com.audioplayer.ssh_audio_player.MEDIA_CONTROL").apply {
            putExtra("action", action)
            setPackage(packageName)
        }
        
        return PendingIntent.getBroadcast(
            this,
            action.hashCode(), // 使用 action 的哈希码作为 requestCode，确保唯一性
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    /**
     * ✅ 更新通知内容（当播放状态或曲目变化时调用）
     */
    fun updateNotification(title: String, isPlaying: Boolean) {
        currentTitle = title
        isCurrentlyPlaying = isPlaying
        
        // 重新构建并更新通知
        val notification = buildMediaStyleNotification().build()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
        
        println("🔔 通知已更新: $title, 播放状态: ${if (isPlaying) "播放中" else "暂停"}")
    }

    /**
     * ✅ 更新媒体元数据（曲目标题、艺术家等）
     * 此方法将通过 MethodChannel 从 Flutter 层调用
     */
    fun updateMediaMetadata(title: String, artist: String?, album: String?, duration: Long) {
        try {
            println("📻 开始更新媒体元数据: title=$title, artist=$artist, duration=$duration")
            
            mediaSession?.let { session ->
                val metadata = MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist ?: "Unknown Artist")
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album ?: "Unknown Album")
                    .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                    .build()
                
                session.setMetadata(metadata)
                println("✅ MediaSessionCompat 元数据已设置: $title")
                
                // ✅ 同时更新通知
                println("🔔 准备更新通知...")
                updateNotification(title, isCurrentlyPlaying)
                
                println("📻 MediaSessionCompat 元数据更新完成: $title")
            } ?: run {
                println("❌ MediaSessionCompat 未初始化，无法更新元数据")
            }
        } catch (e: Exception) {
            e.printStackTrace()
            println("❌ 更新媒体元数据失败: ${e.message}")
        }
    }

    /**
     * ✅ 更新播放状态
     */
    fun updatePlaybackState(state: Int, position: Long, speed: Float) {
        try {
            mediaSession?.let { session ->
                val playbackState = PlaybackStateCompat.Builder()
                    .setState(state, position, speed)
                    .build()
                
                session.setPlaybackState(playbackState)
                
                // ✅ 更新内部播放状态标记
                isCurrentlyPlaying = (state == PlaybackStateCompat.STATE_PLAYING)
                
                // ✅ 更新通知以反映新的播放状态
                updateNotification(currentTitle, isCurrentlyPlaying)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            println("❌ 更新播放状态失败: ${e.message}")
        }
    }

    /**
     * ✅ 释放 MediaSession 资源
     */
    private fun releaseMediaSession() {
        try {
            mediaSession?.let {
                it.isActive = false
                it.release()
                println("🗑️ MediaSession 已释放")
            }
            mediaSession = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * 注册网络回调以保持网络连接活跃
     */
    private fun registerNetworkCallback() {
        try {
            connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val networkRequest = NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                    .build()
                
                networkCallback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        super.onAvailable(network)
                        // 网络可用时可以做些事情（可选）
                    }
                    
                    override fun onLost(network: Network) {
                        super.onLost(network)
                        // 网络丢失时的处理（可选）
                    }
                }
                
                connectivityManager?.registerNetworkCallback(networkRequest, networkCallback!!)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    /**
     * 取消注册网络回调
     */
    private fun unregisterNetworkCallback() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                networkCallback?.let {
                    connectivityManager?.unregisterNetworkCallback(it)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Player Service Channel",
                NotificationManager.IMPORTANCE_LOW // 低重要性，减少打扰
            ).apply {
                description = "Keeps SSH connection and playback alive in background"
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }
    
    /**
     * ✅ 启动SSH监控定时器
     * 每30秒通过MethodChannel调用Flutter层的SSH检查方法
     */
    private fun startSshMonitoring() {
        println("💓 启动SSH监控定时器（间隔: ${SSH_CHECK_INTERVAL_MS / 1000}秒）")
        
        sshCheckRunnable = object : Runnable {
            override fun run() {
                try {
                    println("🔍 [Native] 定时触发SSH连接检查...")
                    
                    // ✅ 通过MethodChannel调用Flutter层的方法
                    // 注意：这里需要获取FlutterEngine的MethodChannel
                    // 由于Service中无法直接访问FlutterEngine，我们通过广播通知MainActivity
                    
                    val intent = Intent("com.audioplayer.ssh_audio_player.SSH_CHECK").apply {
                        setPackage(packageName)
                    }
                    sendBroadcast(intent)
                    println("📤 [Native] 已广播SSH检查请求")
                    
                } catch (e: Exception) {
                    Log.e(TAG, "❌ SSH监控执行失败: ${e.message}")
                    e.printStackTrace()
                }
                
                // 继续调度下一次执行
                handler.postDelayed(this, SSH_CHECK_INTERVAL_MS)
            }
        }
        
        // 立即执行第一次检查，然后每隔30秒执行一次
        handler.post(sshCheckRunnable!!)
    }
    
    /**
     * ✅ 停止SSH监控定时器
     */
    private fun stopSshMonitoring() {
        println("🛑 停止SSH监控定时器")
        sshCheckRunnable?.let {
            handler.removeCallbacks(it)
        }
        sshCheckRunnable = null
    }
}
