# 存储权限请求问题修复

## 问题描述

用户在点击"切换到本地文件"按钮时，权限请求对话框没有弹出，日志显示：
```
I/flutter: 📱 Android 12及以下，检查存储权限...
I/flutter: 🔐 请求存储权限...
I/flutter: ❌ 存储权限被拒绝
```

## 根本原因

### 1. Android版本检测错误
- `StoragePermissionService._getAndroidVersion()` 返回硬编码值 `30`（Android 11）
- 实际设备是 **Android 14** (API Level 34)
- 导致使用了错误的权限API

### 2. 权限API不匹配
- **Android 13+ (API 33+)** 应使用：
  - `Permission.audio`
  - `Permission.videos`
  
- **Android 12及以下** 才使用：
  - `Permission.storage`

由于版本判断错误，Android 14设备被当作Android 11处理，调用了已废弃的`Permission.storage`，导致权限请求失败。

### 3. 缺少详细日志
- 无法看到真实的Android版本
- 无法看到权限的当前状态
- 无法定位具体失败原因

## 修复方案

### 1. 添加原生Android版本查询

**文件**: `android/app/src/main/kotlin/com/audioplayer/ssh_audio_player/MainActivity.kt`

```kotlin
// 新增通道
private val ANDROID_VERSION_CHANNEL = "android_version"

MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ANDROID_VERSION_CHANNEL)
    .setMethodCallHandler { call, result ->
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
```

### 2. 改进Dart端版本检测

**文件**: `lib/services/storage_permission_service.dart`

```dart
/// 获取Android版本号
Future<int> _getAndroidVersion() async {
  if (_cachedAndroidVersion != null) {
    return _cachedAndroidVersion!;
  }
  
  try {
    const platform = MethodChannel('android_version');
    final int version = await platform.invokeMethod('getAndroidVersion');
    _cachedAndroidVersion = version;
    debugPrint('✅ 通过原生方法获取Android版本: $version');
    return version;
  } catch (e) {
    debugPrint('⚠️ 通过MethodChannel获取Android版本失败: $e');
    _cachedAndroidVersion = 34; // 备用默认值
    return _cachedAndroidVersion!;
  }
}
```

### 3. 增强日志输出

```dart
// 获取真实版本
final androidVersion = await _getAndroidVersion();
debugPrint('📱 Android版本: $androidVersion (API Level)');

// 显示当前权限状态
final status = await Permission.storage.status;
debugPrint('📊 当前存储权限状态: ${status.name}');

// 显示请求结果
final result = await Permission.storage.request();
debugPrint('📊 请求结果: ${result.name}');
```

### 4. 处理永久拒绝情况

```dart
// 如果之前被永久拒绝，引导用户去设置
if (status.isPermanentlyDenied) {
  debugPrint('⚠️ 权限被永久拒绝，引导用户去设置');
  await openAppSettings();
  return false;
}
```

## 测试步骤

### 1. 重新安装APK
```bash
# 卸载旧版本
adb uninstall com.audioplayer.ssh_audio_player

# 安装新版本
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 2. 测试权限请求
1. 打开应用
2. 点击AppBar右上角的手机图标📱（切换到本地模式）
3. **应该弹出权限请求对话框**
4. 点击"允许"

### 3. 验证功能
- 成功授权后，应显示本地文件列表
- 可以点击文件进行播放
- 可以浏览文件夹

### 4. 查看日志
```bash
adb logcat | grep -E "flutter|Permission"
```

预期日志输出：
```
I/flutter: 🔄 切换到本地文件模式
I/flutter: 📱 Android版本: 34 (API Level)
I/flutter: ✅ 通过原生方法获取Android版本: 34
I/flutter: 📱 Android 13+，检查媒体权限...
I/flutter: 📊 当前权限状态 - Audio: denied, Video: denied
I/flutter: 🔐 请求媒体权限...
I/flutter: 📊 请求结果 - Audio: granted, Video: granted
I/flutter: ✅ 媒体权限已授予
```

## 常见问题

### Q1: 仍然看不到权限对话框？
**A**: 检查是否之前已经选择了"不再询问"。如果是：
1. 前往"设置 → 应用 → SSH Audio Player → 权限"
2. 手动授予"音乐和音频"、"视频"权限
3. 重启应用

### Q2: 权限授予后仍然无法访问文件？
**A**: Android 11+的分区存储限制：
- 只能访问应用专属目录和公共媒体目录
- 推荐路径：
  - `/storage/emulated/0/Download/`
  - `/storage/emulated/0/Music/`
  - `/storage/emulated/0/Android/data/com.audioplayer.ssh_audio_player/files/`

### Q3: 如何查看当前的Android版本？
**A**: 
```bash
adb shell getprop ro.build.version.sdk
```

## 技术细节

### Android版本与权限API对应关系

| Android版本 | API Level | 权限API | 说明 |
|------------|-----------|---------|------|
| Android 10 | 29 | `READ_EXTERNAL_STORAGE` | 传统存储权限 |
| Android 11 | 30 | `READ_EXTERNAL_STORAGE` | 引入分区存储 |
| Android 12 | 31-32 | `READ_EXTERNAL_STORAGE` | 最后支持的传统权限 |
| Android 13 | 33 | `READ_MEDIA_AUDIO`, `READ_MEDIA_VIDEO` | 新的细粒度权限 |
| Android 14 | 34 | `READ_MEDIA_AUDIO`, `READ_MEDIA_VIDEO` | 继续使用新权限 |

### permission_handler返回值

```dart
PermissionStatus.denied          // 未授权，可以请求
PermissionStatus.granted         // 已授权
PermissionStatus.restricted      // 受限（iOS）
PermissionStatus.limited         // 部分授权（iOS）
PermissionStatus.permanentlyDenied // 永久拒绝，需去设置页面
```

## Git提交记录

```
commit xxxxxx - 修复：存储权限请求无反应问题
  - 添加原生Android版本查询
  - 增强权限服务日志
  - 处理永久拒绝情况
```

## 总结

通过获取真实的Android版本并使用正确的权限API，现在可以正常弹出权限请求对话框了。同时增强的日志系统可以帮助快速定位未来的权限相关问题。
