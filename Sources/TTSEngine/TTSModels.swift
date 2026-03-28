//
//  TTSModels.swift
//  AI有声书
//
//  TTS 相关的数据模型
//

import Foundation

// MARK: - 音色

/// 音色信息
struct Voice: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let gender: VoiceGender
    let language: String
    let provider: TTSProvider
    let sampleRate: Int
    var description: String?

    init(
        id: String,
        name: String,
        gender: VoiceGender,
        language: String = "zh-CN",
        provider: TTSProvider,
        sampleRate: Int = 24000,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.gender = gender
        self.language = language
        self.provider = provider
        self.sampleRate = sampleRate
        self.description = description
    }

    enum VoiceGender: String, Codable, Sendable {
        case male
        case female
        case neutral
        case child
        case elder
    }
}

// MARK: - TTS 提供商

/// TTS 服务提供商
public enum TTSProvider: String, Codable, Sendable {
    case openai
    case azure
    case aliyun
    case xfyun
    case local
}

// MARK: - 音频数据

/// 音频数据
public struct AudioData: Codable, Sendable {
    public let data: Data
    public let format: AudioFormat
    public let duration: TimeInterval
    public let sampleRate: Int

    public enum AudioFormat: String, Codable, Sendable {
        case mp3
        case wav
        case aac
        case opus
    }
}

// MARK: - TTS 请求

/// TTS 合成请求
struct TTSRequest {
    let text: String
    let voice: Voice
    let ssml: String?
    let speed: Double
    let pitch: Double
    let volume: Double

    init(
        text: String,
        voice: Voice,
        ssml: String? = nil,
        speed: Double = 1.0,
        pitch: Double = 1.0,
        volume: Double = 1.0
    ) {
        self.text = text
        self.voice = voice
        self.ssml = ssml
        self.speed = speed
        self.pitch = pitch
        self.volume = volume
    }
}

// MARK: - TTS 配置

/// TTS 配置
struct TTSConfig: Codable {
    var provider: TTSProvider
    var apiKey: String
    var baseURL: String?
    var defaultVoice: Voice?
    var enableCache: Bool
    var maxConcurrentRequests: Int

    init(
        provider: TTSProvider,
        apiKey: String,
        baseURL: String? = nil,
        defaultVoice: Voice? = nil,
        enableCache: Bool = true,
        maxConcurrentRequests: Int = 3
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultVoice = defaultVoice
        self.enableCache = enableCache
        self.maxConcurrentRequests = maxConcurrentRequests
    }
}

// MARK: - 预设音色库

/// 预设音色库
struct VoiceLibrary {

    /// OpenAI 音色
    static let openAIVoices: [Voice] = [
        Voice(id: "alloy", name: "Alloy", gender: .neutral, provider: .openai, description: "中性、平衡"),
        Voice(id: "echo", name: "Echo", gender: .male, provider: .openai, description: "男性、沉稳"),
        Voice(id: "fable", name: "Fable", gender: .male, provider: .openai, description: "男性、叙事感"),
        Voice(id: "onyx", name: "Onyx", gender: .male, provider: .openai, description: "男性、深沉"),
        Voice(id: "nova", name: "Nova", gender: .female, provider: .openai, description: "女性、活力"),
        Voice(id: "shimmer", name: "Shimmer", gender: .female, provider: .openai, description: "女性、温柔")
    ]

    /// Azure 音色（中文）
    static let azureVoices: [Voice] = [
        Voice(id: "zh-CN-XiaoxiaoNeural", name: "晓晓", gender: .female, provider: .azure, description: "女性、温柔、适合旁白"),
        Voice(id: "zh-CN-YunxiNeural", name: "云希", gender: .male, provider: .azure, description: "男性、沉稳、适合旁白"),
        Voice(id: "zh-CN-YunjianNeural", name: "云健", gender: .male, provider: .azure, description: "男性、年轻、活力"),
        Voice(id: "zh-CN-XiaoyiNeural", name: "晓伊", gender: .female, provider: .azure, description: "女性、甜美"),
        Voice(id: "zh-CN-YunyangNeural", name: "云扬", gender: .male, provider: .azure, description: "男性、专业、新闻感"),
        Voice(id: "zh-CN-XiaochenNeural", name: "晓辰", gender: .female, provider: .azure, description: "女性、轻松、自然"),
        Voice(id: "zh-CN-XiaohanNeural", name: "晓涵", gender: .female, provider: .azure, description: "女性、温暖"),
        Voice(id: "zh-CN-XiaomengNeural", name: "晓梦", gender: .female, provider: .azure, description: "女性、少女感"),
        Voice(id: "zh-CN-XiaomoNeural", name: "晓墨", gender: .female, provider: .azure, description: "女性、成熟"),
        Voice(id: "zh-CN-XiaoqiuNeural", name: "晓秋", gender: .female, provider: .azure, description: "女性、知性"),
        Voice(id: "zh-CN-XiaoshuangNeural", name: "晓双", gender: .child, provider: .azure, description: "儿童、活泼"),
        Voice(id: "zh-CN-XiaoxuanNeural", name: "晓萱", gender: .female, provider: .azure, description: "女性、优雅"),
        Voice(id: "zh-CN-XiaoyanNeural", name: "晓颜", gender: .female, provider: .azure, description: "女性、亲切"),
        Voice(id: "zh-CN-XiaoyouNeural", name: "晓悠", gender: .child, provider: .azure, description: "儿童、可爱"),
        Voice(id: "zh-CN-YunfengNeural", name: "云枫", gender: .male, provider: .azure, description: "男性、老年、沉稳"),
        Voice(id: "zh-CN-YunhaoNeural", name: "云皓", gender: .male, provider: .azure, description: "男性、广告感"),
        Voice(id: "zh-CN-YunxiaNeural", name: "云夏", gender: .male, provider: .azure, description: "男性、年轻")
    ]

    /// 科大讯飞超拟人音色
    static let xfyunVoices: [Voice] = [
        Voice(id: "x6_lingxiaoxuan_pro", name: "聆小璇", gender: .female, provider: .xfyun, sampleRate: 24000, description: "女性、温柔、标准"),
        Voice(id: "x6_lingfeiyi_pro", name: "聆飞逸", gender: .male, provider: .xfyun, sampleRate: 24000, description: "男性、沉稳"),
        Voice(id: "x6_lingyuyan_pro", name: "聆玉言", gender: .female, provider: .xfyun, sampleRate: 24000, description: "女性、知性"),
        Voice(id: "x6_lingfeiyue_pro", name: "聆飞月", gender: .female, provider: .xfyun, sampleRate: 24000, description: "女性、甜美"),
        Voice(id: "x6_lingyuyan_omni", name: "聆玉言Omni", gender: .female, provider: .xfyun, sampleRate: 24000, description: "女性、全能")
    ]

    /// 获取所有音色
    static func getAllVoices() -> [Voice] {
        return openAIVoices + azureVoices + xfyunVoices
    }

    /// 根据性别筛选音色
    static func getVoices(for gender: Voice.VoiceGender, provider: TTSProvider? = nil) -> [Voice] {
        let allVoices = getAllVoices()
        return allVoices.filter { voice in
            let genderMatch = voice.gender == gender
            let providerMatch = provider == nil || voice.provider == provider
            return genderMatch && providerMatch
        }
    }

    /// 获取默认音色
    static func getDefaultVoice(for gender: Voice.VoiceGender, provider: TTSProvider = .xfyun) -> Voice? {
        switch provider {
        case .xfyun:
            switch gender {
            case .male:
                return xfyunVoices.first { $0.id == "x6_lingfeiyi_pro" }
            case .female:
                return xfyunVoices.first { $0.id == "x6_lingxiaoxuan_pro" }
            case .child:
                return xfyunVoices.first { $0.id == "x6_lingfeiyue_pro" }
            case .elder:
                return xfyunVoices.first { $0.id == "x6_lingfeiyi_pro" }
            case .neutral:
                return xfyunVoices.first { $0.id == "x6_lingxiaoxuan_pro" }
            }
        case .azure:
            switch gender {
            case .male:
                return azureVoices.first { $0.id == "zh-CN-YunxiNeural" }
            case .female:
                return azureVoices.first { $0.id == "zh-CN-XiaoxiaoNeural" }
            case .child:
                return azureVoices.first { $0.id == "zh-CN-XiaoyouNeural" }
            case .elder:
                return azureVoices.first { $0.id == "zh-CN-YunfengNeural" }
            case .neutral:
                return azureVoices.first { $0.id == "zh-CN-XiaoxiaoNeural" }
            }
        case .openai:
            switch gender {
            case .male:
                return openAIVoices.first { $0.id == "echo" }
            case .female:
                return openAIVoices.first { $0.id == "nova" }
            case .neutral:
                return openAIVoices.first { $0.id == "alloy" }
            default:
                return openAIVoices.first { $0.id == "alloy" }
            }
        default:
            return nil
        }
    }
}
