#!/bin/bash

# AI 有声书项目 - 快速启动脚本

echo "🚀 AI 有声书项目 - 快速启动"
echo "================================"
echo ""

# 检查是否安装了 Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 未检测到 Xcode，请先安装 Xcode"
    echo "   从 Mac App Store 下载: https://apps.apple.com/app/xcode/id497799835"
    exit 1
fi

echo "✅ Xcode 已安装"
xcodebuild -version
echo ""

# 检查 Swift 版本
if command -v swift &> /dev/null; then
    echo "✅ Swift 已安装"
    swift --version
    echo ""
fi

# 创建 Xcode 项目（如果不存在）
if [ ! -d "AIAudioBook.xcodeproj" ]; then
    echo "📦 创建 Xcode 项目..."

    # 使用 Swift Package Manager 生成 Xcode 项目
    swift package generate-xcodeproj 2>/dev/null || {
        echo "⚠️  无法自动生成项目，请手动在 Xcode 中创建"
        echo ""
        echo "手动步骤："
        echo "1. 打开 Xcode"
        echo "2. File → New → Project"
        echo "3. 选择 iOS → App"
        echo "4. 将 Sources 目录下的文件添加到项目"
        echo ""
    }
else
    echo "✅ Xcode 项目已存在"
fi

# 检查 API 密钥配置
echo ""
echo "🔑 检查 API 密钥配置..."

if [ -f "Config.plist" ]; then
    echo "✅ 找到 Config.plist 配置文件"
else
    echo "⚠️  未找到 Config.plist，创建模板文件..."

    cat > Config.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AI_API_KEY</key>
    <string>your-claude-api-key-here</string>
    <key>TTS_API_KEY</key>
    <string>your-azure-tts-key-here</string>
    <key>AI_PROVIDER</key>
    <string>claude</string>
    <key>TTS_PROVIDER</key>
    <string>azure</string>
    <key>AZURE_REGION</key>
    <string>eastasia</string>
</dict>
</plist>
EOF

    echo "✅ 已创建 Config.plist 模板"
    echo "   请编辑此文件并填入你的 API 密钥"
fi

# 检查资源目录
echo ""
echo "📁 检查资源目录..."

if [ ! -d "Resources/BackgroundMusic" ]; then
    mkdir -p Resources/BackgroundMusic
    echo "✅ 创建 Resources/BackgroundMusic 目录"
fi

if [ ! -d "Resources/SoundEffects" ]; then
    mkdir -p Resources/SoundEffects
    echo "✅ 创建 Resources/SoundEffects 目录"
fi

# 统计代码
echo ""
echo "📊 项目统计..."
echo "   Swift 文件数: $(find Sources -name "*.swift" | wc -l | xargs)"
echo "   代码行数: $(find Sources -name "*.swift" -exec wc -l {} + | tail -1 | awk '{print $1}')"
echo "   文档文件数: $(find . -name "*.md" | wc -l | xargs)"

# 显示下一步
echo ""
echo "✨ 准备完成！"
echo ""
echo "📝 下一步操作："
echo ""
echo "1. 配置 API 密钥"
echo "   编辑 Config.plist 文件，填入你的 API 密钥"
echo "   参考: Docs/API密钥配置.md"
echo ""
echo "2. 打开项目"
if [ -d "AIAudioBook.xcodeproj" ]; then
    echo "   运行: open AIAudioBook.xcodeproj"
else
    echo "   在 Xcode 中创建新项目，然后添加 Sources 目录下的文件"
fi
echo ""
echo "3. 运行示例"
echo "   参考: Sources/使用示例.swift"
echo "   或查看: 快速开始.md"
echo ""
echo "4. 开发 UI"
echo "   使用 SwiftUI 创建用户界面"
echo "   参考: Docs/开发指南.md"
echo ""
echo "📚 文档："
echo "   - README.md - 项目介绍"
echo "   - 快速开始.md - 快速入门"
echo "   - Docs/架构设计.md - 架构文档"
echo "   - Docs/开发指南.md - 开发指南"
echo "   - Docs/API密钥配置.md - API 配置"
echo "   - Docs/部署和优化.md - 部署指南"
echo ""
echo "🎉 祝你开发顺利！"
