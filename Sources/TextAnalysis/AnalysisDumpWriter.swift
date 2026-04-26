//
//  AnalysisDumpWriter.swift
//  AI有声书
//
//  把每次小说分析的原始记录（chunk 输入、Kimi prompt、Kimi 原始返回、解析结果）
//  落盘到 Documents/KimiAnalysisDump/run_<timestamp>/，便于排查"旁白被错认"
//  "speaker 给错"等纯靠日志看不清楚的问题。
//
//  落盘文件命名：
//    chunk_<index>_input.txt           原始 chunk 文本
//    chunk_<index>_prompt.txt          发给 Kimi 的完整 prompt
//    chunk_<index>_raw_response.json   Kimi 返回的原始字符串（多次重试时保留最后一次）
//    chunk_<index>_parsed.txt          解析后的 segments + characters 表格视图
//    chunk_<index>_error.txt           解析失败时记录错误诊断（仅失败路径生成）
//    run_summary.txt                   整次 run 的汇总（chunks/角色/段数）
//
//  在并发分析多个 chunk 时是线程安全的（写盘前内部加串行队列）。
//

import Foundation

/// 把单次分析 run 的中间产物（输入 / prompt / 原始返回 / 解析结果）落盘的工具。
final class AnalysisDumpWriter: @unchecked Sendable {

    /// 本次 run 的根目录（Documents/KimiAnalysisDump/run_<stamp>/）。
    let runDirectory: URL

    private let queue = DispatchQueue(label: "com.fuyao.analysis-dump", qos: .utility)
    private let runStamp: String
    private let startedAt: Date

    /// 创建一个 dump writer。失败（沙盒受限或目录创建异常）时返回 nil，调用方按"无落盘"路径继续工作。
    init?(provider: String, runID: String? = nil) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = runID ?? formatter.string(from: Date())
        let runDir = docs
            .appendingPathComponent("KimiAnalysisDump", isDirectory: true)
            .appendingPathComponent("run_\(provider)_\(stamp)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("⚠️ 创建分析 dump 目录失败：\(error.localizedDescription)")
            return nil
        }
        self.runDirectory = runDir
        self.runStamp = stamp
        self.startedAt = Date()
        print("📝 本次分析原始记录落盘目录：\(runDir.path)")
    }

    /// 落盘 chunk 输入文本。
    func writeChunkInput(index: Int, text: String) {
        write(filename: "chunk_\(formattedIndex(index))_input.txt", contents: text)
    }

    /// 落盘 chunk 的 prompt。
    func writeChunkPrompt(index: Int, prompt: String) {
        write(filename: "chunk_\(formattedIndex(index))_prompt.txt", contents: prompt)
    }

    /// 落盘 Kimi 返回的原始字符串。多次重试时调用方传 attempt 号区分。
    func writeChunkRawResponse(index: Int, attempt: Int, response: String) {
        let suffix = attempt <= 1 ? "" : "_attempt\(attempt)"
        write(filename: "chunk_\(formattedIndex(index))_raw_response\(suffix).json", contents: response)
    }

    /// 落盘 chunk 解析后的结果（人眼可读的 segment 表格）。
    func writeChunkParsed(index: Int, parsedDescription: String) {
        write(filename: "chunk_\(formattedIndex(index))_parsed.txt", contents: parsedDescription)
    }

    /// 落盘 chunk 解析失败的诊断。
    func writeChunkError(index: Int, message: String) {
        write(filename: "chunk_\(formattedIndex(index))_error.txt", contents: message)
    }

    /// 落盘整次 run 的汇总信息（chunk 数、segment 数、角色数、耗时等）。
    func writeRunSummary(_ text: String) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let header = """
        # Analysis Run Summary
        - 开始时间: \(runStamp)
        - 落盘目录: \(runDirectory.path)
        - 总耗时: \(String(format: "%.2f", elapsed))s

        """
        write(filename: "run_summary.txt", contents: header + text)
    }

    // MARK: - Private

    private func formattedIndex(_ index: Int) -> String {
        String(format: "%03d", index)
    }

    private func write(filename: String, contents: String) {
        let url = runDirectory.appendingPathComponent(filename)
        queue.async {
            do {
                try contents.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("⚠️ 写入分析 dump 文件失败 [\(filename)]：\(error.localizedDescription)")
            }
        }
    }
}
