# API 密钥配置指南

## 概述

本项目需要两类 API 密钥：
1. **AI 分析服务** - 用于文本分析（识别角色、情感、场景）
2. **TTS 服务** - 用于语音合成

## 1. AI 分析服务

### Claude API（推荐）

**获取方式：**
1. 访问 [Anthropic Console](https://console.anthropic.com/)
2. 注册账号并登录
3. 进入 API Keys 页面
4. 创建新的 API Key

**配置示例：**
```swift
let generator = AudioBookGenerator(
    aiApiKey: "sk-ant-api03-xxxxx",
    ttsApiKey: "your-tts-key",
    aiProvider: .claude,
    ttsProvider: .azure
)
```

**定价：**
- Claude Opus 4.6: $15/MTok (输入), $75/MTok (输出)
- Claude Sonnet 4.6: $3/MTok (输入), $15/MTok (输出)

**预估成本：**
- 分析 1 万字小说约消耗 15K tokens
- 使用 Sonnet: 约 $0.05-0.10

### OpenAI API（备选）

**获取方式：**
1. 访问 [OpenAI Platform](https://platform.openai.com/)
2. 注册账号并登录
3. 进入 API Keys 页面
4. 创建新的 API Key

**配置示例：**
```swift
let generator = AudioBookGenerator(
    aiApiKey: "sk-xxxxx",
    ttsApiKey: "your-tts-key",
    aiProvider: .openai,
    ttsProvider: .azure
)
```

**定价：**
- GPT-4 Turbo: $10/MTok (输入), $30/MTok (输出)

## 2. TTS 服务

### Azure Cognitive Services（推荐）

**获取方式：**
1. 访问 [Azure Portal](https://portal.azure.com/)
2. 创建 "语音服务" 资源
3. 选择区域（推荐：East Asia 或 Southeast Asia）
4. 获取密钥和区域信息

**配置示例：**
```swift
let ttsConfig = TTSConfig(
    provider: .azure,
    apiKey: "your-azure-key",
    baseURL: "https://eastasia.tts.speech.microsoft.com"
)
```

**定价：**
- 神经语音: ¥110/百万字符
- 免费额度: 每月 50 万字符

**预估成本：**
- 1 万字小说: 约 ¥1.1
- 10 万字小说: 约 ¥11

**支持的中文音色：**
- 晓晓 (XiaoxiaoNeural) - 女性、温柔
- 云希 (YunxiNeural) - 男性、沉稳
- 晓伊 (XiaoyiNeural) - 女性、甜美
- 云健 (YunjianNeural) - 男性、年轻
- 更多音色见 `TTSModels.swift`

### OpenAI TTS（备选）

**获取方式：**
- 使用 OpenAI API Key（与 AI 分析服务相同）

**配置示例：**
```swift
let ttsConfig = TTSConfig(
    provider: .openai,
    apiKey: "sk-xxxxx"
)
```

**定价：**
- TTS HD: $15/百万字符
- TTS Standard: $7.5/百万字符

**预估成本：**
- 1 万字小说: 约 $0.15 (HD) 或 $0.075 (Standard)

**支持的音色：**
- alloy, echo, fable, onyx, nova, shimmer

### 阿里云智能语音（国内推荐）

**获取方式：**
1. 访问 [阿里云控制台](https://www.aliyun.com/)
2. 开通 "智能语音交互" 服务
3. 创建项目并获取 AppKey

**定价：**
- 按调用次数计费
- 有免费额度

**注意：** 当前代码中阿里云 TTS 为占位实现，需要补充完整的 API 调用逻辑。

### 科大讯飞（国内备选）

**获取方式：**
1. 访问 [讯飞开放平台](https://www.xfyun.cn/)
2. 注册并创建应用
3. 获取 APPID、APIKey、APISecret

**注意：** 当前代码中科大讯飞 TTS 为占位实现，需要补充完整的 API 调用逻辑。

## 3. 配置文件方式

### 创建配置文件

创建 `Config.plist` 文件：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AI_API_KEY</key>
    <string>your-claude-api-key</string>
    <key>TTS_API_KEY</key>
    <string>your-azure-tts-key</string>
    <key>AI_PROVIDER</key>
    <string>claude</string>
    <key>TTS_PROVIDER</key>
    <string>azure</string>
    <key>AZURE_REGION</key>
    <string>eastasia</string>
</dict>
</plist>
```

### 读取配置

```swift
func loadConfig() -> (aiKey: String, ttsKey: String, aiProvider: AIProvider, ttsProvider: TTSProvider) {
    guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
          let config = NSDictionary(contentsOfFile: path) else {
        fatalError("配置文件不存在")
    }

    let aiKey = config["AI_API_KEY"] as! String
    let ttsKey = config["TTS_API_KEY"] as! String
    let aiProviderString = config["AI_PROVIDER"] as! String
    let ttsProviderString = config["TTS_PROVIDER"] as! String

    let aiProvider: AIProvider = aiProviderString == "openai" ? .openai : .claude
    let ttsProvider = TTSProvider(rawValue: ttsProviderString) ?? .azure

    return (aiKey, ttsKey, aiProvider, ttsProvider)
}

// 使用
let config = loadConfig()
let generator = AudioBookGenerator(
    aiApiKey: config.aiKey,
    ttsApiKey: config.ttsKey,
    aiProvider: config.aiProvider,
    ttsProvider: config.ttsProvider
)
```

## 4. 环境变量方式

### 设置环境变量

在 Xcode Scheme 中设置：
1. Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. 添加：
   - `AI_API_KEY`: your-api-key
   - `TTS_API_KEY`: your-tts-key

### 读取环境变量

```swift
func loadFromEnvironment() -> (aiKey: String, ttsKey: String) {
    guard let aiKey = ProcessInfo.processInfo.environment["AI_API_KEY"],
          let ttsKey = ProcessInfo.processInfo.environment["TTS_API_KEY"] else {
        fatalError("环境变量未设置")
    }
    return (aiKey, ttsKey)
}
```

## 5. 安全建议

### ⚠️ 重要提示

1. **不要将 API Key 硬编码在代码中**
2. **不要将 API Key 提交到 Git 仓库**
3. **使用 .gitignore 排除配置文件**

### .gitignore 配置

```gitignore
# API 密钥配置
Config.plist
Secrets.swift
*.key

# Xcode
*.xcuserstate
xcuserdata/
```

### 密钥管理最佳实践

1. **开发环境**：使用配置文件或环境变量
2. **生产环境**：使用 Keychain 存储
3. **团队协作**：使用密钥管理服务（如 AWS Secrets Manager）

### Keychain 存储示例

```swift
import Security

class KeychainManager {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)

        if let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}

// 使用
KeychainManager.save(key: "AI_API_KEY", value: "your-api-key")
let apiKey = KeychainManager.load(key: "AI_API_KEY")
```

## 6. 成本优化建议

### 降低 AI 分析成本

1. **启用缓存**：相同文本不重复分析
2. **批量处理**：合并多个小段落
3. **使用更便宜的模型**：Sonnet 代替 Opus

### 降低 TTS 成本

1. **启用缓存**：相同文本不重复合成
2. **选择合适的音质**：Standard 代替 HD
3. **使用免费额度**：Azure 每月 50 万字符免费

### 预算控制

```swift
// 设置 API 调用限制
let ttsConfig = TTSConfig(
    provider: .azure,
    apiKey: "your-key",
    maxConcurrentRequests: 3  // 限制并发数
)

// 监控使用量
var totalCharacters = 0
for segment in segments {
    totalCharacters += segment.text.count
}
let estimatedCost = Double(totalCharacters) / 1_000_000 * 110  // Azure 定价
print("预估成本: ¥\(estimatedCost)")
```

## 7. 测试 API 连接

```swift
func testAPIConnection() async {
    // 测试 AI API
    let aiService = ClaudeAnalysisService(apiKey: "your-key")
    do {
        let result = try await aiService.analyze(prompt: "测试连接")
        print("✅ AI API 连接成功")
    } catch {
        print("❌ AI API 连接失败: \(error)")
    }

    // 测试 TTS API
    let ttsConfig = TTSConfig(provider: .azure, apiKey: "your-key")
    let ttsEngine = TTSEngine(config: ttsConfig)
    do {
        let voice = VoiceLibrary.azureVoices.first!
        let audio = try await ttsEngine.synthesize(text: "测试", voice: voice)
        print("✅ TTS API 连接成功")
    } catch {
        print("❌ TTS API 连接失败: \(error)")
    }
}
```

## 8. 常见问题

**Q: API Key 无效怎么办？**
A: 检查密钥是否正确复制，是否有多余的空格或换行符。

**Q: Azure TTS 返回 401 错误？**
A: 检查区域设置是否正确，密钥是否对应该区域。

**Q: 成本太高怎么办？**
A: 启用缓存、使用更便宜的模型、减少并发请求数。

**Q: 如何切换服务提供商？**
A: 修改初始化参数中的 `aiProvider` 和 `ttsProvider`。
