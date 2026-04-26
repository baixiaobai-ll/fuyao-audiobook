//
//  Models.swift
//  AI有声书
//
//  文本分析相关的数据模型
//

import Foundation

// MARK: - 文本片段类型

/// 文本片段类型
public enum SegmentType: String, Codable, Sendable {
    case dialogue      // 对话
    case narration     // 旁白
    case description   // 描述
    case thought       // 内心独白
}

// MARK: - 情感类型

/// 情感类型
public enum Emotion: String, Codable, Sendable {
    case neutral       // 平静
    case happy         // 开心
    case sad           // 悲伤
    case angry         // 愤怒
    case excited       // 兴奋
    case fearful       // 恐惧
    case surprised     // 惊讶
    case tender        // 温柔

    /// 对应的语音参数调整
    var prosodyAdjustment: ProsodyAdjustment {
        switch self {
        case .neutral:
            return ProsodyAdjustment(rate: 1.0, pitch: 1.0, volume: 1.0)
        case .happy:
            return ProsodyAdjustment(rate: 1.1, pitch: 1.15, volume: 1.05)
        case .sad:
            return ProsodyAdjustment(rate: 0.9, pitch: 0.85, volume: 0.9)
        case .angry:
            return ProsodyAdjustment(rate: 1.15, pitch: 1.2, volume: 1.15)
        case .excited:
            return ProsodyAdjustment(rate: 1.2, pitch: 1.25, volume: 1.1)
        case .fearful:
            return ProsodyAdjustment(rate: 1.1, pitch: 1.1, volume: 0.85)
        case .surprised:
            return ProsodyAdjustment(rate: 1.05, pitch: 1.3, volume: 1.1)
        case .tender:
            return ProsodyAdjustment(rate: 0.95, pitch: 0.95, volume: 0.95)
        }
    }
}

/// 韵律调整参数
public struct ProsodyAdjustment {
    let rate: Double    // 语速倍率
    let pitch: Double   // 音调倍率
    let volume: Double  // 音量倍率
}

// MARK: - 场景类型

/// 场景类型
public enum SceneType: String, Codable, Sendable {
    case peaceful      // 平和场景
    case tense         // 紧张场景
    case battle        // 战斗场景
    case romantic      // 浪漫场景
    case mysterious    // 神秘场景
    case sad           // 悲伤场景
    case festive       // 欢庆场景

    /// 推荐的背景音乐类型
    var recommendedMusicType: String {
        switch self {
        case .peaceful: return "ambient_calm"
        case .tense: return "suspense"
        case .battle: return "action_intense"
        case .romantic: return "romantic_soft"
        case .mysterious: return "mystery"
        case .sad: return "melancholy"
        case .festive: return "celebration"
        }
    }
}

// MARK: - 叙事位阶 & 音色人设标签（Kimi → 客户端）

public enum NarrativeRole: String, Codable, Sendable, Hashable {
    /// 作品视点主角 / 第一男主或第一女主
    case primary
    /// 重要配角
    case secondary
    /// 龙套、路人
    case tertiary
}

/// Kimi 在 `characters[].voiceArchetype` 中返回的**软标签**：描述「该角色适合哪种听感人设」，
/// **不是**讯飞 `vcn` ID。与 `narrativeRole` 一起决定客户端打分；`NarrativeRole.primary` + 成年男声 → 强绑定「聆飞逸」位。
public enum VoiceArchetypeTag: String, Codable, Sendable, Hashable {
    /// 老年男性：长辈、老者、掌门、族长等
    case elderMale = "elder_male"
    /// 老年女性：老妇、婆婆、嬷嬷等
    case elderFemale = "elder_female"
    /// 男童、小厮、店小二、年轻男配、音色偏轻的男角
    case boyOrYoungMale = "boy_young_male"
    /// 女童、少女、年轻女配
    case girlOrYoungFemale = "girl_young_female"
    /// 成年男性主角、将军、沉稳男配、反派男等
    case adultMale = "adult_male"
    /// 成年女主、温柔女性、贵妇、师姐等
    case adultFemale = "adult_female"
    /// 性别 / 年龄信息不足，或龙套 NPC，用中性叙述向兜底
    case neutral = "neutral"
}

// MARK: - 角色

/// 角色信息
public struct Character: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let gender: Gender
    /// Kimi 给出的音色人设标签；`nil` 时客户端完全按 `gender` + 本地启发式推断（与旧版兼容）。
    public var voiceArchetype: VoiceArchetypeTag?
    /// 叙事位阶：区分男主与男配，避免男配先占「聆飞逸」。
    public var narrativeRole: NarrativeRole?
    public var voiceId: String?
    public var description: String?

    public init(
        id: UUID = UUID(),
        name: String,
        gender: Gender,
        voiceArchetype: VoiceArchetypeTag? = nil,
        narrativeRole: NarrativeRole? = nil,
        voiceId: String? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.gender = gender
        self.voiceArchetype = voiceArchetype
        self.narrativeRole = narrativeRole
        self.voiceId = voiceId
        self.description = description
    }

    public enum Gender: String, Codable, Sendable {
        case male
        case female
        case neutral
        case child
        case elder
    }
}

// MARK: - 场景

/// 场景信息
public struct NovelScene: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let type: SceneType
    public let description: String
    public let intensity: Double

    public init(id: UUID = UUID(), type: SceneType, description: String, intensity: Double = 0.5) {
        self.id = id
        self.type = type
        self.description = description
        self.intensity = min(max(intensity, 0.0), 1.0)
    }
}

// MARK: - 文本片段

/// 文本片段
public struct TextSegment: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let type: SegmentType
    public let speaker: Character?
    public let emotion: Emotion
    public let scene: NovelScene
    public let order: Int

    public init(
        id: UUID = UUID(),
        text: String,
        type: SegmentType,
        speaker: Character? = nil,
        emotion: Emotion = .neutral,
        scene: NovelScene,
        order: Int
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.speaker = speaker
        self.emotion = emotion
        self.scene = scene
        self.order = order
    }
}

// MARK: - 分析结果

/// 文本分析结果
struct AnalysisResult: Codable {
    let segments: [TextSegment]
    let characters: [Character]
    let scenes: [NovelScene]
    let metadata: NovelMetadata

    init(segments: [TextSegment], characters: [Character], scenes: [NovelScene], metadata: NovelMetadata) {
        self.segments = segments
        self.characters = characters
        self.scenes = scenes
        self.metadata = metadata
    }
}

/// 小说元数据
struct NovelMetadata: Codable {
    let title: String
    let author: String?
    let chapterTitle: String?
    let wordCount: Int
    let estimatedDuration: TimeInterval  // 预估时长（秒）

    init(title: String, author: String? = nil, chapterTitle: String? = nil, wordCount: Int, estimatedDuration: TimeInterval = 0) {
        self.title = title
        self.author = author
        self.chapterTitle = chapterTitle
        self.wordCount = wordCount
        self.estimatedDuration = estimatedDuration
    }
}
