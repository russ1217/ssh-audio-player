# 本地文件浏览快速测试指南

## 问题说明

之前访问 `/storage` 目录返回空，是因为：
1. `/storage` 是挂载点，不是实际存储路径
2. Android分区存储限制
3. 应用专属目录可能为空

## 修复方案

现在默认使用以下路径（按优先级）：
1. ✅ `/storage/emulated/0/Download` - 下载目录（最常用）
2. ✅ `/storage/emulated/0/Music` - 音乐目录
3. ⚠️ `/storage/emulated/0` - 内部存储根目录（回退选项）

## 测试步骤

### 1. 安装新版本APK
```bash
# APK已推送到设备
adb install /sdcard/Download/ssh_audio_player_fixed.apk
```

### 2. 切换到本地模式
1. 打开应用
2. 点击AppBar右上角的手机图标📱
3. 授予存储权限

### 3. 验证路径
查看日志输出：
```bash
adb logcat | grep flutter
```

应该看到类似：
```
I/flutter: 🔄 切换到本地文件模式
I/flutter: ✅ 通过原生方法获取Android版本: 34
I/flutter: 📱 Android 13+，检查媒体权限...
I/flutter: 🔐 请求媒体权限...
I/flutter: ✅ 媒体权限已授予
I/flutter: ✅ 使用Download目录: /storage/emulated/0/Download
I/flutter: 📁 加载本地目录: /storage/emulated/0/Download
I/flutter: 📊 找到 X 个项目
I/flutter: ✅ 成功加载 X 个有效项目
```

### 4. 如果Download目录为空

**方法1：手动放入测试文件**
```bash
# 推送一个测试音频文件到Download目录
adb push test.mp3 /sdcard/Download/
```

**方法2：导航到其他目录**
- 点击返回按钮（←）回到上级目录
- 或进入 `/storage/emulated/0/Music`

**方法3：查看日志确认当前路径**
```bash
adb logcat | grep "加载本地目录"
```

### 5. 常见问题排查

#### Q1: 仍然显示空目录？
**检查：**
```bash
# 查看Download目录是否有文件
adb shell ls -la /sdcard/Download/

# 如果没有文件，添加一个测试文件
adb push somefile.mp3 /sdcard/Download/
```

#### Q2: 权限已授予但仍无法访问？
**解决：**
```bash
# 清除应用数据重试
adb shell pm clear com.audioplayer.ssh_audio_player

# 重新打开应用并授权
```

#### Q3: 想访问其他目录？
**当前支持的路径：**
- `/storage/emulated/0/Download` ✅
- `/storage/emulated/0/Music` ✅
- `/storage/emulated/0/Documents` ✅
- `/storage/emulated/0/DCIM` ✅

**不支持的路径：**
- `/storage` ❌ （挂载点）
- `/data` ❌ （系统目录）
- `/system` ❌ （系统目录）

## 下一步改进

计划添加的功能：
1. 📂 **快捷路径选择器** - 一键跳转到常用目录
2. 🔍 **文件搜索** - 按名称搜索文件
3. 📌 **收藏文件夹** - 标记常用目录
4. 🖼️ **文件类型过滤** - 只显示音频/视频文件

## 日志关键词

调试时关注以下日志：
- `🔄 切换到本地文件模式` - 模式切换开始
- `✅ 使用XXX目录` - 确定的默认路径
- `📁 加载本地目录` - 开始加载
- `📊 找到 X 个项目` - 扫描结果
- `✅ 成功加载` - 加载完成
- `❌ 无权限读取目录` - 权限问题
- `⚠️ 跳过无法访问的项目` - 部分文件不可读
