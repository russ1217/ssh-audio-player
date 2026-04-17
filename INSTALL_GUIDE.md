# Russ SSH Player 安装指南

## 问题说明

Android 16 (API 36) 设备启用了严格的安全策略，阻止通过ADB直接安装应用，出现错误：
```
INSTALL_FAILED_USER_RESTRICTED: Install canceled by user
```

## 解决方案

### ✅ 已完成：APK文件已推送到手机

APK文件已保存到手机的下载目录：
```
/sdcard/Download/Russ_SSH_Player.apk
```

### 📱 手动安装步骤

1. **打开手机文件管理器**
   - 找到「文件管理」或「我的文件」应用
   - 或使用第三方文件管理器（如Solid Explorer、ES文件浏览器）

2. **定位APK文件**
   - 进入「内部存储」→「Download」文件夹
   - 找到 `Russ_SSH_Player.apk` 文件（约21.7MB）

3. **点击安装**
   - 点击APK文件
   - 如果提示"禁止安装未知来源应用"：
     - 点击「设置」
     - 开启「允许来自此来源的应用」
     - 返回并重新点击安装

4. **完成安装**
   - 等待安装完成
   - 点击「打开」启动应用
   - 或在桌面找到「Russ SSH Player」图标

### 🔧 如果仍然无法安装

#### 方法1：关闭安装验证（需要开发者选项）

1. 进入「设置」→「关于手机」
2. 连续点击「版本号」7次，启用开发者模式
3. 进入「设置」→「系统」→「开发者选项」
4. 关闭以下选项（如果有）：
   - ❌ USB安装验证
   - ❌ 通过USB验证应用
   - ❌ MIUI优化（小米手机）

#### 方法2：使用Package Installer

在手机终端模拟器中执行：
```bash
su
pm install -r /sdcard/Download/Russ_SSH_Player.apk
```

#### 方法3：使用Shizuku（无需Root）

1. 从Play Store安装Shizuku
2. 通过无线调试激活Shizuku
3. 使用Shizuku安装APK

### 🎯 功能测试

安装成功后，请测试以下功能：

1. **基本功能**
   - ✅ 应用正常启动，无闪退
   - ✅ 界面显示正常

2. **SSH连接**
   - 添加SSH服务器配置
   - 连接到远程服务器
   - 浏览远程目录

3. **音频播放**
   - 选择音频文件播放
   - 测试播放控制（播放/暂停/停止）
   - 测试上一曲/下一曲

4. **通知栏控制**（新功能）
   - 下拉通知栏
   - 查看媒体控制按钮（上一曲/播放暂停/下一曲/停止）
   - 点击按钮验证控制功能

5. **蓝牙设备**
   - 连接蓝牙耳机/音箱
   - 验证蓝牙设备显示曲目信息
   - 使用蓝牙设备控制播放

### 📝 技术细节

**应用信息**：
- 包名：`com.audioplayer.ssh_audio_player`
- 版本：Release构建
- 大小：21.7MB
- 最低Android版本：5.0 (API 21)
- 目标Android版本：16 (API 36)

**编译时间**：2026-04-17

**最新修复**：
- ✅ 修复Android 14+广播接收器注册导致的启动闪退
- ✅ 实现通知栏媒体控制功能
- ✅ 修复MediaSession兼容性問題

### ❓ 常见问题

**Q: 为什么不能直接用adb install？**
A: Android 14+引入了更严格的安全策略，默认阻止通过ADB安装未签名的应用。这是为了保护用户免受恶意软件侵害。

**Q: 每次更新都需要手动安装吗？**
A: 不是的。你可以在开发者选项中关闭"USB安装验证"，之后就可以正常使用 `adb install` 了。

**Q: 如何卸载应用？**
A: 
```bash
adb uninstall com.audioplayer.ssh_audio_player
```
或在手机上长按应用图标 → 卸载

**Q: 如何查看应用日志？**
A:
```bash
adb logcat | grep -i "flutter\|RussSSH"
```

### 📞 技术支持

如遇问题，请提供：
1. Android版本号
2. 手机品牌和型号
3. 错误日志（通过 `adb logcat` 获取）
4. 问题复现步骤

---

**最后更新**: 2026-04-17
**文档版本**: 1.0
