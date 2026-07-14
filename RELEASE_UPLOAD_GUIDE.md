# v1.2.5 Release 上传指南

## ✅ 已完成的步骤

### 1. 版本更新
- ✅ pubspec.yaml 版本号更新为 `1.2.5+1`
- ✅ Git 提交更改
- ✅ 创建 Git 标签 `v1.2.5`
- ✅ 推送到远程仓库（master 分支和标签）

### 2. APK 构建
- ✅ 成功构建 Release APK
- 📁 文件位置：`build/app/outputs/flutter-apk/app-release.apk`
- 📦 文件大小：56MB

---

## 📤 GitHub Release 上传步骤

由于 APK 文件较大（56MB），需要手动通过 GitHub Web 界面上传。

### 方法一：通过 GitHub Web 界面（推荐）

#### 步骤 1：访问 Releases 页面
打开浏览器，访问：
```
https://github.com/russ1217/ssh-audio-player/releases
```

#### 步骤 2：创建新 Release
1. 点击 **"Draft a new release"** 按钮
2. 在 **"Choose a tag"** 下拉框中选择 **v1.2.5**（已推送的标签）
3. **Release title** 填写：`v1.2.5 - 全屏播放模式`
4. **Describe this release** 粘贴以下内容：

```markdown
## 🎉 新功能：全屏播放模式

### ✨ 主要特性
- 📱 横屏全屏显示
- ⏱️ 80px 超大字体秒表计时器
- 📊 可拖动进度条和时长显示
- 🔒 防锁屏功能（wakelock_plus）
- 🎨 优化的两行控制布局

### 📥 安装
下载 app-release.apk 并安装到 Android 设备

### 💡 使用提示
播放音频后，点击底部控制栏第二行最右侧的 ⛶ 全屏按钮

详见 RELEASE_v1.2.5.md
```

#### 步骤 3：上传 APK 文件
1. 在 **"Attach binaries by dropping them here or selecting them"** 区域
2. 拖拽或点击选择文件：`build/app/outputs/flutter-apk/app-release.apk`
3. 等待上传完成（可能需要几分钟，因为文件较大）

#### 步骤 4：发布 Release
1. 确认所有信息正确
2. 点击 **"Publish release"** 按钮
3. 完成！✅

---

### 方法二：使用 GitHub CLI（如果已安装）

```bash
cd /home/russ/apps/player

# 创建 Release 并上传 APK
gh release create v1.2.5 \
  --title "v1.2.5 - 全屏播放模式" \
  --notes-file RELEASE_v1.2.5.md \
  build/app/outputs/flutter-apk/app-release.apk
```

---

## 📋 上传前检查清单

- [x] 版本号已更新（pubspec.yaml: 1.2.5+1）
- [x] 代码已提交到 Git
- [x] Git 标签已创建（v1.2.5）
- [x] 代码已推送到远程（master + tags）
- [x] Release APK 已构建
- [x] Release 说明文档已创建
- [ ] **待完成：手动上传 APK 到 GitHub Release**

---

## 🔍 验证上传

上传完成后，请验证：

### 1. 检查 Release 页面
访问：https://github.com/russ1217/ssh-audio-player/releases/tag/v1.2.5

应该看到：
- ✅ 标题：v1.2.5 - 全屏播放模式
- ✅ 描述：包含功能说明
- ✅ Assets：app-release.apk (56MB)
- ✅ 标签：v1.2.5

### 2. 测试下载
- 点击下载 APK 文件
- 确认下载成功
- 在设备上测试安装

### 3. 检查标签
```bash
git ls-remote --tags origin | grep v1.2.5
```

应该看到：
```
<commit-hash> refs/tags/v1.2.5
```

---

## 💡 注意事项

### 大文件上传
- APK 文件 56MB，上传可能需要 2-5 分钟（取决于网络速度）
- 确保网络连接稳定
- 如果上传失败，可以重试或使用更快的网络

### Git LFS（可选优化）
如果经常发布大文件，可以考虑使用 Git LFS：

```bash
# 安装 Git LFS
git lfs install

# 跟踪 APK 文件
git lfs track "*.apk"

# 提交 .gitattributes
git add .gitattributes
git commit -m "chore: 配置 Git LFS 追踪 APK 文件"
git push
```

但根据项目规范，推荐使用 GitHub Release 而不是直接提交大文件到仓库。

---

## 📝 后续步骤

1. **上传 APK 到 GitHub Release**（当前待完成）
2. 验证下载链接有效
3. 在设备上测试新版本
4. 更新 README.md 中的最新版本号
5. （可选）通知用户新版本发布

---

## ❓ 常见问题

### Q: 上传时提示文件太大？
A: GitHub Release 单个文件限制为 2GB，56MB 完全没问题。

### Q: 上传速度慢怎么办？
A: 
- 使用更快的网络连接
- 尝试不同的时间段（避开高峰）
- 考虑使用 GitHub CLI

### Q: 上传失败怎么办？
A: 
- 检查网络连接
- 刷新页面重试
- 清除浏览器缓存
- 尝试使用其他浏览器

### Q: 可以同时上传多个文件吗？
A: 可以，但本次只需要上传一个 APK 文件。

---

**现在就前往 GitHub 完成 Release 上传吧！** 🚀

访问：https://github.com/russ1217/ssh-audio-player/releases/new
