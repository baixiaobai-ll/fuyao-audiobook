//
//  RoleIdentity.swift
//  AI有声书
//
//  角色身份归一化 - 跨 chunk 文本分析、音色绑定恢复、过期 voiceId 迁移共用同一套 key
//

import Foundation

/// 把任意原始角色名（来自 Kimi、来自历史 voiceBindings、来自 UI）归一为稳定主键，
/// 用于 voiceAssignments 字典、跨 chunk 合并、binding 匹配。
///
/// 设计原则：
/// - 只去除明确的称呼变体（"老/小/阿" 前缀、"先生/小姐/哥哥" 等后缀），不切首字，避免把
///   "林子轩 / 林子默" 误并到 "林"。
/// - 同时清洗对话引导动词残留（"笑着说"、"低声道" 等）和说话风格后缀（"轻声"、"冷冷"），
///   防止 Kimi 偶尔把 "张三笑着" 当成 speaker。
/// - 去空白 + 大小写归一化，保证 "张三 " / "张三" / "ZHANG SAN" 落到同一桶。
public enum RoleIdentity {

    /// 真正落地的归一化主键。
    /// 旁白槽（VoiceManager.narrationBindingKey）应当**走原值**，不要送进来归一化。
    public static func canonicalKey(forRawName raw: String) -> String {
        let cleaned = cleanedName(raw)
        guard !cleaned.isEmpty else { return "" }

        var candidate = cleaned
        for prefix in honorificPrefixes
        where candidate.hasPrefix(prefix) && candidate.count > prefix.count {
            candidate.removeFirst(prefix.count)
            break
        }

        let sortedSuffixes = honorificSuffixes.sorted { $0.count > $1.count }
        for suffix in sortedSuffixes
        where candidate.hasSuffix(suffix) && candidate.count > suffix.count {
            candidate.removeLast(suffix.count)
            break
        }

        let normalized = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
        return normalized.isEmpty ? cleaned.lowercased() : normalized
    }

    /// 清洗角色名（保留可读形态），比 canonicalKey 更轻：
    /// - 去除引号、括号、分隔标点
    /// - 去除引导动词（"说"/"道"/"喊道" 等）之后的尾巴
    /// - 去除风格后缀（"笑着"/"轻声"/"冷冷地"）
    public static func cleanedName(_ raw: String) -> String {
        var candidate = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "‘", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "「", with: "")
            .replacingOccurrences(of: "」", with: "")
            .replacingOccurrences(of: "『", with: "")
            .replacingOccurrences(of: "』", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")

        candidate = candidate.replacingOccurrences(
            of: "^[：:、，,。！？!？；;\\s]+|[：:、，,。！？!？；;\\s]+$",
            with: "",
            options: .regularExpression
        )

        if let splitIndex = speechVerbMarkers
            .compactMap({ marker in
                candidate.range(of: marker).flatMap { range in
                    range.lowerBound == candidate.startIndex ? nil : range.lowerBound
                }
            })
            .min() {
            candidate = String(candidate[..<splitIndex])
        }

        // Kimi 偶尔把"角色名 + 动作短语"整段塞进 speaker（如"李萍惨然一笑"、"陆鸣接过酒杯"、
        // "李博文踌躇了一下"）。这里用助词 / 动作动词起始字 / 量词起始字做兜底切除，
        // 凡是出现这些字（且不是首字）就把后面的动作部分裁掉。
        // - 仅在 candidate.count >= 3 时执行，保护 "苏笑 / 周看" 这种刚好 2 字的纯姓名。
        // - 仅切第 1 位之后的命中位置，保护 "笑笑 / 惨然" 等极个别可能首字命中的角色名。
        // 覆盖不到 100%，但能挡住绝大多数 Kimi 输出变体。
        if candidate.count >= 3,
           let cutIndex = candidate.indices.dropFirst().first(where: { idx in
               actionStopChars.contains(String(candidate[idx]))
           }) {
            candidate = String(candidate[..<cutIndex])
        }

        var trimmed = true
        while trimmed {
            trimmed = false
            for suffix in styleSuffixes {
                if candidate.hasSuffix(suffix), candidate.count > suffix.count {
                    candidate.removeLast(suffix.count)
                    trimmed = true
                    break
                }
            }
        }

        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 共享词表

    static let honorificPrefixes: [String] = ["老", "小", "阿"]

    static let honorificSuffixes: [String] = [
        "先生", "小姐", "姑娘", "夫人", "老师", "医生", "警官", "将军", "老板", "掌柜",
        "殿下", "大人", "公子", "少爷", "哥哥", "姐姐", "弟弟", "妹妹", "叔叔", "阿姨"
    ]

    static let speechVerbMarkers: [String] = [
        "笑着说", "轻声说", "低声说", "沉声说", "冷冷说道", "轻声说道", "低声说道",
        "沉声说道", "提醒道", "解释道", "吩咐道", "喃喃道", "嘀咕道", "回头说道",
        "开口说道", "回应道", "搪塞道", "又道", "便道", "正色道", "连声道", "沉声道",
        "辩解道", "抱怨道", "叹息道", "接口道", "接着道", "继续道",
        "回道", "应道", "说道", "说", "问道", "问", "答道",
        "答", "喊道", "喊", "叫道", "叫", "道"
    ]

    static let styleSuffixes: [String] = [
        "笑着", "轻声", "低声", "沉声", "冷冷地", "冷冷", "淡淡地", "淡淡",
        "认真地", "认真", "无奈地", "无奈", "平静地", "平静", "咬牙切齿地", "咬牙切齿"
    ]

    /// 出现在 speaker 字段中、可以确定**不是姓名**的字。一旦命中（且不在首位），
    /// 后续部分都视为动作描述被裁掉。
    ///
    /// **重要原则**（2026-04-26 修订）：
    /// 身体部位字（"头 / 手 / 身 / 面 / 脸 / 背 / 眼 / 腿 / 目 / 眉 / 口 / 嘴 / 胸 / 腰"）
    /// 大量出现在合法外貌代号里——例如 Kimi 给的 "鸡冠头男"、"光头壮汉"、"白面书生"、
    /// "瘸腿大叔"、"独眼老者"、"剑眉男"——一旦放进 stop chars，会把代号截成 "鸡冠"、"光"、
    /// "白"、"瘸" 这种看不懂的碎片，导致音色分配崩坏。
    ///
    /// 实际"动作短语"几乎都以动词起始字开头（"点头 / 摇头 / 抬头 / 低头 / 转身 / 捂嘴 /
    /// 闭眼 / 睁眼 / 皱眉 / 伸手"），靠下面这批 *动词起始字* 已经能可靠地切到 speaker；
    /// 把身体部位字留下来反而是收益不到 1% 但代价 99% 的反向收益。
    /// - 助词 / 结构助词："了 / 着 / 过 / 地 / 得 / 的"
    /// - 数量 / 程度起始字："一 / 两 / 几 / 半"
    /// - 高频动作动词起始字（不会出现在常见中文姓名 / 代号里）：
    ///   "笑 / 点 / 摇 / 转 / 接 / 站 / 坐 / 躺 / 跑 / 跳 / 走 / 来 / 去 / 看 / 瞥 / 望 / 瞧 / 皱 /
    ///   抬 / 低 / 扯 / 睁 / 闭 / 咬 / 张 / 伸 / 抖 / 捏 / 紧 / 握 / 抓 / 拿 / 放 / 拍 / 推 /
    ///   拉 / 抱 / 扑 / 撞 / 叹 / 停 / 想 / 念 / 默 / 嗓 / 声 / 话 / 语 / 音"
    /// - 高频形容动作起始字："惨 / 勉 / 缓 / 徐 / 悄 / 突 / 忽 / 慢 / 急 / 立 / 随 / 于 /
    ///   舒 / 屏 / 捂 / 揉 / 揣 / 撩 / 摸 / 按 / 踌"
    static let actionStopChars: Set<String> = [
        "了", "着", "过", "地", "得", "的",
        "一", "两", "几", "半",
        "笑", "点", "摇", "转", "接", "站", "坐", "躺", "跑", "跳", "走",
        "来", "去", "看", "瞥", "望", "瞧", "皱", "抬", "低", "扯",
        "睁", "闭", "咬", "张", "伸", "抖", "捏", "紧", "握", "抓",
        "拿", "放", "拍", "推", "拉", "抱", "扑", "撞", "叹", "停",
        "想", "念", "默", "嗓", "声", "话", "语", "音",
        "惨", "勉", "缓", "徐", "悄", "突", "忽", "慢", "急", "立",
        "随", "于", "舒", "屏", "捂", "揉", "揣", "撩", "摸", "按", "踌"
    ]
}
