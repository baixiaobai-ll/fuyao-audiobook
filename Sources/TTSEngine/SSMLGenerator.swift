//
//  SSMLGenerator.swift
//  AI有声书
//
//  SSML 标记生成器
//

import Foundation

/// SSML 生成器
class SSMLGenerator {

    /// 为文本片段生成 SSML
    /// - Parameters:
    ///   - segment: 文本片段
    ///   - voice: 音色
    /// - Returns: SSML 字符串
    func generate(segment: TextSegment, voice: Voice) -> String {
        let emotion = segment.emotion
        let prosody = emotion.prosodyAdjustment

        var ssml = "<speak>"

        // 添加音色标签（如果支持）
        if voice.provider == .azure {
            ssml += "<voice name=\"\(voice.id)\">"
        }

        // 根据片段类型添加不同的处理
        switch segment.type {
        case .dialogue:
            ssml += generateDialogueSSML(segment: segment, prosody: prosody)
        case .narration:
            ssml += generateNarrationSSML(segment: segment, prosody: prosody)
        case .description:
            ssml += generateDescriptionSSML(segment: segment, prosody: prosody)
        case .thought:
            ssml += generateThoughtSSML(segment: segment, prosody: prosody)
        }

        if voice.provider == .azure {
            ssml += "</voice>"
        }

        ssml += "</speak>"

        return ssml
    }

    // MARK: - Private Methods

    /// 生成对话 SSML
    private func generateDialogueSSML(segment: TextSegment, prosody: ProsodyAdjustment) -> String {
        var ssml = ""

        // 对话前的停顿
        ssml += "<break time=\"300ms\"/>"

        // 添加韵律标签
        ssml += "<prosody rate=\"\(formatRate(prosody.rate))\" pitch=\"\(formatPitch(prosody.pitch))\" volume=\"\(formatVolume(prosody.volume))\">"

        // 根据情感添加表达风格（Azure 支持）
        if let style = getExpressStyle(for: segment.emotion) {
            ssml += "<mstts:express-as style=\"\(style)\">"
            ssml += escapeXML(segment.text)
            ssml += "</mstts:express-as>"
        } else {
            ssml += escapeXML(segment.text)
        }

        ssml += "</prosody>"

        // 对话后的停顿
        ssml += "<break time=\"400ms\"/>"

        return ssml
    }

    /// 生成旁白 SSML
    private func generateNarrationSSML(segment: TextSegment, prosody: ProsodyAdjustment) -> String {
        var ssml = ""

        // 旁白使用较平稳的语速
        let adjustedRate = prosody.rate * 0.95

        ssml += "<prosody rate=\"\(formatRate(adjustedRate))\" pitch=\"\(formatPitch(prosody.pitch))\" volume=\"\(formatVolume(prosody.volume))\">"

        // 添加自然的停顿
        let textWithBreaks = addNaturalBreaks(segment.text)
        ssml += escapeXML(textWithBreaks)

        ssml += "</prosody>"

        // 段落后停顿
        ssml += "<break time=\"500ms\"/>"

        return ssml
    }

    /// 生成描述 SSML
    private func generateDescriptionSSML(segment: TextSegment, prosody: ProsodyAdjustment) -> String {
        var ssml = ""

        // 描述使用较慢的语速，增强画面感
        let adjustedRate = prosody.rate * 0.9

        ssml += "<prosody rate=\"\(formatRate(adjustedRate))\" pitch=\"\(formatPitch(prosody.pitch))\" volume=\"\(formatVolume(prosody.volume))\">"

        let textWithBreaks = addNaturalBreaks(segment.text)
        ssml += escapeXML(textWithBreaks)

        ssml += "</prosody>"

        ssml += "<break time=\"600ms\"/>"

        return ssml
    }

    /// 生成内心独白 SSML
    private func generateThoughtSSML(segment: TextSegment, prosody: ProsodyAdjustment) -> String {
        var ssml = ""

        // 内心独白音量稍低，语速稍慢
        let adjustedVolume = prosody.volume * 0.9
        let adjustedRate = prosody.rate * 0.95

        ssml += "<break time=\"400ms\"/>"

        ssml += "<prosody rate=\"\(formatRate(adjustedRate))\" pitch=\"\(formatPitch(prosody.pitch))\" volume=\"\(formatVolume(adjustedVolume))\">"

        // Azure 支持 whisper 风格
        ssml += "<mstts:express-as style=\"gentle\">"
        ssml += escapeXML(segment.text)
        ssml += "</mstts:express-as>"

        ssml += "</prosody>"

        ssml += "<break time=\"500ms\"/>"

        return ssml
    }

    /// 添加自然停顿
    private func addNaturalBreaks(_ text: String) -> String {
        var result = text

        // 在标点符号后添加停顿
        let punctuationBreaks: [(String, String)] = [
            ("。", "。<break time=\"400ms\"/>"),
            ("！", "！<break time=\"400ms\"/>"),
            ("？", "？<break time=\"400ms\"/>"),
            ("，", "，<break time=\"200ms\"/>"),
            ("；", "；<break time=\"300ms\"/>"),
            ("：", "：<break time=\"250ms\"/>"),
            ("、", "、<break time=\"150ms\"/>")
        ]

        for (punctuation, replacement) in punctuationBreaks {
            result = result.replacingOccurrences(of: punctuation, with: replacement)
        }

        return result
    }

    /// 获取表达风格
    private func getExpressStyle(for emotion: Emotion) -> String? {
        // Azure Neural Voice 支持的表达风格
        switch emotion {
        case .happy:
            return "cheerful"
        case .sad:
            return "sad"
        case .angry:
            return "angry"
        case .excited:
            return "excited"
        case .fearful:
            return "fearful"
        case .tender:
            return "gentle"
        case .neutral, .surprised:
            return nil
        }
    }

    /// 格式化语速
    private func formatRate(_ rate: Double) -> String {
        let percentage = Int(rate * 100)
        return "\(percentage)%"
    }

    /// 格式化音调
    private func formatPitch(_ pitch: Double) -> String {
        let percentage = Int((pitch - 1.0) * 100)
        if percentage >= 0 {
            return "+\(percentage)%"
        } else {
            return "\(percentage)%"
        }
    }

    /// 格式化音量
    private func formatVolume(_ volume: Double) -> String {
        let percentage = Int(volume * 100)
        return "\(percentage)%"
    }

    /// 转义 XML 特殊字符
    private func escapeXML(_ text: String) -> String {
        var escaped = text
        let replacements: [(String, String)] = [
            ("&", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&apos;")
        ]

        for (char, entity) in replacements {
            escaped = escaped.replacingOccurrences(of: char, with: entity)
        }

        return escaped
    }
}

// MARK: - SSML 工具扩展

extension SSMLGenerator {

    /// 生成简单的 SSML（不带情感和韵律）
    func generateSimple(text: String, voice: Voice) -> String {
        var ssml = "<speak>"

        if voice.provider == .azure {
            ssml += "<voice name=\"\(voice.id)\">"
        }

        ssml += escapeXML(text)

        if voice.provider == .azure {
            ssml += "</voice>"
        }

        ssml += "</speak>"

        return ssml
    }

    /// 验证 SSML 格式
    func validate(ssml: String) -> Bool {
        // 简单验证：检查标签是否匹配
        let openTags = ssml.components(separatedBy: "<").count - 1
        let closeTags = ssml.components(separatedBy: ">").count - 1

        return openTags == closeTags && ssml.contains("<speak>") && ssml.contains("</speak>")
    }

    /// 从 SSML 中提取纯文本
    func extractText(from ssml: String) -> String {
        var text = ssml

        // 移除所有 XML 标签
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // 还原转义字符
        let unescapeReplacements: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'")
        ]

        for (entity, char) in unescapeReplacements {
            text = text.replacingOccurrences(of: entity, with: char)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
