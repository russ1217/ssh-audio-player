# 后台播放修复说明

## 问题描述

边下边播状态，进入后台播放后，大约过 2-3 分钟播放后：
- 停止播放
- 或不再有声音，但播放进度条还在继续

## 原因分析

### iOS
1. **缺少后台音频模式**: `Info.plist` 没有配置 `UIBackgroundModes` 的 `audio` 模式
2. **音频会话未配置**: 没有设置 `AVAudioSessionCategory.playback`，系统不知道应用在播放音频

当 iOS 应用进入后台时，如果没有声明后台音频模式，系统会在 2-3 分钟后暂停应用的音频播放以节省电量。

### Android
1. **音频会话未配置**: 没有设置 `stayAwake`，CPU 可能在后台进入休眠状态
2. **未保持唤醒**: 系统可能在 Doze 模式下暂停应用

## 修复方案

### 1. iOS 配置 (ios/Runner/Info.plist)

添加了后台音频模式：

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

这告诉 iOS 系统：这个应用需要在后台继续播放音频。

### 2. Android 配置 (android/app/src/main/AndroidManifest.xml)

已配置以下权限：

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

以及音频服务：

```xml
<service android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
    </intent-filter>
</service>
```

### 注意事项

**just_audio 版本限制**: 
- 当前使用 just_audio 0.9.46，不支持 `AudioContext` API（需要 0.10.x）
- 后台播放完全依赖 iOS/Android 原生配置实现
- 功能正常，但没有精细的音频会话控制

**如需更好的音频控制**，可以升级到 just_audio 0.10.x：
```yaml
just_audio: ^0.10.5  # 支持 AudioContext
```

## 测试方法

### iOS 测试
1. 在真机上运行应用（模拟器不支持后台音频）
2. 开始播放音频
3. 锁定屏幕或切换到其他应用
4. 验证音频继续播放数小时而不中断
5. 检查锁屏界面是否显示播放控制

### Android 测试
1. 开始播放音频
2. 切换到其他应用或锁定屏幕
3. 验证音频继续播放
4. 检查通知栏是否显示播放控制
5. 长时间测试（1-2 小时）确保不会被系统杀死

## 预期效果

✅ 应用进入后台后，音频播放不会被系统暂停
✅ 播放进度条和音频同步进行
✅ 蓝牙音频输出正常
✅ 锁屏界面显示播放控制
✅ 可以长时间后台播放（数小时）
✅ 通知栏显示播放状态

## 注意事项

### iOS
- 必须在**真机**上测试后台音频（模拟器不支持）
- 确保设备没有开启"低电量模式"，可能会限制后台活动
- 用户可以在设置中关闭应用的后台音频权限

### Android
- 某些厂商的定制 ROM（如小米、华为）可能有更严格的后台管理
- 如果仍然被杀死，可能需要在系统设置中将应用加入"白名单"
- 建议在电池优化设置中将应用设为"不优化"

## 其他相关修复

### SSH 心跳检测
- 每 60 秒检查一次 SSH 连接状态
- 断开自动重连
- 避免播放远程文件时因 SSH 断开而中断

### 后台预下载
- 50MB 以下文件播放时，后台预下载后续文件
- 减少播放间隔，实现无缝连续播放
- 即使 SSH 短暂断开，已下载的文件仍可正常播放

## 相关文件

- `ios/Runner/Info.plist` - iOS 后台音频配置
- `android/app/src/main/AndroidManifest.xml` - Android 权限配置
- `lib/services/audio_player_service_impl.dart` - 音频会话配置
- `lib/services/ssh_service.dart` - SSH 心跳检测
- `lib/providers/app_provider.dart` - 缓存和预下载管理
