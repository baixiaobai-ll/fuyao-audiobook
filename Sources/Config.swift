//
//  Config.swift
//  AI有声书
//
//  配置管理 - 安全地管理 API 密钥和应用配置
//

import Foundation

/// 应用配置管理器
struct Config {

    // MARK: - API 密钥

    /// AI 分析 API 密钥
    static var aiApiKey: String {
        let keys = aiProviderConfigKeys(for: aiProvider)
        if let key = loadFirstNonEmptyValue(fromEnvironmentKeys: keys) {
            return key
        }
        if let key = loadFirstNonEmptyValue(fromKeychainKeys: keys) {
            return key
        }
        if let key = loadFirstNonEmptyValue(fromPlistKeys: keys) {
            return key
        }
        fatalError("❌ AI API Key 未配置！请参考 Docs/API密钥配置.md")
    }

    /// TTS API 密钥
    static var ttsApiKey: String {
        if let key = ProcessInfo.processInfo.environment["TTS_API_KEY"], !key.isEmpty {
            return key
        }

        if let key = KeychainManager.load(key: "TTS_API_KEY"), !key.isEmpty {
            return key
        }

        if let key = loadFromPlist(key: "TTS_API_KEY"), !key.isEmpty {
            return key
        }

        fatalError("❌ TTS API Key 未配置！请参考 Docs/API密钥配置.md")
    }

    // MARK: - 服务提供商配置

    /// AI 服务提供商
    static var aiProvider: AIProvider {
        let providerString = ProcessInfo.processInfo.environment["AI_PROVIDER"]
            ?? loadFromPlist(key: "AI_PROVIDER")
            ?? "kimi"
        return AIProvider(rawValue: providerString) ?? .kimi
    }

    /// AI 模型名称
    static var aiModel: String {
        if let model = ProcessInfo.processInfo.environment["AI_MODEL"], !model.isEmpty {
            return model
        }
        if let model = loadFromPlist(key: "AI_MODEL"), !model.isEmpty {
            return model
        }

        switch aiProvider {
        case .kimi:
            return "kimi-k2.6"
        case .qwen:
            return "qwen3.6-plus"
        }
    }

    /// AI 基础地址
    static var aiBaseURL: String? {
        if let url = ProcessInfo.processInfo.environment["AI_BASE_URL"], !url.isEmpty {
            return url
        }
        if let url = loadFromPlist(key: "AI_BASE_URL"), !url.isEmpty {
            return url
        }

        switch aiProvider {
        case .kimi:
            return "https://api.moonshot.cn/v1"
        case .qwen:
            return qwenDashScopeCompatibleBaseURL
        }
    }

    /// 通义千问 OpenAI 兼容接口根路径（不要尾 `/`）。国内默认北京；海外见百炼文档 `dashscope-intl` / `dashscope-us`。
    static var qwenDashScopeCompatibleBaseURL: String {
        if let u = ProcessInfo.processInfo.environment["DASHSCOPE_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return u.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let u = loadFromPlist(key: "DASHSCOPE_BASE_URL")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return u.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "https://dashscope.aliyuncs.com/compatible-mode/v1"
    }

    /// TTS 服务提供商
    static var ttsProvider: TTSProvider {
        let providerString = ProcessInfo.processInfo.environment["TTS_PROVIDER"]
            ?? loadFromPlist(key: "TTS_PROVIDER")
            ?? "azure"

        return TTSProvider(rawValue: providerString) ?? .azure
    }

    /// Azure 区域
    static var azureRegion: String {
        return ProcessInfo.processInfo.environment["AZURE_REGION"]
            ?? loadFromPlist(key: "AZURE_REGION")
            ?? "eastasia"
    }

    // MARK: - 应用配置

    /// 应用版本
    static var appVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// 构建版本
    static var buildVersion: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// 是否为调试模式
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - 功能开关

    /// 是否启用背景音乐
    static var enableBackgroundMusic: Bool {
        return UserDefaults.standard.bool(forKey: "enableBackgroundMusic", defaultValue: true)
    }

    /// 是否启用音效
    static var enableSoundEffects: Bool {
        return UserDefaults.standard.bool(forKey: "enableSoundEffects", defaultValue: true)
    }

    /// 是否启用缓存
    static var enableCache: Bool {
        return UserDefaults.standard.bool(forKey: "enableCache", defaultValue: true)
    }

    /// TTS/分段合成最大并发（讯飞等接口上限较高时可调大，建议不超过 100）。
    static var maxConcurrentTasks: Int {
        let v = UserDefaults.standard.integer(forKey: "maxConcurrentTasks", defaultValue: 24)
        return min(100, max(1, v))
    }

    // MARK: - 音频配置

    /// 背景音乐音量
    static var backgroundMusicVolume: Float {
        return UserDefaults.standard.float(forKey: "backgroundMusicVolume", defaultValue: 0.3)
    }

    /// 语音音量
    static var voiceVolume: Float {
        return UserDefaults.standard.float(forKey: "voiceVolume", defaultValue: 1.0)
    }

    /// 音效音量
    static var soundEffectsVolume: Float {
        return UserDefaults.standard.float(forKey: "soundEffectsVolume", defaultValue: 0.5)
    }

    /// 播放速度
    static var playbackRate: Float {
        return UserDefaults.standard.float(forKey: "playbackRate", defaultValue: 1.0)
    }


    /// 自建发现页聚合 API 根地址（如 https://api.example.com），末尾无斜杠。未配置则只用笔趣阁直连。
    /// 同一服务可实现 `GET/POST /v1/playback/analysis`：云端仅存**分析索引**（UTF-8 偏移、类型/角色/场景等），**不存正文**；正文始终在客户端拉取后再还原。
    static var discoverAPIBaseURL: String? {
        if let e = ProcessInfo.processInfo.environment["DISCOVER_API_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            return e
        }
        if let p = loadFromPlist(key: "DISCOVER_API_BASE_URL")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        return nil
    }

    /// 认证服务根地址（如 https://api.example.com），用于号码认证一键登录换取会话。
    /// 未单独配置时，会回退到 `DISCOVER_API_BASE_URL`。
    static var authAPIBaseURL: String? {
        if let e = ProcessInfo.processInfo.environment["AUTH_API_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            return e
        }
        if let p = loadFromPlist(key: "AUTH_API_BASE_URL")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        return discoverAPIBaseURL
    }

    /// 阿里云号码认证 SDK 鉴权串，建议由服务端安全下发；当前版本优先读取本地配置。
    static var numberAuthSDKInfo: String? {
        if let e = ProcessInfo.processInfo.environment["NUMBER_AUTH_SDK_INFO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            return e
        }
        if let p = loadFromPlist(key: "NUMBER_AUTH_SDK_INFO")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        return nil
    }

    /// 单章送入 TTS 分析的最大字数（过大增加耗时与费用）。
    static var chapterTTSDisplayMaxChars: Int {
        let v = UserDefaults.standard.integer(forKey: "chapterTTSDisplayMaxChars")
        if v > 0 { return min(v, 50_000) }
        return 2000
    }

    /// 是否在生成过程中边下边播（默认开启；关闭则整章合成完再播，等待长）。
    static var streamPlaybackWhileGenerating: Bool {
        UserDefaults.standard.bool(forKey: "streamPlaybackWhileGenerating", defaultValue: true)
    }

    /// 流式播放：累计缓冲的片段时长（秒）达到该值，或已缓冲 ≥2 段时，**提前开播**（不再固定等 3 段/20 秒）。
    static var streamPlaybackStartMinTotalSeconds: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "streamPlaybackStartMinTotalSeconds", defaultValue: 6)
        if v > 0, v < 300 { return v }
        return 6
    }

    /// 在「本章节全部片段时间线生成完毕」后，是否在后台对**下一章**跑一遍完整合成以预热 TTS 缓存（减轻切章冷启动）。
    static var prefetchEntireNextChapterWhenCurrentReady: Bool {
        UserDefaults.standard.bool(forKey: "prefetchEntireNextChapterWhenCurrentReady", defaultValue: true)
    }

    /// 当前章播放到该进度（0～1）时开始预拉「下一章」正文到本地缓存。
    static var chapterPrefetchProgressThreshold: Double {
        let v = UserDefaults.standard.double(forKey: "chapterPrefetchProgressThreshold")
        if v > 0, v < 1 { return v }
        return 0.18
    }

    static var hasConfiguredAIAPIKey: Bool {
        let keys = aiProviderConfigKeys(for: aiProvider)
        return loadFirstNonEmptyValue(fromEnvironmentKeys: keys) != nil
            || loadFirstNonEmptyValue(fromKeychainKeys: keys) != nil
            || loadFirstNonEmptyValue(fromPlistKeys: keys) != nil
    }

    /// 当 **Kimi 单次分析请求** 在 120s 内超时后，用通义续跑分析；需百炼/ DashScope 的 key。
    /// 未配置时仍只用 Kimi（超时后报原有错误，不会静默失败）。
    static var qwenApiKeyForKimiTimeoutFallback: String? {
        let envKeys = ["QWEN_API_KEY", "DASHSCOPE_API_KEY"]
        if let k = loadFirstNonEmptyValue(fromEnvironmentKeys: envKeys) { return k }
        if let k = loadFirstNonEmptyValue(fromKeychainKeys: envKeys) { return k }
        for key in envKeys {
            if let k = loadFromPlist(key: key), !k.isEmpty { return k }
        }
        return nil
    }

    static var hasConfiguredTTSAPIKey: Bool {
        loadFirstNonEmptyValue(fromEnvironmentKeys: ["TTS_API_KEY"]) != nil
            || loadFirstNonEmptyValue(fromKeychainKeys: ["TTS_API_KEY"]) != nil
            || loadFirstNonEmptyValue(fromPlistKeys: ["TTS_API_KEY"]) != nil
    }

    // MARK: - Private Methods

    /// 从 Plist 文件读取配置
    private static func loadFromPlist(key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path) else {
            return nil
        }

        return config[key] as? String
    }

    private static func loadFirstNonEmptyValue(fromEnvironmentKeys keys: [String]) -> String? {
        for key in keys {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func loadFirstNonEmptyValue(fromKeychainKeys keys: [String]) -> String? {
        for key in keys {
            if let value = KeychainManager.load(key: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func loadFirstNonEmptyValue(fromPlistKeys keys: [String]) -> String? {
        for key in keys {
            if let value = loadFromPlist(key: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func aiProviderConfigKeys(for provider: AIProvider) -> [String] {
        switch provider {
        case .kimi:
            return ["KIMI_API_KEY", "MOONSHOT_API_KEY", "AI_API_KEY"]
        case .qwen:
            return ["QWEN_API_KEY", "DASHSCOPE_API_KEY", "AI_API_KEY"]
        }
    }
}

// MARK: - Keychain 管理器

/// Keychain 管理器
class KeychainManager {

    /// 保存到 Keychain
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // 删除旧值
        SecItemDelete(query as CFDictionary)

        // 添加新值
        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            print("✅ Keychain 保存成功: \(key)")
        } else {
            print("⚠️ Keychain 保存失败: \(status)")
        }
    }

    /// 从 Keychain 读取
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        return nil
    }

    /// 从 Keychain 删除
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// 清空所有 Keychain 数据
    static func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword
        ]

        SecItemDelete(query as CFDictionary)
        print("🗑️ Keychain 已清空")
    }
}

// MARK: - UserDefaults 扩展

extension UserDefaults {

    /// 获取 Bool 值，带默认值
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }

    /// 获取 Int 值，带默认值
    func integer(forKey key: String, defaultValue: Int) -> Int {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return integer(forKey: key)
    }

    /// 获取 Float 值，带默认值
    func float(forKey key: String, defaultValue: Float) -> Float {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return float(forKey: key)
    }

    /// 获取 Double 值，带默认值
    func double(forKey key: String, defaultValue: Double) -> Double {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return double(forKey: key)
    }
}

// MARK: - Bundle 扩展

extension Bundle {

    /// 应用版本
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// 构建版本
    var buildVersion: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// 完整版本信息
    var fullVersion: String {
        return "\(appVersion) (\(buildVersion))"
    }
}

// MARK: - 配置初始化助手

/// 配置初始化助手
class ConfigHelper {

    /// 首次启动初始化
    static func initializeOnFirstLaunch() {
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunched")

        if !hasLaunched {
            print("🎉 首次启动，初始化配置...")

            // 设置默认值
            UserDefaults.standard.set(true, forKey: "enableBackgroundMusic")
            UserDefaults.standard.set(true, forKey: "enableSoundEffects")
            UserDefaults.standard.set(true, forKey: "enableCache")
            UserDefaults.standard.set(24, forKey: "maxConcurrentTasks")
            UserDefaults.standard.set(true, forKey: "streamPlaybackWhileGenerating")
            UserDefaults.standard.set(0.3, forKey: "backgroundMusicVolume")
            UserDefaults.standard.set(1.0, forKey: "voiceVolume")
            UserDefaults.standard.set(0.5, forKey: "soundEffectsVolume")
            UserDefaults.standard.set(1.0, forKey: "playbackRate")

            UserDefaults.standard.set(true, forKey: "hasLaunched")

            print("✅ 配置初始化完成")
        }
    }

    /// 验证配置
    static func validateConfiguration() -> Bool {
        var isValid = true

        // 检查 API 密钥
        if Config.hasConfiguredAIAPIKey {
            print("✅ AI API Key 已配置")
        } else {
            print("❌ AI API Key 未配置")
            isValid = false
        }

        if Config.hasConfiguredTTSAPIKey {
            print("✅ TTS API Key 已配置")
        } else {
            print("❌ TTS API Key 未配置")
            isValid = false
        }

        return isValid
    }

    /// 打印配置信息
    static func printConfiguration() {
        print("📋 应用配置信息:")
        print("   版本: \(Config.appVersion)")
        print("   构建: \(Config.buildVersion)")
        print("   调试模式: \(Config.isDebug)")
        print("   AI 提供商: \(Config.aiProvider)")
        print("   AI 模型: \(Config.aiModel)")
        print("   AI 基础地址: \(Config.aiBaseURL ?? "local")")
        if Config.aiProvider == .kimi {
            let fb = Config.qwenApiKeyForKimiTimeoutFallback != nil
            print("   Kimi 超时后降级通义: \(fb ? "已配置 (QWEN / DASHSCOPE Key)" : "未配置，超时后不会自动切到百炼")")
        }
        print("   TTS 提供商: \(Config.ttsProvider)")
        print("   Azure 区域: \(Config.azureRegion)")
        print("   背景音乐: \(Config.enableBackgroundMusic)")
        print("   音效: \(Config.enableSoundEffects)")
        print("   缓存: \(Config.enableCache)")
        print("   TTS 最大并发: \(Config.maxConcurrentTasks)（讯飞等接口上限 100，勿超过）")
        print("   边播边生成: \(Config.streamPlaybackWhileGenerating)")
        print("   流式开场缓冲(秒, ≥2段或总时长达此值即播): \(String(format: "%.1f", Config.streamPlaybackStartMinTotalSeconds))")
        print("   章末后台预合成下一章: \(Config.prefetchEntireNextChapterWhenCurrentReady)")
        print("   下一章预取进度阈值: \(String(format: "%.0f%%", Config.chapterPrefetchProgressThreshold * 100))（实际会按段数/并发微调）")
    }

    #if DEBUG
    /// Debug 专用：只打印配置是否存在和长度，绝不输出密钥明文。
    static func printAIConfigurationDiagnostics() {
        print("[AIConfig] AI_PROVIDER=\(Config.aiProvider.rawValue)")
        print("[AIConfig] AI_MODEL=\(Config.aiModel)")
        print("[AIConfig] AI_BASE_URL=\(Config.aiBaseURL ?? "nil")")
        print("[AIConfig] DASHSCOPE_BASE_URL=\(Config.qwenDashScopeCompatibleBaseURL)")
        for key in ["KIMI_API_KEY", "MOONSHOT_API_KEY", "AI_API_KEY", "QWEN_API_KEY", "DASHSCOPE_API_KEY"] {
            let value = ProcessInfo.processInfo.environment[key]
                ?? KeychainManager.load(key: key)
                ?? Self.loadDiagnosticPlistValue(key: key)
            let state = value.map { "configured length=\($0.count)" } ?? "missing"
            print("[AIConfig] \(key)=\(state)")
        }
    }

    private static func loadDiagnosticPlistValue(key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path) else {
            return nil
        }
        return config[key] as? String
    }
    #endif
}
