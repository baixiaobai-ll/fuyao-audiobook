import CryptoKit
import Foundation

/// 云端可持久化的「分析索引」：不含任何正文子串，仅 UTF-8 偏移 + 结构字段。
struct PlaybackAnalysisIndex: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var bookId: String
    var chapterIndex: Int
    /// `SHA256(canonicalText.utf8)` 小写 hex，与 `NovelTextAnalyzer.canonicalTextForPlayback` 结果一致
    var textHash: String
    var characters: [Character]
    var segmentDescriptors: [SegmentDescriptor]
    var metadata: NovelMetadata

    struct SegmentDescriptor: Codable, Sendable {
        var order: Int
        var utf8Start: Int
        var utf8End: Int
        var type: SegmentType
        var emotion: Emotion
        var speakerCharacterId: UUID?
        var scene: NovelScene
    }
}

enum PlaybackAnalysisIndexError: LocalizedError {
    case hashMismatch
    case segmentNotFoundInCanonical(order: Int)
    case invalidUtf8Range(order: Int)
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .hashMismatch:
            return "正文指纹与云端索引不一致"
        case .segmentNotFoundInCanonical(let order):
            return "无法在规范化正文中定位第 \(order) 段"
        case .invalidUtf8Range(let order):
            return "第 \(order) 段 UTF-8 范围无效"
        case .unsupportedSchema(let v):
            return "不支持的索引版本: \(v)"
        }
    }
}

enum PlaybackAnalysisIndexBuilder {

    static func textHash(forCanonicalText canonical: String) -> String {
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 由本地 `AnalysisResult` 与规范化正文生成可上传索引（顺序在 `canonical` 中查找子串定位 UTF-8 范围）。
    static func makeIndex(
        bookId: String,
        chapterIndex: Int,
        canonicalText: String,
        result: AnalysisResult
    ) throws -> PlaybackAnalysisIndex {
        let textHash = textHash(forCanonicalText: canonicalText)
        let haystack = Array(canonicalText.utf8)
        var byteCursor = 0
        let sorted = result.segments.sorted { $0.order < $1.order }
        var descriptors: [PlaybackAnalysisIndex.SegmentDescriptor] = []

        for seg in sorted {
            let needle = Array(seg.text.utf8)
            let start: Int
            let end: Int
            if needle.isEmpty {
                start = byteCursor
                end = byteCursor
            } else {
                guard let found = firstIndexOfNeedle(needle, in: haystack, startingAt: byteCursor) else {
                    throw PlaybackAnalysisIndexError.segmentNotFoundInCanonical(order: seg.order)
                }
                start = found
                end = found + needle.count
                byteCursor = end
            }

            descriptors.append(
                PlaybackAnalysisIndex.SegmentDescriptor(
                    order: seg.order,
                    utf8Start: start,
                    utf8End: end,
                    type: seg.type,
                    emotion: seg.emotion,
                    speakerCharacterId: seg.speaker?.id,
                    scene: seg.scene
                )
            )
        }

        return PlaybackAnalysisIndex(
            schemaVersion: PlaybackAnalysisIndex.currentSchemaVersion,
            bookId: bookId,
            chapterIndex: chapterIndex,
            textHash: textHash,
            characters: result.characters,
            segmentDescriptors: descriptors,
            metadata: result.metadata
        )
    }

    /// 用客户端持有的规范化正文还原 `AnalysisResult`（`textHash` 必须一致）。
    static func materialize(index: PlaybackAnalysisIndex, canonicalText: String) throws -> AnalysisResult {
        guard index.schemaVersion == PlaybackAnalysisIndex.currentSchemaVersion else {
            throw PlaybackAnalysisIndexError.unsupportedSchema(index.schemaVersion)
        }
        let computed = textHash(forCanonicalText: canonicalText)
        guard computed == index.textHash else {
            throw PlaybackAnalysisIndexError.hashMismatch
        }

        let utf8Count = canonicalText.utf8.count
        var segments: [TextSegment] = []
        let sortedDesc = index.segmentDescriptors.sorted { $0.order < $1.order }

        for d in sortedDesc {
            guard d.utf8Start >= 0, d.utf8End <= utf8Count, d.utf8Start <= d.utf8End else {
                throw PlaybackAnalysisIndexError.invalidUtf8Range(order: d.order)
            }
            let slice = utf8ByteSlice(canonicalText, start: d.utf8Start, end: d.utf8End)
            guard let text = slice else {
                throw PlaybackAnalysisIndexError.invalidUtf8Range(order: d.order)
            }
            let speaker: Character?
            if let sid = d.speakerCharacterId {
                speaker = index.characters.first { $0.id == sid }
            } else {
                speaker = nil
            }
            segments.append(
                TextSegment(
                    text: text,
                    type: d.type,
                    speaker: speaker,
                    emotion: d.emotion,
                    scene: d.scene,
                    order: d.order
                )
            )
        }

        let scenes = mergedScenes(from: segments.map(\.scene))
        return AnalysisResult(
            segments: segments,
            characters: index.characters,
            scenes: scenes,
            metadata: index.metadata
        )
    }

    // MARK: - UTF-8 helpers

    private static func utf8ByteSlice(_ string: String, start: Int, end: Int) -> String? {
        guard start <= end else { return nil }
        let utf8 = string.utf8
        guard start >= 0, end <= utf8.count else { return nil }
        let iStart = utf8.index(utf8.startIndex, offsetBy: start)
        let iEnd = utf8.index(utf8.startIndex, offsetBy: end)
        guard let sPos = iStart.samePosition(in: string),
              let ePos = iEnd.samePosition(in: string) else {
            return nil
        }
        return String(string[sPos..<ePos])
    }

    private static func firstIndexOfNeedle(_ needle: [UInt8], in haystack: [UInt8], startingAt: Int) -> Int? {
        guard !needle.isEmpty else { return startingAt <= haystack.count ? startingAt : nil }
        guard startingAt <= haystack.count, needle.count <= haystack.count - startingAt else { return nil }

        outer: for i in startingAt...(haystack.count - needle.count) {
            for j in 0..<needle.count {
                if haystack[i + j] != needle[j] {
                    continue outer
                }
            }
            return i
        }
        return nil
    }

    private static func mergedScenes(from scenes: [NovelScene]) -> [NovelScene] {
        var merged: [NovelScene] = []
        var current: NovelScene?
        for s in scenes {
            if let c = current, c.type == s.type {
                let avg = (c.intensity + s.intensity) / 2
                current = NovelScene(id: c.id, type: c.type, description: c.description, intensity: avg)
            } else {
                if let c = current { merged.append(c) }
                current = s
            }
        }
        if let c = current { merged.append(c) }
        return merged
    }
}
