# 网络状态检测与自动恢复功能

## 功能概述

本应用现已支持网络状态监控，当检测到网络断开后恢复时，会自动重新连接SSH服务器并恢复之前的播放状态。

## 实现原理

### 1. 网络监控服务 (NetworkMonitorService)

- **位置**: `lib/services/network_monitor_service.dart`
- **依赖**: `connectivity_plus: ^5.0.2`
- **功能**:
  - 实时监听网络状态变化（WiFi、移动数据、以太网、VPN）
  - 通过 Stream 广播网络连接/断开事件
  - 提供手动检查网络连接的方法

### 2. AppProvider 集成

在 `AppProvider` 中集成了网络监控：

```dart
// 初始化网络监控
_setupNetworkMonitor();

// 网络断开处理
_handleNetworkDisconnected() {
  // 保存播放状态标记
  _shouldResumeAfterReconnect = true;
}

// 网络恢复处理
_handleNetworkReconnected() async {
  // 1. 检查是否需要恢复
  // 2. 自动重连 SSH
  // 3. 恢复流式播放
  // 4. 恢复到断点位置
}
```

### 3. 自动恢复流程

```
用户正在播放远程音频
         ↓
    网络突然断开
         ↓
  NetworkMonitor 检测到断开
         ↓
  标记需要恢复 (_shouldResumeAfterReconnect = true)
         ↓
    网络恢复正常
         ↓
  NetworkMonitor 检测到恢复
         ↓
  自动重连 SSH 服务器 (最多30秒超时)
         ↓
  SSH 重连成功
         ↓
  重新启动流式播放服务
         ↓
  恢复到断开前的播放进度
         ↓
    播放继续 ✅
```

## 使用场景

### 场景 1: WiFi 切换
- 用户从家庭 WiFi 切换到移动数据
- 应用自动检测网络变化并重连

### 场景 2: 短暂断网
- 路由器重启或网络波动
- 网络恢复后自动继续播放

### 场景 3: VPN 连接
- 用户开启/关闭 VPN
- 应用能识别 VPN 连接状态并相应处理

## 技术细节

### 网络状态监听
```dart
_connectivity.onConnectivityChanged.listen((results) {
  // 处理网络状态变化
});
```

### 支持的连接类型
- ✅ WiFi
- ✅ 移动数据 (4G/5G)
- ✅ 以太网
- ✅ VPN
- ❌ 无连接

### SSH 重连机制
- **超时时间**: 30秒
- **重试策略**: 由 SSH 心跳检测机制配合（最多5次，每次间隔10秒）
- **播放恢复**: 保持原有播放进度位置

## 注意事项

1. **仅在 SSH 模式下生效**
   - 本地文件播放不受网络状态影响
   - 只有在远程 SSH 模式下才会触发自动恢复

2. **防抖保护**
   - 使用 `_isAutoResuming` 标志避免重复恢复操作
   - 网络频繁波动时不会造成资源浪费

3. **与心跳检测协同**
   - 网络监控作为第一道防线快速检测网络变化
   - SSH 心跳检测作为第二道防线确保连接有效性
   - 两者协同工作，提高可靠性

4. **资源管理**
   - 在 `AppProvider.dispose()` 中正确清理网络监控资源
   - 避免内存泄漏

## 测试建议

### 测试步骤
1. 连接到 SSH 服务器并开始播放音频
2. 关闭 WiFi 或断开网络连接
3. 观察应用是否正确标记需要恢复
4. 重新连接网络
5. 验证应用是否自动重连 SSH 并恢复播放

### 预期结果
- 网络断开时：播放停止，但不报错
- 网络恢复时：自动重连并在几秒内恢复播放
- 播放进度：从断开时的位置继续

## 相关文件

- `lib/services/network_monitor_service.dart` - 网络监控服务
- `lib/providers/app_provider.dart` - 应用状态管理（集成网络监控）
- `pubspec.yaml` - 添加 connectivity_plus 依赖

## 版本历史

- **v1.0.0** (2026-04-20): 初始实现网络状态检测与自动恢复功能
