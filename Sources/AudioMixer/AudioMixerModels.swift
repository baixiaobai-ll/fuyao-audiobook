//
//  AudioMixerModels.swift
//  AI有声书
//
//  音频混合相关的数据模型
//

import Foundation

// MARK: - 混合配置

/// 音频混合配置
struct AudioMixConfig: Codable {
    var enableBackgroundMusic: Bool
    var backgroundMusicVolume: Float
    var voiceVolume: Float
    var enableSoundEffects: Bool
    var soundEffectsVolume: Float
    var fadeInDuration: TimeInterval
    var fadeOutDuration: TimeInterval

    init(
        enableBackgroundMusic: Bool = true,
        backgroundMusicVolume: Float = 0.3,
        voiceVolume: Float = 1.0,
        enableSoundEffects: Bool = true,
        soundEffectsVolume: Float = 0.5,
        fadeInDuration: TimeInterval = 2.0,
        fadeOutDuration: TimeInterval = 2.0
    ) {
        self.enableBackgroundMusic = enableBackgroundMusic
        self.backgroundMusicVolume = backgroundMusicVolume
        self.voiceVolume = voiceVolume
        self.enableSoundEffects = enableSoundEffects
        self.soundEffectsVolume = soundEffectsVolume
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
    }
}

// MARK: - 背景音乐

/// 背景音乐信息
struct BackgroundMusic: Codable, Identifiable {
    let id: UUID
    let name: String
    let fileName: String
    let category: MusicCategory
    let duration: TimeInterval
    var isLoopable: Bool

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        category: MusicCategory,
        duration: TimeInterval,
        isLoopable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.category = category
        self.duration = duration
        self.isLoopable = isLoopable
    }

    enum MusicCategory: String, Codable {
        case ambient_calm = "平和氛围"
        case suspense = "悬疑紧张"
        case action_intense = "激烈战斗"
        case romantic_soft = "浪漫温馨"
        case mystery = "神秘诡异"
        case melancholy = "悲伤忧郁"
        case celebration = "欢庆喜悦"
    }
}

// MARK: - 音效

/// 音效信息
struct SoundEffect: Codable, Identifiable {
    let id: UUID
    let name: String
    let fileName: String
    let category: EffectCategory
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        category: EffectCategory,
        duration: TimeInterval
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.category = category
        self.duration = duration
    }

    enum EffectCategory: String, Codable {
        case footsteps = "脚步声"
        case door = "门声"
        case weather = "天气"
        case weapon = "武器"
        case nature = "自然"
        case crowd = "人群"
        case magic = "魔法"
        case transition = "转场"
    }
}

// MARK: - 混合任务

/// 音频混合任务
struct AudioMixTask {
    let voiceAudio: AudioData
    let backgroundMusic: BackgroundMusic?
    let soundEffects: [SoundEffect]
    let config: AudioMixConfig
    let segment: TextSegment

    init(
        voiceAudio: AudioData,
        backgroundMusic: BackgroundMusic? = nil,
        soundEffects: [SoundEffect] = [],
        config: AudioMixConfig = AudioMixConfig(),
        segment: TextSegment
    ) {
        self.voiceAudio = voiceAudio
        self.backgroundMusic = backgroundMusic
        self.soundEffects = soundEffects
        self.config = config
        self.segment = segment
    }
}

// MARK: - 混合结果

/// 音频混合结果
struct AudioMixResult {
    let audioData: AudioData
    let duration: TimeInterval
    let voiceSegments: [VoiceSegment]

    struct VoiceSegment {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
    }
}

// MARK: - 音乐库

/// 背景音乐库
struct MusicLibrary {

    /// 预设背景音乐（实际使用时需要添加真实的音乐文件）
    static let presetMusic: [BackgroundMusic] = [
        // 平和氛围
        BackgroundMusic(
            name: "宁静时光",
            fileName: "peaceful_01.mp3",
            category: .ambient_calm,
            duration: 180
        ),
        BackgroundMusic(
            name: "田园风光",
            fileName: "peaceful_02.mp3",
            category: .ambient_calm,
            duration: 200
        ),

        // 悬疑紧张
        BackgroundMusic(
            name: "暗流涌动",
            fileName: "suspense_01.mp3",
            category: .suspense,
            duration: 150
        ),
        BackgroundMusic(
            name: "危机四伏",
            fileName: "suspense_02.mp3",
            category: .suspense,
            duration: 160
        ),

        // 激烈战斗
        BackgroundMusic(
            name: "剑拔弩张",
            fileName: "battle_01.mp3",
            category: .action_intense,
            duration: 120
        ),
        BackgroundMusic(
            name: "热血沸腾",
            fileName: "battle_02.mp3",
            category: .action_intense,
            duration: 140
        ),

        // 浪漫温馨
        BackgroundMusic(
            name: "月下私语",
            fileName: "romantic_01.mp3",
            category: .romantic_soft,
            duration: 180
        ),
        BackgroundMusic(
            name: "温柔时光",
            fileName: "romantic_02.mp3",
            category: .romantic_soft,
            duration: 190
        ),

        // 神秘诡异
        BackgroundMusic(
            name: "迷雾重重",
            fileName: "mystery_01.mp3",
            category: .mystery,
            duration: 170
        ),
        BackgroundMusic(
            name: "诡异氛围",
            fileName: "mystery_02.mp3",
            category: .mystery,
            duration: 160
        ),

        // 悲伤忧郁
        BackgroundMusic(
            name: "离别之殇",
            fileName: "sad_01.mp3",
            category: .melancholy,
            duration: 200
        ),
        BackgroundMusic(
            name: "忧伤旋律",
            fileName: "sad_02.mp3",
            category: .melancholy,
            duration: 180
        ),

        // 欢庆喜悦
        BackgroundMusic(
            name: "欢乐颂",
            fileName: "celebration_01.mp3",
            category: .celebration,
            duration: 150
        ),
        BackgroundMusic(
            name: "喜庆时刻",
            fileName: "celebration_02.mp3",
            category: .celebration,
            duration: 160
        )
    ]

    /// 根据场景类型获取音乐
    static func getMusic(for sceneType: SceneType) -> [BackgroundMusic] {
        let category: BackgroundMusic.MusicCategory

        switch sceneType {
        case .peaceful:
            category = .ambient_calm
        case .tense:
            category = .suspense
        case .battle:
            category = .action_intense
        case .romantic:
            category = .romantic_soft
        case .mysterious:
            category = .mystery
        case .sad:
            category = .melancholy
        case .festive:
            category = .celebration
        }

        return presetMusic.filter { $0.category == category }
    }

    /// 随机选择音乐
    static func randomMusic(for sceneType: SceneType) -> BackgroundMusic? {
        let musicList = getMusic(for: sceneType)
        return musicList.randomElement()
    }
}

// MARK: - 音效库

/// 音效库
struct SoundEffectLibrary {

    /// 预设音效（实际使用时需要添加真实的音效文件）
    static let presetEffects: [SoundEffect] = [
        // 脚步声
        SoundEffect(name: "脚步声-石板", fileName: "footstep_stone.mp3", category: .footsteps, duration: 1.0),
        SoundEffect(name: "脚步声-草地", fileName: "footstep_grass.mp3", category: .footsteps, duration: 1.0),

        // 门声
        SoundEffect(name: "开门", fileName: "door_open.mp3", category: .door, duration: 2.0),
        SoundEffect(name: "关门", fileName: "door_close.mp3", category: .door, duration: 1.5),

        // 天气
        SoundEffect(name: "雨声", fileName: "rain.mp3", category: .weather, duration: 5.0),
        SoundEffect(name: "雷声", fileName: "thunder.mp3", category: .weather, duration: 3.0),
        SoundEffect(name: "风声", fileName: "wind.mp3", category: .weather, duration: 4.0),

        // 武器
        SoundEffect(name: "剑击", fileName: "sword_clash.mp3", category: .weapon, duration: 1.0),
        SoundEffect(name: "拔剑", fileName: "sword_draw.mp3", category: .weapon, duration: 1.5),

        // 自然
        SoundEffect(name: "鸟鸣", fileName: "birds.mp3", category: .nature, duration: 3.0),
        SoundEffect(name: "流水", fileName: "water.mp3", category: .nature, duration: 5.0),

        // 人群
        SoundEffect(name: "人群喧哗", fileName: "crowd_noise.mp3", category: .crowd, duration: 5.0),
        SoundEffect(name: "掌声", fileName: "applause.mp3", category: .crowd, duration: 3.0),

        // 魔法
        SoundEffect(name: "魔法施放", fileName: "magic_cast.mp3", category: .magic, duration: 2.0),
        SoundEffect(name: "魔法爆炸", fileName: "magic_explosion.mp3", category: .magic, duration: 2.5),

        // 转场
        SoundEffect(name: "时间流逝", fileName: "time_pass.mp3", category: .transition, duration: 3.0),
        SoundEffect(name: "场景切换", fileName: "scene_change.mp3", category: .transition, duration: 2.0)
    ]

    /// 根据关键词匹配音效
    static func matchEffects(for text: String) -> [SoundEffect] {
        var effects: [SoundEffect] = []

        let keywords: [String: SoundEffect.EffectCategory] = [
            "走": .footsteps, "跑": .footsteps, "脚步": .footsteps,
            "门": .door, "开门": .door, "关门": .door,
            "雨": .weather, "雷": .weather, "风": .weather,
            "剑": .weapon, "刀": .weapon, "武器": .weapon,
            "鸟": .nature, "水": .nature, "河": .nature,
            "人群": .crowd, "众人": .crowd, "掌声": .crowd,
            "魔法": .magic, "法术": .magic, "咒语": .magic
        ]

        for (keyword, category) in keywords {
            if text.contains(keyword) {
                if let effect = presetEffects.first(where: { $0.category == category }) {
                    effects.append(effect)
                }
            }
        }

        return effects
    }
}
