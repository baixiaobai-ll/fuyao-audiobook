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
        // 优先从环境变量读取
        if let key = ProcessInfo.processInfo.environment["AI_API_KEY"], !key.isEmpty {
            return key
        }

        // 从 Keychain 读取
        if let key = KeychainManager.load(key: "AI_API_KEY"), !key.isEmpty {
            return key
        }

        // 从配置文件读取
        if let key = loadFromPlist(key: "AI_API_KEY"), !key.isEmpty {
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
        .qwen
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

    /// 当前章播放到该进度（0～1）时开始预拉「下一章」正文到本地缓存。
    static var chapterPrefetchProgressThreshold: Double {
        let v = UserDefaults.standard.double(forKey: "chapterPrefetchProgressThreshold")
        if v > 0, v < 1 { return v }
        return 0.18
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
        do {
            _ = Config.aiApiKey
            print("✅ AI API Key 已配置")
        } catch {
            print("❌ AI API Key 未配置")
            isValid = false
        }

        do {
            _ = Config.ttsApiKey
            print("✅ TTS API Key 已配置")
        } catch {
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
        print("   TTS 提供商: \(Config.ttsProvider)")
        print("   Azure 区域: \(Config.azureRegion)")
        print("   背景音乐: \(Config.enableBackgroundMusic)")
        print("   音效: \(Config.enableSoundEffects)")
        print("   缓存: \(Config.enableCache)")
        print("   TTS 最大并发: \(Config.maxConcurrentTasks)（讯飞等接口上限 100，勿超过）")
        print("   边播边生成: \(Config.streamPlaybackWhileGenerating)")
        print("   下一章预取进度阈值: \(String(format: "%.0f%%", Config.chapterPrefetchProgressThreshold * 100))（实际会按段数/并发微调）")
    }
}
