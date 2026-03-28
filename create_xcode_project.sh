#!/bin/bash

# 创建 Xcode 项目的脚本
# 由于无法直接通过命令行创建 iOS App 项目，这个脚本会指导用户手动创建

echo "================================================"
echo "  AI 有声书 - Xcode 项目创建指南"
echo "================================================"
echo ""
echo "由于 Xcode 项目需要在图形界面中创建，请按以下步骤操作："
echo ""
echo "1. 打开 Xcode（已自动打开）"
echo ""
echo "2. 点击 'Create New Project'"
echo ""
echo "3. 选择模板："
echo "   - 平台: iOS"
echo "   - 模板: App"
echo "   - 点击 Next"
echo ""
echo "4. 填写项目信息："
echo "   Product Name: AI有声书"
echo "   Team: (选择你的开发团队)"
echo "   Organization Identifier: com.audiobook"
echo "   Interface: SwiftUI"
echo "   Language: Swift"
echo "   点击 Next"
echo ""
echo "5. 选择保存位置:"
echo "   保存到: $(pwd)"
echo "   点击 Create"
echo ""
echo "6. 项目创建完成后，运行以下命令添加源代码:"
echo "   ./add_sources.sh"
echo ""
echo "================================================"
echo ""

# 自动打开 Xcode
open -a Xcode

echo "✅ Xcode 已打开，请按照上述步骤创建项目"
echo ""
