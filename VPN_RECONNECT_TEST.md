# VPN重连后SSH自动恢复功能测试指南

## 问题背景

之前发现VPN重连后，应用虽然检测到SSH连接失效并尝试重连，但没有触发完整的自动恢复流程。

## 解决方案

### 1. 增强日志输出
- 在 `NetworkMonitorService._handleConnectivityChange()` 中添加详细的网络状态变化日志
- 在 `AppProvider._handleNetworkReconnected()` 中添加状态检查详情

### 2. 应用生命周期集成
- 在 `main.dart` 的 `didChangeAppLifecycleState()` 中，当应用从后台恢复到前台时（`resumed`），主动检查网络状态
- 如果检测到需要恢复播放但SSH未连接，立即触发恢复流程

### 3. 公开必要接口
- 在 `AppProvider` 中添加 `shouldResumeAfterReconnect` getter
- 添加 `handleNetworkReconnected()` 公开方法供外部调用

## 测试步骤

### 场景1: VPN断开重连（应用在后台）

1. **准备阶段**
   ```bash
   # 启动日志监控
   adb logcat | grep -E "flutter.*网络|flutter.*重连|flutter.*恢复|flutter.*应用恢复"
   ```

2. **开始播放**
   - 打开应用
   - 连接SSH服务器
   - 选择一个音频文件开始播放
   - 确认播放正常

3. **切换到后台**
   - 按Home键将应用切换到后台
   - 观察日志：应该看到 "📱 应用进入后台"

4. **断开VPN**
   - 关闭VPN连接
   - 观察日志：应该看到SSH心跳检测断开

5. **重新连接VPN**
   - 开启VPN连接
   - 等待VPN完全连接

6. **恢复应用到前台**
   - 点击应用图标或从最近任务中恢复
   - **关键观察点**：
     ```
     📱 应用回到前台
     🔍 应用恢复到前台，检查网络连接状态...
     🔄 检测到需要恢复SSH连接，尝试重连...
     🔄 手动触发网络恢复检查...
     ✅ 网络已恢复，检查是否需要重连和恢复播放...
        - _shouldResumeAfterReconnect: true
        - _sshService.isConnected: false
        - _activeSSHConfig: 存在
        - _isPlaying: true
        - _currentPlayingFile: xxx.mp3
     🔄 网络恢复，尝试重新连接SSH...
     ✅ SSH 重连成功，准备恢复播放
     🔄 正在恢复播放: xxx.mp3
     ⏩ 恢复到进度: 0:03:55.494000
     ✅ 播放已恢复
     ```

### 场景2: VPN断开重连（应用在前台）

1. **准备阶段**
   - 同上，开始播放音频

2. **保持应用在前台**
   - 不要切换应用

3. **断开VPN**
   - 关闭VPN
   - 观察日志：
     ```
     ❌ 网络已断开
     ⚠️ 网络已断开，保存播放状态...
     💾 网络断开，保存播放进度以备恢复
     ```

4. **重新连接VPN**
   - 开启VPN
   - **预期行为**：
     - 如果 `connectivity_plus` 检测到网络变化，会看到：
       ```
       📡 网络状态变化事件: wifi (或其他类型)
       ✅ 网络已恢复连接
       🔄 网络状态变化: 已连接
       ✅ 网络已恢复，检查是否需要重连和恢复播放...
       ```
     - 然后自动重连SSH并恢复播放

### 场景3: 网络监控未触发的情况

如果VPN重连后没有看到 "📡 网络状态变化事件" 日志，说明 `connectivity_plus` 没有检测到VPN状态变化。此时依赖应用生命周期检查：

1. 断开VPN
2. 重连VPN
3. **手动切换到其他应用再切回来**（触发 `resumed` 事件）
4. 应用会自动检测并恢复

## 关键日志标识

### 成功的完整流程
```
✅ 网络已恢复连接                    ← 网络监控检测到
🔄 网络状态变化: 已连接              ← 回调触发
✅ 网络已恢复，检查是否需要重连...    ← 开始恢复流程
   - _shouldResumeAfterReconnect: true
   - _sshService.isConnected: false
🔄 网络恢复，尝试重新连接SSH...      ← SSH重连
✅ SSH 重连成功                      ← 重连成功
🔄 正在恢复播放: xxx.mp3            ← 恢复播放
✅ 播放已恢复                        ← 完成
```

### 通过应用生命周期触发
```
📱 应用回到前台                     ← 应用恢复
🔍 应用恢复到前台，检查网络连接状态... ← 开始检查
🔄 检测到需要恢复SSH连接，尝试重连... ← 触发恢复
🔄 手动触发网络恢复检查...           ← 调用处理方法
✅ 网络已恢复，检查是否需要重连...    ← 后续流程同上
```

### 失败的情况
```
⚠️ 网络已恢复，但不满足重连条件      ← 条件不满足
   - 原因：_shouldResumeAfterReconnect 为 false
   - 原因：SSH 已连接
   - 原因：没有活动的 SSH 配置
```

## 调试技巧

### 1. 查看完整的Flutter日志
```bash
adb logcat -s flutter:I
```

### 2. 只看网络和重连相关
```bash
adb logcat | grep -E "flutter.*(网络|重连|恢复|应用恢复)"
```

### 3. 实时监控
```bash
# 清空旧日志
adb logcat -c
# 开始监控
adb logcat | grep -E "flutter.*"
```

## 常见问题

### Q1: 为什么VPN重连后没有自动恢复？
**A**: 可能的原因：
1. `connectivity_plus` 没有检测到VPN状态变化（某些Android版本/ROM的限制）
2. 应用在后台时网络监控回调可能不被触发
3. **解决方案**：应用恢复到前台时会主动检查，只需切换一下应用即可触发

### Q2: 如何确认网络监控是否工作？
**A**: 查看启动日志，应该有：
```
🌐 设置网络状态监控...
🌐 初始化网络状态监控...
✅ 网络状态监控已启动
✅ 网络状态监控已设置
```

### Q3: 如果还是不能自动恢复怎么办？
**A**: 
1. 检查是否有 "📡 网络状态变化事件" 日志
2. 如果没有，说明 `connectivity_plus` 没检测到，这是正常的
3. 确保应用恢复到前台时会触发检查（看 "🔍 应用恢复到前台" 日志）
4. 手动触发：切换到其他应用再切回来

## 技术实现细节

### 双重保障机制
1. **第一层**：`NetworkMonitorService` 实时监听网络变化
   - 优点：即时响应
   - 缺点：某些情况下（如VPN）可能检测不到

2. **第二层**：应用生命周期检查
   - 优点：可靠，每次应用恢复都会检查
   - 缺点：需要用户交互（切换应用）

### 恢复条件
必须同时满足以下条件才会触发恢复：
- `_shouldResumeAfterReconnect == true`（之前标记需要恢复）
- `_sshService.isConnected == false`（SSH当前未连接）
- `_activeSSHConfig != null`（有SSH配置可用）

## 版本信息

- **实现日期**: 2026-04-20
- **Git提交**: a0643fa
- **APK版本**: Release build with network recovery enhancement
