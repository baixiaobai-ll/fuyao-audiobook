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
    private static let removableHonorificPrefixes = ["老", "小", "阿"]
    private static let removableHonorificSuffixes = [
        "先生", "小姐", "姑娘", "夫人", "老师", "医生", "警官", "将军", "老板", "掌柜",
        "殿下", "大人", "公子", "少爷", "哥哥", "姐姐", "弟弟", "妹妹", "叔叔", "阿姨"
    ]

    private var characterVoiceMap: [UUID: Voice] = [:]
    private var availableVoices: [Voice] = []
    private var configuredNarrationVoice: Voice?

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

    /// 智能分配音色（优先恢复已有绑定，只对新角色分配，旁白槽保留不参与分配）
    func smartAssignVoices(
        for characters: [Character],
        existingBindings: [String: String] = [:]
    ) -> (assignments: [Character: Voice], newBindings: [String: String]) {
        var assignments: [Character: Voice] = [:]
        var newBindings: [String: String] = [:]
        // 旁白槽支持手动绑定，角色分配从剩余音色中选
        let narrationVoiceId = existingBindings[Self.narrationBindingKey]
            ?? VoiceLibrary.getPreferredNarrationVoice(for: availableVoices.first?.provider ?? .xfyun)?.id
        configuredNarrationVoice = narrationVoiceId.flatMap { id in
            availableVoices.first(where: { $0.id == id })
        }
        var usedVoices: Set<String> = narrationVoiceId.map { [$0] } ?? []

        for character in characters {
            // 1. 已有绑定 → 恢复
            if let voiceId = resolveExistingVoiceId(for: character.name, existingBindings: existingBindings),
               let voice = availableVoices.first(where: { $0.id == voiceId }) {
                assignments[character] = voice
                characterVoiceMap[character.id] = voice
                usedVoices.insert(voiceId)
                print("🔁 恢复角色 '\(character.name)' 音色: \(voice.name)")
                continue
            }
            // 2. 新角色 → 选未用音色
            let recommended = getRecommendedVoices(for: character.gender)
            let voice: Voice
            if let unused = recommended.first(where: { !usedVoices.contains($0.id) }) {
                voice = unused
            } else if let any = availableVoices.first(where: { !usedVoices.contains($0.id) }) {
                voice = any
            } else {
                voice = autoAssignVoice(for: character)
            }
            assignments[character] = voice
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

    private func resolveExistingVoiceId(
        for characterName: String,
        existingBindings: [String: String]
    ) -> String? {
        if let exact = existingBindings[characterName] {
            return exact
        }

        let canonical = Self.canonicalBindingKey(for: characterName)
        guard !canonical.isEmpty else { return nil }

        return existingBindings.first(where: { key, _ in
            key != Self.narrationBindingKey && Self.canonicalBindingKey(for: key) == canonical
        })?.value
    }

    private static func canonicalBindingKey(for raw: String) -> String {
        var candidate = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")

        for prefix in removableHonorificPrefixes where candidate.hasPrefix(prefix) && candidate.count > prefix.count {
            candidate.removeFirst(prefix.count)
            break
        }

        let sortedSuffixes = removableHonorificSuffixes.sorted { $0.count > $1.count }
        for suffix in sortedSuffixes where candidate.hasSuffix(suffix) && candidate.count > suffix.count {
            candidate.removeLast(suffix.count)
            break
        }

        return candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }
}
