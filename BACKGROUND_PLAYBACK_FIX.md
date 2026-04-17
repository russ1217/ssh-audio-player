# 后台播放和 SSH 连接保持方案

## 问题描述
应用在进入后台后，SSH 连接被系统中断，导致流式音频播放停止。

## 解决方案

### 1. Android Manifest 配置增强
**文件**: `android/app/src/main/AndroidManifest.xml`

添加了以下关键配置：
- **网络权限**: `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`
- **前台服务类型**: `foregroundServiceType="mediaPlayback|dataSync"` - 同时支持媒体播放和数据同步
- **明文流量**: `android:usesCleartextTraffic="true"` - 允许本地 HTTP 流式服务
- **网络安全配置**: 引用自定义的 `network_security_config.xml`

### 2. 网络安全配置
**文件**: `android/app/src/main/res/xml/network_security_config.xml`

创建了网络安全配置文件，允许：
- 所有明文流量（用于本地 HTTP 流）
- 特定域名访问：`127.0.0.1`, `localhost`, `172.16.0.4`

### 3. 前台服务增强
**文件**: `android/app/src/main/kotlin/com/example/player/BackgroundPlayerService.kt`

关键改进：
- **网络回调注册**: 使用 `ConnectivityManager.NetworkCallback` 保持网络连接活跃
- **Wake Lock 无超时**: 移除 10 分钟限制，直到服务停止才释放
- **持续通知**: 设置 `setOngoing(true)` 防止通知被清除
- **START_STICKY**: 如果服务被杀死，系统会尝试重启

### 4. 应用生命周期管理
**文件**: `lib/main.dart`

在 `didChangeAppLifecycleState` 中：
- **进入后台** (`paused`): 自动启动前台服务
- **回到前台** (`resumed`): 可选择停止前台服务（当前注释掉以保持连接）

### 5. 自动恢复机制
**已有功能**: `lib/providers/app_provider.dart`

应用已实现完善的自动恢复逻辑：
- 检测 SSH 断开
- 保存播放进度
- 自动重连 SSH（最多 5 次尝试）
- 恢复播放位置

## 工作原理

```
用户操作                    系统行为
────────                  ────────
1. 开始播放              → 建立 SSH 连接 + SFTP 会话
                          → 启动 HTTP 流式服务
                          → just_audio 播放本地 HTTP 流

2. 应用进入后台          → 触发 didChangeAppLifecycleState(paused)
                          → 启动 Foreground Service
                          → 显示持续通知
                          → 注册 Network Callback
                          → 获取 Wake Lock（无超时）

3. 后台播放中            → 前台服务保持进程活跃
                          → Network Callback 保持网络路由
                          → Wake Lock 防止 CPU 休眠
                          → SSH 心跳检测每 60 秒检查连接

4. SSH 意外断开          → 流式服务检测到断开
                          → 触发 onSshDisconnected 回调
                          → AppProvider 保存播放进度
                          → 自动重试 SSH 重连（最多 5 次）
                          → 重连成功后恢复播放

5. 应用回到前台          → 隐藏通知
                          → 前台服务继续运行（可选停止）
```

## 测试步骤

1. **构建并安装应用**:
   ```bash
   flutter clean
   flutter run --release
   ```

2. **测试后台播放**:
   - 连接到 SSH 服务器
   - 开始播放音频文件
   - 按 Home 键进入后台
   - 观察通知栏是否显示 "Player Active"
   - 等待 2-3 分钟，确认播放未中断

3. **验证 SSH 重连**:
   - 在后台播放时，手动断开服务器网络
   - 观察日志中的重连尝试
   - 恢复网络后，确认自动恢复播放

## 注意事项

1. **电池优化**: 即使用了前台服务，仍建议用户关闭电池优化以获得最佳体验
2. **网络环境**: 确保 WiFi 或移动数据在后台可用
3. **内存管理**: 大文件流式播放不会占用过多内存
4. **通知权限**: Android 13+ 需要通知权限才能显示前台服务通知

## 关键代码位置

- 前台服务启动: `lib/main.dart` → `didChangeAppLifecycleState`
- 网络保持: `BackgroundPlayerService.kt` → `registerNetworkCallback`
- SSH 重连: `lib/providers/app_provider.dart` → `_autoResumePlayback`
- 流式服务: `lib/services/streaming_audio_service.dart`

## 故障排查

如果后台播放仍然中断：

1. **检查日志**:
   ```bash
   adb logcat | grep -E "Player|SSH|Foreground"
   ```

2. **验证前台服务**:
   - 下拉通知栏，确认 "Player Active" 通知存在
   - 进入设置 → 应用 → player → 查看是否有前台服务标记

3. **检查电池优化**:
   ```bash
   adb shell dumpsys deviceidle whitelist | grep com.example.player
   ```

4. **网络状态**:
   ```bash
   adb shell dumpsys connectivity | grep -A 5 "NetworkAgentInfo"
   ```

## 进一步优化建议

1. **WiFi Lock**: 如果需要更稳定的 WiFi 连接，可以添加 `WifiLock`
2. **部分 Wake Lock**: 当前使用 `PARTIAL_WAKE_LOCK`，如需屏幕常亮可改用 `FULL_WAKE_LOCK`
3. **自适应心跳**: 根据网络质量动态调整 SSH 心跳间隔
4. **离线缓存**: 对于经常播放的文件，可以考虑本地缓存策略
