# SSH连接自动恢复功能 - 最终实现方案

## 🎯 核心策略变更

**重要**：不再依赖网络层检测（WiFi/蜂窝/VPN），而是**直接检测SSH连接本身的有效性**。

### 为什么？

1. **网络层≠SSH层**：WiFi/VPN连接正常不代表SSH连接有效
2. **多网络环境复杂**：蜂窝、WiFi、VPN叠加时，网络状态检测不可靠
3. **SSH心跳更准确**：SSHService的心跳检测直接验证SSH连接可用性
4. **持续重试机制**：移除重试次数限制，无论网络断开多久都会持续尝试直到成功

## ✅ 最终实现的三重保障机制

### 1️⃣ SSH心跳检测（后台持续监控 + 无限期重试）
- **位置**: `ssh_service.dart` 中的心跳定时器
- **频率**: 
  - 正常模式：60秒检查一次
  - 断开后：**10秒快速检测，持续重试直到成功**
- **触发条件**: SSH连接失效时自动重连
- **重试策略**: **无次数限制**，每10秒重试一次，直到重连成功
- **优势**: 无论应用在前台还是后台都工作，即使网络断开数小时也能在恢复后自动重连

### 2️⃣ 应用恢复到前台时的主动检查
- **位置**: `main.dart` 的 `_checkAndRecoverNetworkConnection()`
- **触发时机**: `AppLifecycleState.resumed`（应用从后台恢复）
- **检查逻辑**:
  ```dart
  if (!provider.isLocalMode && provider.activeSSHConfig != null) {
    if (!provider.isSSHConnected) {
      // SSH未连接，立即重连
      await provider.handleNetworkReconnected();
    } else {
      // SSH已连接，验证有效性
      final isValid = await provider.sshService.checkConnection();
      if (!isValid) {
        // 连接失效，触发重连
        await provider.handleNetworkReconnected();
      }
    }
  }
  ```
- **优势**: 用户切换回应用时立即检测并恢复

### 3️⃣ 流式服务SSH断开监听
- **位置**: `app_provider.dart` 的 `_setupStreamingServiceListener()`
- **触发条件**: 流式播放时SSH断开
- **处理**: 调用 `_autoResumePlayback()` 保存状态并触发重连

## 🔧 技术实现细节

### 应用生命周期集成（main.dart）

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  // ...
  } else if (state == AppLifecycleState.resumed) {
    debugPrint('📱 应用回到前台');
    _notificationService.hideNotification();
    
    // ✅ 关键：直接检查SSH连接有效性
    _checkAndRecoverNetworkConnection();
  }
}

/// 检查并恢复SSH连接
Future<void> _checkAndRecoverNetworkConnection() async {
  final provider = context.read<AppProvider>();
  
  // 只在SSH模式下检查
  if (!provider.isLocalMode && provider.activeSSHConfig != null) {
    if (!provider.isSSHConnected) {
      // SSH未连接 → 重连
      await provider.handleNetworkReconnected();
    } else {
      // SSH已连接 → 验证有效性
      final isValid = await provider.sshService.checkConnection();
      if (!isValid) {
        // 连接失效 → 重连
        await provider.handleNetworkReconnected();
      }
    }
  }
}
```

### SSH心跳检测（ssh_service.dart）

```dart
void _startHeartbeatTimer(Duration interval) {
  _heartbeatTimer = Timer.periodic(interval, (_) async {
    if (_client != null) {
      final isConnected = await checkConnection();
      if (!isConnected) {
        // SSH断开，持续尝试重连（无次数限制）
        if (_currentConfig != null) {
          _reconnectAttempts++;
          debugPrint('🔄 心跳检测：尝试自动重连 (第 $_reconnectAttempts 次)...');
          try {
            final success = await reconnect().timeout(
              const Duration(seconds: 20),
            );
            
            if (success) {
              debugPrint('✅ 心跳检测：自动重连成功（共尝试 $_reconnectAttempts 次）');
              _reconnectAttempts = 0;
              // 恢复正常心跳间隔
              _startHeartbeatTimer(heartbeatIntervalNormal);
            } else {
              debugPrint('❌ 心跳检测：自动重连失败，将在10秒后重试...');
              // 继续重试
              _startHeartbeatTimer(heartbeatIntervalDisconnected);
            }
          } catch (e) {
            debugPrint('❌ 心跳检测：重连异常 - $e，将在10秒后重试...');
            // 继续重试
            _startHeartbeatTimer(heartbeatIntervalDisconnected);
          }
        }
      } else {
        _reconnectAttempts = 0;
      }
    }
  });
}
```

**关键改进**：
- ✅ **移除最大重试次数限制**：不再在5次后停止
- ✅ **持续周期性检测**：每10秒重试一次，直到成功
- ✅ **智能间隔调整**：成功后恢复60秒正常间隔，失败后保持10秒快速检测

## 🧪 测试场景

### 场景1: VPN断开重连（应用在后台）

**步骤**:
1. 连接SSH并开始播放
2. 切换到后台（Home键）
3. 关闭VPN
4. 等待60秒（SSH心跳检测会触发）
5. 重新开启VPN
6. 切回应用

**预期日志**:
```
⚠️ SSH 连接已断开                    ← 心跳检测到断开
🔄 心跳检测：SSH 断开，自动恢复播放
💾 保存播放进度: 0:03:55.494000
🔄 正在重新连接 SSH...              ← 心跳触发重连
✅ SSH 重连成功（尝试 1 次）
🔄 正在恢复播放: xxx.mp3
✅ 播放已恢复
```

### 场景1: VPN断开重连（应用在后台）- 长时间断开测试

**步骤**:
1. 连接SSH并开始播放
2. 切换到后台（Home键）
3. 关闭VPN
4. **等待任意时长**（5分钟、1小时、甚至过夜）
5. 重新开启VPN
6. 等待最多10秒（心跳检测间隔）

**预期日志**:
```
⚠️ SSH 连接已断开                    ← 心跳检测到断开
🔄 心跳检测：尝试自动重连 (第 1 次)...
❌ 心跳检测：自动重连失败，将在10秒后重试...
🔄 心跳检测：尝试自动重连 (第 2 次)...
❌ 心跳检测：自动重连失败，将在10秒后重试...
...（持续每10秒重试一次）...
[用户重新开启VPN]
🔄 心跳检测：尝试自动重连 (第 N 次)...
✅ 心跳检测：自动重连成功（共尝试 N 次）
🔄 正在恢复播放: xxx.mp3
✅ 播放已恢复
```

**关键优势**：
- ✅ 无论网络断开多久，都会在恢复后自动重连
- ✅ 不需要用户任何操作
- ✅ 即使应用完全在后台也能工作

### 场景2: VPN断开重连（应用在前台）

**步骤**:
1. 连接SSH并开始播放
2. 保持应用在前台
3. 关闭VPN
4. 重新开启VPN
5. **切换到其他应用再切回来**（触发resumed事件）

**预期日志**:
```
📱 应用回到前台
🔍 应用恢复到前台，检查SSH连接状态...
📡 检测到SSH模式，检查连接有效性...
⚠️ SSH未连接，尝试重连...
🔄 手动触发网络恢复检查...
✅ 网络已恢复（仅供参考）
ℹ️ SSH重连将由以下机制处理：
   - SSH心跳检测（如果已启动）
   - 应用恢复到前台时的主动检查
🔄 正在重新连接 SSH...
✅ SSH 重连成功
🔄 正在恢复播放: xxx.mp3
✅ 播放已恢复
```

### 场景3: SSH连接假死（网络正常但SSH失效）

**步骤**:
1. 开始播放
2. 路由器重启或SSH服务器重启
3. 网络恢复但SSH会话失效
4. 切换应用再切回来

**预期行为**:
```
🔍 应用恢复到前台，检查SSH连接状态...
✅ SSH已连接，验证连接有效性...
❌ SSH连接已失效，触发重连...
🔄 手动触发网络恢复检查...
🔄 正在重新连接 SSH...
✅ SSH 重连成功
✅ 播放已恢复
```

## 📊 关键日志标识

### 成功的完整流程
```
【路径A：心跳检测触发】
⚠️ SSH 连接已断开                    ← 心跳检测
🔄 心跳检测：SSH 断开，自动恢复播放
🔄 正在重新连接 SSH...
✅ SSH 重连成功
🔄 正在恢复播放: xxx.mp3
✅ 播放已恢复

【路径B：应用恢复触发】
📱 应用回到前台
🔍 应用恢复到前台，检查SSH连接状态...
⚠️ SSH未连接，尝试重连...           ← 或 "❌ SSH连接已失效"
🔄 正在重新连接 SSH...
✅ SSH 重连成功
🔄 正在恢复播放: xxx.mp3
✅ 播放已恢复
```

### SSH连接验证
```
✅ SSH已连接，验证连接有效性...      ← 检查连接是否真正可用
❌ SSH连接已失效，触发重连...        ← echo测试失败
```

## ⚠️ 注意事项

### 1. 网络监控的作用
- **仅作参考**：记录网络状态变化，不触发SSH重连
- **不依赖**: 不再根据WiFi/VPN状态判断是否需要重连

### 2. 重连触发条件
必须同时满足：
- SSH模式（非本地模式）
- 有活动的SSH配置
- SSH未连接 **或** 连接已失效

### 3. 恢复播放条件
- `_shouldResumeAfterReconnect == true`（之前标记需要恢复）
- SSH重连成功
- 有正在播放的文件

### 4. 心跳检测间隔
- **正常模式**：60秒（SSH连接正常时）
- **断开后**：10秒（快速检测，持续重试）
- **超时设置**：每次重连尝试最多20秒

### 5. 重试策略
- ✅ **无次数限制**：将持续重试直到成功
- ✅ **智能间隔**：失败后10秒重试，成功后恢复60秒
- ✅ **后台工作**：即使应用在后台也会持续检测

## 🎯 优势总结

### 相比之前的方案
1. **更准确**：直接检测SSH而非网络层
2. **更可靠**：三重保障机制协同工作
3. **更简单**：逻辑清晰，易于调试
4. **适应性更强**：适用于任何网络环境（WiFi/蜂窝/VPN/混合）
5. **✅ 无限期重试**：无论网络断开多久都会持续尝试，直到重连成功

### 适用场景
- ✅ VPN断开重连（即使断开数小时）
- ✅ WiFi切换蜂窝数据
- ✅ 路由器重启
- ✅ SSH服务器重启
- ✅ 网络波动导致SSH会话失效
- ✅ 应用长时间在后台
- ✅ 夜间网络维护导致的长时间断开

## 📝 Git提交历史

```
7958b5f feat: SSH重连改为持续周期性检测，移除重试次数限制
78bc536 docs: 更新SSH自动恢复功能文档，说明基于SSH直接检测的最终方案
2610a40 fix: 优化SSH重连策略，直接检测SSH连接而非网络层状态
308207f docs: 添加VPN重连后SSH自动恢复功能测试指南
a0643fa feat: 添加应用恢复到前台时的网络检查和SSH重连
c7df5b1 feat: 添加网络状态检测与自动恢复功能
```

## 🔗 相关文件

- `lib/main.dart` - 应用生命周期管理
- `lib/providers/app_provider.dart` - SSH重连逻辑
- `lib/services/ssh_service.dart` - SSH心跳检测
- `lib/services/network_monitor_service.dart` - 网络监控（仅供参考）

---

**最后更新**: 2026-04-20  
**版本**: v2.0 - 基于SSH直接检测的最终方案
