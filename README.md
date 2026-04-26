# 扶摇

“扶摇”是一款将小说正文转化为可播放有声内容的 iOS 应用。

它当前已经具备完整主链路：本地 `TXT` 导入、发现页找书、章节拉取、AI 文本分析、TTS 合成、边生成边播放、书架与个人页等核心能力。

## 当前状态

- 已有可运行的 iOS App 界面，主入口在 `App/`
- 共享业务层与核心能力在 `Sources/`
- 主开发方式是使用 Xcode 运行 iOS 工程
- `swift build` 现在只用于检查共享层 `AIAudioBook` 库是否可编译

## 核心能力

- 本地 `TXT` 小说导入与章节切分
- 发现页分类推荐与关键词搜索
- 在线书源章节抓取与正文缓存
- AI 角色、情绪、场景分析
- 多角色声线分配与 TTS 合成
- 长章节分批生成，支持边生成边播放
- 播放进度保存、跨段进度聚合、下一章预取

## 项目结构

```text
App/                 # iOS 界面层（SwiftUI）
Sources/             # 共享业务层与核心模块
  Bookshelf/         # 书架、书源、章节缓存
  TextAnalysis/      # 文本分析
  TTSEngine/         # TTS 合成
  AudioMixer/        # 音频混合
  Player/            # 播放器与进度
Docs/                # 项目文档
project.yml          # iOS 工程定义
Package.swift        # 共享库构建描述（仅检查 Sources）
```

## 运行方式

### 方式 1：在 Xcode 中运行 App

这是推荐方式，也是“扶摇”当前的主要开发路径。

1. 用 Xcode 打开已生成的 iOS 工程
2. 配置 `Config.plist` 或环境变量中的 API 密钥
3. 选择模拟器或真机
4. 运行并测试“书架 / 发现 / 播放 / 我的”四个主页面

### 方式 2：命令行检查共享层

如果你只是想确认共享业务层没有编译错误，可以在项目根目录执行：

```bash
swift build
```

注意：
- 这个命令当前只检查 `Sources/` 下的共享库
- 它不负责构建完整的 iOS App 界面

## 配置说明

项目需要 AI 分析服务和 TTS 服务的密钥。优先级如下：

1. 环境变量
2. Keychain
3. `Config.plist`

详细说明见：

- `Docs/API密钥配置.md`
- `Config.plist.template`
- `Docs/项目导航.md`

当前文本分析默认使用 Moonshot `Kimi K2.6`（`AI_PROVIDER=kimi`），备选 `Qwen`。

## 最近同步过的项目现实

- 发现页搜索已改为真实搜索优先，失败时回退到缓存搜索
- 长章节不再默认只取前 2000 字，而是分批生成与播放
- `Package.swift` 已调整为仅检查共享库，避免误把 `App/` 按 macOS 可执行目标构建

## 下一步建议

- 在 Xcode 中重点验证发现页搜索体验
- 测试长章节是否能连续播放完整内容
- 继续完善 README、开发指南和产品说明的一致性
