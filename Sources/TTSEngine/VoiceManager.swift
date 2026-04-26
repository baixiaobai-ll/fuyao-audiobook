//
//  VoiceManager.swift
//  AI有声书
//
//  音色管理器 - 为角色分配和管理音色
//

import Foundation

/// 音色管理器
class VoiceManager {
    static let narrationBindingKey = "__narration__"

    private var characterVoiceMap: [UUID: Voice] = [:]
    private var availableVoices: [Voice] = []
    private var configuredNarrationVoice: Voice?
    /// 给 `type=dialogue` 但 `speaker=nil` 的"未命名对话"段落使用的专属音色槽。
    /// 在 smartAssignVoices 时确定，跟具体角色不会撞车。
    private var configuredUnknownDialogueVoice: Voice?

    init() {
        // 加载可用音色
        loadAvailableVoices()
    }

    /// 为角色分配音色
    /// - Parameter character: 角色
    /// - Returns: 分配的音色
    func assignVoice(for character: Character) -> Voice {
        // 如果已经分配过，直接返回
        if let existingVoice = characterVoiceMap[character.id] {
            return existingVoice
        }

        // 如果角色已指定音色 ID
        if let voiceId = character.voiceId,
           let voice = availableVoices.first(where: { $0.id == voiceId }) {
            characterVoiceMap[character.id] = voice
            return voice
        }

        // 根据角色性别自动分配
        let voice = autoAssignVoice(for: character)
        characterVoiceMap[character.id] = voice

        print("🎭 为角色 '\(character.name)' 分配音色: \(voice.name)")

        return voice
    }

    /// 手动设置角色音色
    /// - Parameters:
    ///   - character: 角色
    ///   - voice: 音色
    func setVoice(for character: Character, voice: Voice) {
        characterVoiceMap[character.id] = voice
        print("🎭 角色 '\(character.name)' 音色已更新为: \(voice.name)")
    }

    /// 获取角色的音色
    /// - Parameter character: 角色
    /// - Returns: 音色（如果已分配）
    func getVoice(for character: Character) -> Voice? {
        return characterVoiceMap[character.id]
    }

    /// 获取旁白音色（优先使用配置的旁白，其次回退到默认旁白）
    func getNarrationVoice() -> Voice {
        if let configuredNarrationVoice {
            return configuredNarrationVoice
        }
        return VoiceLibrary.getPreferredNarrationVoice(for: availableVoices.first?.provider ?? .xfyun)
            ?? availableVoices.first!
    }

    /// 获取"未命名对话"音色：给 Kimi 标记为 `type=dialogue` 但 `speaker=nil` 的段落用。
    ///
    /// 这条路径必须**与旁白音色区分开**——之前 buildPlaybackItem 把这类段落
    /// 直接 fallback 到旁白音色，导致用户听感上"对话被当成旁白读"。
    /// smartAssignVoices 会把这个槽加进 usedVoices，所以不会跟具体角色撞车。
    /// 实在拿不到（极少数：当前 provider 没有对应预设、availableVoices 为空），退回到旁白音色。
    func getUnknownDialogueVoice() -> Voice {
        if let configuredUnknownDialogueVoice {
            return configuredUnknownDialogueVoice
        }
        let provider = availableVoices.first?.provider ?? .xfyun
        if let preset = VoiceLibrary.getPreferredUnknownDialogueVoice(for: provider) {
            return preset
        }
        return getNarrationVoice()
    }

    /// 清除所有音色分配
    func clearAllAssignments() {
        characterVoiceMap.removeAll()
        print("🗑️ 已清除所有音色分配")
    }

    /// 获取所有可用音色
    func getAvailableVoices() -> [Voice] {
        return availableVoices
    }

    /// 根据性别获取推荐音色
    /// - Parameter gender: 性别
    /// - Returns: 推荐的音色列表
    func getRecommendedVoices(for gender: Character.Gender) -> [Voice] {
        let voiceGender: Voice.VoiceGender
        switch gender {
        case .male:
            voiceGender = .male
        case .female:
            voiceGender = .female
        case .neutral:
            voiceGender = .neutral
        case .child:
            voiceGender = .child
        case .elder:
            voiceGender = .elder
        }

        return availableVoices.filter { $0.gender == voiceGender }
    }

    /// 按 TTS provider 加载对应音色（供生成器调用）
    func loadAvailableVoices(for provider: TTSProvider) {
        switch provider {
        case .xfyun:  availableVoices = VoiceLibrary.xfyunVoices
        case .azure:  availableVoices = VoiceLibrary.azureVoices
        case .openai: availableVoices = VoiceLibrary.openAIVoices
        default:      availableVoices = VoiceLibrary.xfyunVoices
        }
        configuredNarrationVoice = nil
        configuredUnknownDialogueVoice = nil
    }

    // MARK: - Private Methods

    /// 加载可用音色（默认使用讯飞）
    private func loadAvailableVoices() {
        loadAvailableVoices(for: .xfyun)
    }

    /// 自动分配音色
    private func autoAssignVoice(for character: Character) -> Voice {
        let voiceGender: Voice.VoiceGender
        switch character.gender {
        case .male:
            voiceGender = .male
        case .female:
            voiceGender = .female
        case .neutral:
            voiceGender = .neutral
        case .child:
            voiceGender = .child
        case .elder:
            voiceGender = .elder
        }

        // 获取该性别的默认音色
        if let defaultVoice = VoiceLibrary.getDefaultVoice(for: voiceGender) {
            return defaultVoice
        }

        // 如果没有找到，使用第一个匹配的音色
        if let matchingVoice = availableVoices.first(where: { $0.gender == voiceGender }) {
            return matchingVoice
        }

        // 最后的降级方案
        return availableVoices.first!
    }

    /// 智能分配音色（优先恢复已有绑定，只对新角色分配，旁白槽保留不参与分配）。
    ///
    /// - returns:
    ///   - `assignments`: key 为 `RoleIdentity.canonicalKey`，给生成器按 canonicalKey 直接查表，
    ///     避免再依赖 Character.id（UUID 跨 chunk 不稳定）。
    ///   - `newBindings`: key 仍是 raw character name，写回 Book.voiceBindings 时保留可读形态。
    func smartAssignVoices(
        for characters: [Character],
        existingBindings: [String: String] = [:]
    ) -> (assignments: [String: Voice], newBindings: [String: String]) {
        var assignments: [String: Voice] = [:]
        var newBindings: [String: String] = [:]
        // 旁白槽支持手动绑定，角色分配从剩余音色中选。
        // 历史 `existingBindings` 里旁白槽可能是旧默认 `x6_lingfeiyi_pro`（系统当时自动写入），
        // 主控已决定把所有小说的默认旁白改为 `x6_gufengpangbai_pro`，这里把"未被白名单接受"
        // 或"等于旧默认"的情况一并视为缺省，统一从 `getPreferredNarrationVoice` 取新默认。
        let provider = availableVoices.first?.provider ?? .xfyun
        let preferredNarrationId = VoiceLibrary.getPreferredNarrationVoice(for: provider)?.id
        let rawNarrationVoiceId = existingBindings[Self.narrationBindingKey]
        let narrationVoiceId: String?
        if let raw = rawNarrationVoiceId,
           availableVoices.contains(where: { $0.id == raw }),
           raw != "x6_lingfeiyi_pro" {
            narrationVoiceId = raw
        } else {
            narrationVoiceId = preferredNarrationId
        }
        configuredNarrationVoice = narrationVoiceId.flatMap { id in
            availableVoices.first(where: { $0.id == id })
        }

        // "未命名对话"槽：跟旁白同样在分配前固定下来，加进 usedVoices 防止被分给具体角色。
        // 找不到预设（罕见）就退回到 nil，运行时 getUnknownDialogueVoice 会自动 fallback 到旁白。
        let preferredUnknownDialogueId = VoiceLibrary.getPreferredUnknownDialogueVoice(for: provider)?.id
        configuredUnknownDialogueVoice = preferredUnknownDialogueId.flatMap { id in
            availableVoices.first(where: { $0.id == id })
        }

        var usedVoices: Set<String> = narrationVoiceId.map { [$0] } ?? []
        if let unknownDialogueId = preferredUnknownDialogueId,
           availableVoices.contains(where: { $0.id == unknownDialogueId }) {
            usedVoices.insert(unknownDialogueId)
        }

        /// 先给 `primary` 选音色，避免多个 `adult_male` 时配角先占「聆飞逸」。
        let charactersOrdered = characters.sorted { a, b in
            let ra = Self.narrativeRoleSortRank(a)
            let rb = Self.narrativeRoleSortRank(b)
            if ra != rb { return ra < rb }
            return a.name < b.name
        }

        for character in charactersOrdered {
            let canonical = RoleIdentity.canonicalKey(forRawName: character.name)
            let assignmentKey = canonical.isEmpty ? character.name.lowercased() : canonical

            // 同一 canonicalKey 已经分配过（输入数组里有重名漏 dedup），直接复用
            if let already = assignments[assignmentKey] {
                characterVoiceMap[character.id] = already
                continue
            }

            // 1. 已有绑定 → 恢复
            if let voiceId = resolveExistingVoiceId(for: character.name, existingBindings: existingBindings),
               let voice = availableVoices.first(where: { $0.id == voiceId }) {
                assignments[assignmentKey] = voice
                characterVoiceMap[character.id] = voice
                usedVoices.insert(voiceId)
                print("🔁 恢复角色 '\(character.name)' 音色: \(voice.name)")
                continue
            }
            // 2. 新角色 → 选未用音色
            // 讯飞：用 `XfyunVoiceRoleCatalog` 按「角色听感需求」打分，而不是仅靠 `Voice.gender` 过滤
            // （白名单里根本没有 elder/child 标签音色，必须靠业务表把老人/孩童对齐到合适男声女声）。
            let voice: Voice
            if provider == .xfyun {
                voice = pickBestXfyunSuperVoice(for: character, usedVoices: usedVoices)
            } else {
                let recommended = getRecommendedVoices(for: character.gender)
                if let unused = recommended.first(where: { !usedVoices.contains($0.id) }) {
                    voice = unused
                } else if let fallback = elderChildAwareFallbackVoice(for: character.gender, usedVoices: usedVoices) {
                    voice = fallback
                } else if let any = availableVoices.first(where: { !usedVoices.contains($0.id) }) {
                    voice = any
                } else {
                    voice = autoAssignVoice(for: character)
                }
            }
            assignments[assignmentKey] = voice
            characterVoiceMap[character.id] = voice
            usedVoices.insert(voice.id)
            newBindings[character.name] = voice.id
            print("🎭 新分配角色 '\(character.name)' 音色: \(voice.name)")
        }

        print("🎭 已为 \(characters.count) 个角色分配音色（\(newBindings.count) 个新增）")
        return (assignments, newBindings)
    }

    /// 导出音色配置
    func exportConfiguration() -> [String: String] {
        var config: [String: String] = [:]
        for (characterId, voice) in characterVoiceMap {
            config[characterId.uuidString] = voice.id
        }
        return config
    }

    /// 导入音色配置
    func importConfiguration(_ config: [String: String]) {
        characterVoiceMap.removeAll()

        for (characterIdString, voiceId) in config {
            guard let characterId = UUID(uuidString: characterIdString),
                  let voice = availableVoices.first(where: { $0.id == voiceId }) else {
                continue
            }
            characterVoiceMap[characterId] = voice
        }

        print("📥 已导入 \(characterVoiceMap.count) 个音色配置")
    }

    /// 在讯飞白名单内，为角色选**适配分最高**且未被占用的音色。
    private func pickBestXfyunSuperVoice(for character: Character, usedVoices: Set<String>) -> Voice {
        let need = XfyunVoiceRoleCatalog.resolvedNeed(for: character)
        let candidates = availableVoices.filter { $0.provider == .xfyun && !usedVoices.contains($0.id) }
        guard !candidates.isEmpty else {
            return autoAssignVoice(for: character)
        }
        let best = candidates.max { a, b in
            let sa = XfyunVoiceRoleCatalog.compatibilityScore(voiceId: a.id, need: need)
            let sb = XfyunVoiceRoleCatalog.compatibilityScore(voiceId: b.id, need: need)
            if sa != sb { return sa < sb }
            return xfyunVoiceOrderingIndex(a.id) > xfyunVoiceOrderingIndex(b.id)
        }
        return best ?? candidates[0]
    }

    /// `VoiceLibrary.xfyunVoices` 中的下标，仅用于同分打破平局（越小越优先）。
    private func xfyunVoiceOrderingIndex(_ voiceId: String) -> Int {
        VoiceLibrary.xfyunVoices.firstIndex(where: { $0.id == voiceId }) ?? Int.max
    }

    private static func narrativeRoleSortRank(_ character: Character) -> Int {
        switch character.narrativeRole {
        case .some(.primary): return 0
        case .some(.secondary): return 1
        case .none: return 1
        case .some(.tertiary): return 2
        }
    }

    /// Bug E 兜底：给 elder / child 角色找最合适的"未用"音色。
    ///
    /// 当前讯飞白名单里**没有任何音色**标 `gender = elder` 或 `gender = child`（小奶狗弟弟也是 male），
    /// 因此 `getRecommendedVoices(for: .elder)` / `(for: .child)` 都会返回空数组。如果继续走
    /// `availableVoices.first(where: !used)` 兜底，按白名单数组顺序第一个未用的常常是女声，
    /// 出现"60 岁老者用聆小璇女声"这种违和。这里改用以下顺序：
    ///   1. `VoiceLibrary.getDefaultVoice(for: gender)`（elder → 聆伯松，child → 小奶狗弟弟）
    ///   2. 该角色性别对应的 male voices（elder/child 在 99% 中文小说里指男性）
    ///   3. 全部失败 → 返回 nil，由调用方走原 `availableVoices.first(where: !used)` 兜底
    /// 对于 `male / female / neutral`，这个兜底直接返回 nil（让原有逻辑处理）。
    private func elderChildAwareFallbackVoice(
        for gender: Character.Gender,
        usedVoices: Set<String>
    ) -> Voice? {
        guard gender == .elder || gender == .child else { return nil }

        let provider = availableVoices.first?.provider ?? .xfyun
        let voiceGender: Voice.VoiceGender = (gender == .elder) ? .elder : .child
        if let preset = VoiceLibrary.getDefaultVoice(for: voiceGender, provider: provider),
           availableVoices.contains(where: { $0.id == preset.id }),
           !usedVoices.contains(preset.id) {
            return preset
        }

        if let maleFallback = availableVoices.first(where: {
            $0.gender == .male && !usedVoices.contains($0.id)
        }) {
            return maleFallback
        }

        return nil
    }

    private func resolveExistingVoiceId(
        for characterName: String,
        existingBindings: [String: String]
    ) -> String? {
        if let exact = existingBindings[characterName] {
            return exact
        }

        let canonical = RoleIdentity.canonicalKey(forRawName: characterName)
        guard !canonical.isEmpty else { return nil }

        return existingBindings.first(where: { key, _ in
            key != Self.narrationBindingKey
                && RoleIdentity.canonicalKey(forRawName: key) == canonical
        })?.value
    }
}
