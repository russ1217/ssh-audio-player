#!/bin/bash

echo "========================================="
echo "  播放模式功能验证脚本"
echo "========================================="
echo ""

# 检查文件是否存在
echo "📁 检查新增文件..."
if [ -f "lib/models/playlist_repeat_mode.dart" ]; then
    echo "✅ playlist_repeat_mode.dart 存在"
else
    echo "❌ playlist_repeat_mode.dart 不存在"
    exit 1
fi

# 检查关键方法是否存在
echo ""
echo "🔍 检查关键方法实现..."

if grep -q "toggleRepeatMode" lib/providers/app_provider.dart; then
    echo "✅ toggleRepeatMode 方法已实现"
else
    echo "❌ toggleRepeatMode 方法未找到"
    exit 1
fi

if grep -q "_generateShuffleIndices" lib/providers/app_provider.dart; then
    echo "✅ _generateShuffleIndices 方法已实现"
else
    echo "❌ _generateShuffleIndices 方法未找到"
    exit 1
fi

if grep -q "_getNextIndex" lib/providers/app_provider.dart; then
    echo "✅ _getNextIndex 方法已实现"
else
    echo "❌ _getNextIndex 方法未找到"
    exit 1
fi

if grep -q "_getPreviousIndex" lib/providers/app_provider.dart; then
    echo "✅ _getPreviousIndex 方法已实现"
else
    echo "❌ _getPreviousIndex 方法未找到"
    exit 1
fi

# 检查UI按钮
echo ""
echo "🎨 检查UI实现..."

if grep -q "toggleRepeatMode" lib/widgets/bottom_player_bar.dart; then
    echo "✅ 播放模式切换按钮已添加"
else
    echo "❌ 播放模式切换按钮未找到"
    exit 1
fi

if grep -q "_getRepeatModeIcon" lib/widgets/bottom_player_bar.dart; then
    echo "✅ 播放模式图标方法已实现"
else
    echo "❌ 播放模式图标方法未找到"
    exit 1
fi

# 检查setUrlWithoutPlay实现
echo ""
echo "🔧 检查音频服务实现..."

if grep -q "setUrlWithoutPlay" lib/services/audio_player_service_impl.dart; then
    echo "✅ audio_player_service_impl.dart 中 setUrlWithoutPlay 已实现"
else
    echo "❌ audio_player_service_impl.dart 中 setUrlWithoutPlay 未找到"
    exit 1
fi

if grep -q "setUrlWithoutPlay" lib/services/audio_player_stub.dart; then
    echo "✅ audio_player_stub.dart 中 setUrlWithoutPlay 已实现"
else
    echo "❌ audio_player_stub.dart 中 setUrlWithoutPlay 未找到"
    exit 1
fi

# 运行flutter analyze
echo ""
echo "🔬 运行代码分析..."
flutter analyze --no-pub 2>&1 | grep -E "error|Error" > /tmp/analyze_errors.txt

if [ -s /tmp/analyze_errors.txt ]; then
    echo "❌ 发现编译错误:"
    cat /tmp/analyze_errors.txt
    exit 1
else
    echo "✅ 无编译错误"
fi

# 统计修改的文件
echo ""
echo "📊 修改文件统计..."
echo "   - lib/models/playlist_repeat_mode.dart (新增)"
echo "   - lib/providers/app_provider.dart (修改)"
echo "   - lib/widgets/bottom_player_bar.dart (修改)"
echo "   - lib/services/audio_player_service_impl.dart (修改)"
echo "   - lib/services/audio_player_stub.dart (修改)"

echo ""
echo "========================================="
echo "  ✅ 所有验证通过！"
echo "========================================="
echo ""
echo "📝 下一步："
echo "   1. 运行 flutter build apk --debug 构建应用"
echo "   2. 在设备上安装并测试"
echo "   3. 参考 TEST_CHECKLIST.md 进行完整测试"
echo ""
