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
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class BackgroundPlayerService : Service() {

    private lateinit var wakeLock: PowerManager.WakeLock
    private val CHANNEL_ID = "PlayerServiceChannel"
    private val NOTIFICATION_ID = 1
    
    // 网络回调，用于保持网络连接活跃
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var connectivityManager: ConnectivityManager? = null
    
    // ✅ MediaSession 用于向蓝牙设备广播媒体信息
    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        
        // Acquire Wake Lock to keep CPU running
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Player::WakeLock")
        wakeLock.setReferenceCounted(false)
        
        // Register network callback to keep network active
        registerNetworkCallback()
        
        // ✅ 初始化 MediaSession
        initializeMediaSession()
        
        // ✅ 注册到 MediaSessionHelper，使 MainActivity 可以访问
        MediaSessionHelper.backgroundService = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Start Foreground with Notification
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Player Active")
            .setContentText("SSH and Playback running in background")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true) // 设置为持续通知，防止被清除
            .build()

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
        println("🛑 应用被用户从最近任务中移除，停止服务和播放")
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        unregisterNetworkCallback()
        
        // ✅ 清理 MediaSession
        releaseMediaSession()
        
        // ✅ 清除引用
        MediaSessionHelper.backgroundService = null
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    /**
     * ✅ 初始化 MediaSession，使蓝牙设备能获取播放信息
     */
    private fun initializeMediaSession() {
        try {
            mediaSession = MediaSession(this, "RussSSHPlayer").apply {
                // 设置会话标志位
                setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or 
                        MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
                
                // 设置初始播放状态（暂停）
                setState(PlaybackState.STATE_PAUSED, 0, 1.0f)
                
                // 激活会话
                isActive = true
                
                println("✅ MediaSession 已初始化")
            }
        } catch (e: Exception) {
            e.printStackTrace()
            println("❌ MediaSession 初始化失败: ${e.message}")
        }
    }

    /**
     * ✅ 更新媒体元数据（曲目标题、艺术家等）
     * 此方法将通过 MethodChannel 从 Flutter 层调用
     */
    fun updateMediaMetadata(title: String, artist: String?, album: String?, duration: Long) {
        try {
            mediaSession?.let { session ->
                val metadata = MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, artist ?: "Unknown Artist")
                    .putString(MediaMetadata.METADATA_KEY_ALBUM, album ?: "Unknown Album")
                    .putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
                    .build()
                
                session.setMetadata(metadata)
                println("📻 MediaSession 元数据已更新: $title")
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
                val playbackState = PlaybackState.Builder()
                    .setState(state, position, speed)
                    .build()
                
                session.setPlaybackState(playbackState)
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
}