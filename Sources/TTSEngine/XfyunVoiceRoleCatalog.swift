//
//  XfyunVoiceRoleCatalog.swift
//  AI有声书
//
//  讯飞超拟人白名单里每个音色的**业务侧角色适配**（与 API 的 vcn 无关）。
//  `VoiceManager.smartAssignVoices` 在 provider=.xfyun 时，优先用 Kimi 的 `Character.voiceArchetype`
//  映射到 `XfyunCharacterVoiceNeed`；缺省时再退回 `gender` + 角色名粗启发式，再对各候选音色算分，
//  在「未占用」集合里取最高分，实现「老人像老人、孩童像孩童」，而不是仅靠 `Voice.gender` 过滤。
//

import Foundation

// MARK: - 角色侧「需求向量」

/// 一次分配时希望音色去贴近的听感维度（由 `Character` 推断，不是讯飞 API 字段）。
enum XfyunCharacterVoiceNeed: Hashable, Sendable {
    /// 老年男性：长辈、老者、掌门、族长、说书感叙事 NPC 等
    case elderMale
    /// 老年女性：老妇、婆婆、嬷嬷等（由角色名关键字粗判）
    case elderFemale
    /// 男童、小厮、店小二、年轻男配、音色偏轻的男角
    case boyYoungMaleSupport
    /// 女童、少女、年轻女配
    case girlYoungFemale
    /// 男频「第一男主 / 视点小生」等——强优先**聆飞逸**，**不要**和「稳健叙事男」配角抢 聆伯松 顺位。
    case primeAdultMaleLead
    /// 成年男性配角 / 常规将军反派 / 沉稳男二（**不是**整书视点主角时由 Kimi 标 `secondary`）
    case primeAdultMale
    /// 成年女主、温柔女性、贵妇、师姐等
    case primeAdultFemale
    /// 性别信息不足时的中性兜底（尽量用不偏科太狠的声线）
    case neutralAndrogynousNarratorish
}

// MARK: - 讯飞白名单适配表

enum XfyunVoiceRoleCatalog {

    /// 供 `VoiceManager` 使用：综合 `narrativeRole` + `voiceArchetype` + `gender`。
    static func resolvedNeed(for character: Character) -> XfyunCharacterVoiceNeed {
        if let tag = character.voiceArchetype {
            let base = tag.xfyunCharacterVoiceNeed
            if shouldUseMaleLeadVector(character: character, baseNeed: base) {
                return .primeAdultMaleLead
            }
            return base
        }
        let inferred = inferredNeed(for: character)
        if shouldUseMaleLeadVector(character: character, baseNeed: inferred) {
            return .primeAdultMaleLead
        }
        return inferred
    }

    /// 本书视点男主（`narrativeRole=primary`）且是成年向男声需求 → 走「聆飞逸」主舞台向量。
    private static func shouldUseMaleLeadVector(character: Character, baseNeed: XfyunCharacterVoiceNeed) -> Bool {
        character.narrativeRole == .primary
            && character.gender == .male
            && baseNeed == .primeAdultMale
    }

    /// 从分析结果里的角色，在**没有** `voiceArchetype` 时，由 `gender` + 角色名推断听感需求。
    static func inferredNeed(for character: Character) -> XfyunCharacterVoiceNeed {
        switch character.gender {
        case .elder:
            return isLikelyFemaleElder(name: character.name) ? .elderFemale : .elderMale
        case .child:
            return inferChildNeed(name: character.name)
        case .male:
            return .primeAdultMale
        case .female:
            return .primeAdultFemale
        case .neutral:
            return .neutralAndrogynousNarratorish
        }
    }

    /// 对单条讯飞 `voiceId` 在给定需求下的适配分。越高越适合；同分由 `VoiceLibrary.xfyunVoices` 顺序打破平局。
    static func compatibilityScore(voiceId: String, need: XfyunCharacterVoiceNeed) -> Int {
        switch voiceId {
        case "x6_lingbosong_pro":
            // 聆伯松：稳健男声、故事感 —— 男配、长辈/老者；**不要**在「成年男主位」上压过 聆飞逸。
            switch need {
            case .elderMale: return 100
            case .primeAdultMale: return 100
            case .primeAdultMaleLead: return 52
            case .neutralAndrogynousNarratorish: return 62
            case .boyYoungMaleSupport: return 28
            case .elderFemale: return 10
            case .girlYoungFemale: return 6
            case .primeAdultFemale: return 5
            }

        case "x6_xiaonaigoudidi_mini":
            // 小奶狗弟弟：年轻偏轻 —— 男童、小厮、店小二、少年感男配；**不适合**作为第一顺位老年音。
            switch need {
            case .boyYoungMaleSupport: return 100
            case .girlYoungFemale: return 18
            case .primeAdultMale: return 50
            case .primeAdultMaleLead: return 22
            case .neutralAndrogynousNarratorish: return 30
            case .primeAdultFemale: return 8
            case .elderMale: return 4
            case .elderFemale: return 4
            }

        case "x6_lingfeiyi_pro":
            // 聆飞逸：沉稳成年男 —— **整书男主首选**；配角成年男在 `primeAdultMale` 里故意低于 伯松/奶狗 顺位，减少抢麦。
            switch need {
            case .primeAdultMaleLead: return 100
            case .primeAdultMale: return 70
            case .elderMale: return 62
            case .boyYoungMaleSupport: return 48
            case .neutralAndrogynousNarratorish: return 52
            case .elderFemale: return 12
            case .girlYoungFemale: return 6
            case .primeAdultFemale: return 6
            }

        case "x6_gufengpangbai_pro":
            // 古风旁白：叙事 / 史传感 —— 默认旁白槽会占用；若意外进入角色池，适合中性叙述 NPC，**不宜**优先派给少女或男童。
            switch need {
            case .neutralAndrogynousNarratorish: return 58
            case .elderMale: return 44
            case .primeAdultMale: return 36
            case .primeAdultMaleLead: return 28
            case .boyYoungMaleSupport: return 14
            case .elderFemale: return 22
            case .primeAdultFemale: return 18
            case .girlYoungFemale: return 12
            }

        case "x6_lingxiaoxuan_pro":
            // 聆小璇：温柔女声 —— 女主、温柔女配；也可作老年女声兜底之一。
            switch need {
            case .primeAdultFemale: return 94
            case .elderFemale: return 88
            case .girlYoungFemale: return 58
            case .neutralAndrogynousNarratorish: return 38
            case .primeAdultMaleLead, .primeAdultMale, .elderMale, .boyYoungMaleSupport: return 8
            }

        case "x5_lingyuzhao_flow":
            // 灵玉昭：流式女声、知性 —— 成熟女配、女长老感、师姐类。
            switch need {
            case .primeAdultFemale: return 82
            case .elderFemale: return 80
            case .girlYoungFemale: return 52
            case .neutralAndrogynousNarratorish: return 36
            case .primeAdultMaleLead, .primeAdultMale, .elderMale, .boyYoungMaleSupport: return 10
            }

        case "x6_lingxiaoyue_pro":
            // 聆小玥：清亮年轻女 —— 少女、年轻女配首选。
            switch need {
            case .girlYoungFemale: return 98
            case .primeAdultFemale: return 64
            case .elderFemale: return 28
            case .neutralAndrogynousNarratorish: return 32
            case .primeAdultMaleLead, .primeAdultMale, .elderMale, .boyYoungMaleSupport: return 8
            }

        case "x6_lingyuyan_pro":
            // 聆玉言：知性女 —— 女主 / 女谋士；默认会占「未命名对话」槽，进入角色池时分数略低于聆小璇以免抢女主位。
            switch need {
            case .primeAdultFemale: return 84
            case .elderFemale: return 72
            case .girlYoungFemale: return 56
            case .neutralAndrogynousNarratorish: return 40
            case .primeAdultMaleLead, .primeAdultMale, .elderMale, .boyYoungMaleSupport: return 8
            }

        default:
            return 25
        }
    }

    // MARK: - Private

    private static func inferChildNeed(name: String) -> XfyunCharacterVoiceNeed {
        if isLikelyGirlChild(name: name) { return .girlYoungFemale }
        return .boyYoungMaleSupport
    }

    private static func isLikelyGirlChild(name: String) -> Bool {
        let n = name
        let hints = ["女童", "童女", "丫头", "丫鬟", "小姐", "姑娘", "姐", "妹", "妞", "囡", "女娃", "婢女"]
        return hints.contains { n.contains($0) }
    }

    private static func isLikelyFemaleElder(name: String) -> Bool {
        let n = name
        let hints = ["老妇", "婆婆", "老太", "嬷嬷", "太妃", "太后", "太君", "夫人", "婶", "婆", "祖母", "奶奶", "老娘"]
        return hints.contains { n.contains($0) }
    }
}

extension VoiceArchetypeTag {
    /// Kimi 标签 → 与 `inferredNeed` 同一套打分向量，保证「标签路径」与「兜底路径」可比较。
    fileprivate var xfyunCharacterVoiceNeed: XfyunCharacterVoiceNeed {
        switch self {
        case .elderMale: return .elderMale
        case .elderFemale: return .elderFemale
        case .boyOrYoungMale: return .boyYoungMaleSupport
        case .girlOrYoungFemale: return .girlYoungFemale
        case .adultMale: return .primeAdultMale
        case .adultFemale: return .primeAdultFemale
        case .neutral: return .neutralAndrogynousNarratorish
        }
    }
}
