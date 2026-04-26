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

    /// 科大讯飞超拟人音色（白名单：仅保留主控确认仍有效的 8 个发音人）
    /// 已废弃的旧 ID 由 `compatibleXfyunSuperVoiceId` 做迁移映射，避免历史 voiceBindings 直接 404。
    ///
    /// **数组顺序的语义**（2026-04-26 修订）：
    /// - provider 为 **讯飞** 时，`VoiceManager.smartAssignVoices` 已改为用 `XfyunVoiceRoleCatalog`
    ///   按「老人 / 孩童 / 成年男女 / 中性」等业务需求对各 `voiceId` **打分**，在未被旁白槽、
    ///   未命名对话槽占用的候选里取最高分；**本数组顺序仅在同分时作次要优先级**。
    /// - 其他 provider 仍可能按 `Voice.gender` + 数组顺序做简单匹配。
    /// 排序原则：把听感更通用的声音排在前面，便于同分时的稳定默认。
    static let xfyunVoices: [Voice] = [
        Voice(id: "x6_lingxiaoxuan_pro", name: "聆小璇", gender: .female, provider: .xfyun, sampleRate: 24000, description: "女性、温柔、标准"),
        Voice(id: "x6_lingfeiyi_pro", name: "聆飞逸", gender: .male, provider: .xfyun, sampleRate: 24000, description: "男性、沉稳"),
        // 聆伯松：稳健男声、故事感。第 3 位是为了让「第二个普通男角色」
        // 优先拿到此稳健男声，而不是同分时默认拿到「小奶狗弟弟」致老者/旁白听感违和。
        Voice(id: "x6_lingbosong_pro", name: "聆伯松", gender: .male, provider: .xfyun, sampleRate: 24000, description: "男性、稳健、故事感"),
        // 年轻男声；后置给真正的年轻男角色，避免同分下旁白/老者误选。
        Voice(id: "x6_xiaonaigoudidi_mini", name: "小奶狗弟弟", gender: .male, provider: .xfyun, sampleRate: 24000, description: "男性、年轻、温柔"),
        // 男声、古风旁白感
        Voice(id: "x6_gufengpangbai_pro", name: "古风旁白", gender: .male, provider: .xfyun, sampleRate: 24000, description: "男性、古风、旁白感"),
        Voice(id: "x5_lingyuzhao_flow", name: "灵玉昭", gender: .female, provider: .xfyun, sampleRate: 24000, description: "女性、流式、知性"),
        Voice(id: "x6_lingxiaoyue_pro", name: "聆小玥", gender: .female, provider: .xfyun, sampleRate: 24000, description: "女性、清亮、年轻"),
        Voice(id: "x6_lingyuyan_pro", name: "聆玉言", gender: .female, provider: .xfyun, sampleRate: 24000, description: "女性、知性")
    ]

    /// 获取所有音色
    static func getAllVoices() -> [Voice] {
        return openAIVoices + azureVoices + xfyunVoices
    }

    static func getVoices(for provider: TTSProvider) -> [Voice] {
        switch provider {
        case .openai:
            return openAIVoices
        case .azure:
            return azureVoices
        case .xfyun:
            return xfyunVoices
        default:
            return []
        }
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
                // 白名单里没有真正意义上的儿童音；选最年轻的男声兜底（之前指向不存在的 x6_lingfeiyue_pro 是 bug）
                return xfyunVoices.first { $0.id == "x6_xiaonaigoudidi_mini" }
            case .elder:
                // 白名单里没有真正意义上的老年音；选最稳健的男声兜底
                return xfyunVoices.first { $0.id == "x6_lingbosong_pro" }
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

    static func getPreferredNarrationVoice(for provider: TTSProvider = .xfyun) -> Voice? {
        switch provider {
        case .xfyun:
            // 优先用古风旁白做朗读底色，找不到再退回到聆飞逸。
            return xfyunVoices.first { $0.id == "x6_gufengpangbai_pro" }
                ?? xfyunVoices.first { $0.id == "x6_lingfeiyi_pro" }
                ?? xfyunVoices.first
        case .azure:
            return azureVoices.first { $0.id == "zh-CN-YunxiNeural" } ?? azureVoices.first
        case .openai:
            return openAIVoices.first { $0.id == "echo" } ?? openAIVoices.first
        default:
            return nil
        }
    }

    /// 给 `type=dialogue` 但 `speaker=nil` 的"未命名对话"段落使用的专属音色。
    ///
    /// **为什么单独一个槽**：之前这类段落直接复用旁白音色，导致用户听感上"对话像是被吞了
    /// 变成旁白朗读"，是 2026-04-26 用户反馈"旁白被错认"的根因之一。
    /// 这个槽要满足：
    /// 1. 跟旁白音色**听感差异明显**（比如旁白是男声、未命名对话就用女声）；
    /// 2. 跟具体角色不会撞车（VoiceManager 把它加进 usedVoices，禁止分配给角色）；
    /// 3. 失败时退化到旁白，至少保证能播。
    static func getPreferredUnknownDialogueVoice(for provider: TTSProvider = .xfyun) -> Voice? {
        switch provider {
        case .xfyun:
            // 旁白默认是男声"古风旁白"，未命名对话用女声"聆玉言"形成对比。
            // 找不到时退回到中性的"聆小璇"，再不行用旁白音色。
            return xfyunVoices.first { $0.id == "x6_lingyuyan_pro" }
                ?? xfyunVoices.first { $0.id == "x6_lingxiaoxuan_pro" }
                ?? getPreferredNarrationVoice(for: .xfyun)
        case .azure:
            return azureVoices.first { $0.id == "zh-CN-XiaomoNeural" }
                ?? azureVoices.first { $0.id == "zh-CN-XiaoxiaoNeural" }
                ?? getPreferredNarrationVoice(for: .azure)
        case .openai:
            return openAIVoices.first { $0.id == "nova" }
                ?? openAIVoices.first { $0.id == "alloy" }
                ?? getPreferredNarrationVoice(for: .openai)
        default:
            return nil
        }
    }

    /// 把历史 / 旧版本里残留的讯飞 voiceId 透明迁移到当前白名单内的有效 ID，
    /// 让保存在 `Book.voiceBindings` 里的旧值仍能正确播放，避免直接 404。
    /// `x5_lingyuzhao_flow` 仍在白名单内（主控确认有效），不再做映射。
    static func compatibleXfyunSuperVoiceId(for voiceId: String) -> String {
        switch voiceId {
        // 流式接口被弃用，但发音人本体仍存在 → 映射到同声线女声
        case "x5_lingxiaotang_flow":
            return "x6_lingxiaoyue_pro"
        // 已下线的儿童 / 个性发音人 → 映射到白名单里最近似的男青年
        case "x6_dudulibao_pro":
            return "x6_xiaonaigoudidi_mini"
        // 已下线的女性角色音 → 映射到白名单女声
        case "x6_wumeinv_pro":
            return "x6_lingxiaoxuan_pro"
        // 已下线的男性聊天 / 播报音 → 映射到聆飞逸
        case "x6_feizheChat_pro":
            return "x6_lingfeiyi_pro"
        // 已下线的男性新闻播报音 → 映射到古风旁白（同样偏旁白感）
        case "x6_lingfeibo_pro":
            return "x6_gufengpangbai_pro"
        // 已下线的角色感长者音 → 映射到稳健男声
        case "x6_huajidama_pro", "x6_ruyadashu_pro":
            return "x6_lingbosong_pro"
        // 老的非超拟人通用 ID → 映射到聆飞逸（保留早先发现的兜底语义）
        case "x4_lingfei":
            return "x6_lingfeiyi_pro"
        default:
            return voiceId
        }
    }
}
