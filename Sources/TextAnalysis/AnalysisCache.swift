//
//  AnalysisCache.swift
//  AI有声书
//
//  分析结果缓存管理
//

import Foundation

/// 分析缓存管理器
class AnalysisCache {

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    init() {
        // 获取缓存目录
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = docsURL.appendingPathComponent("AnalysisCache", isDirectory: true)

        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// 存储分析结果
    func store(_ result: AnalysisResult, key: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(result)
            try data.write(to: fileURL)
            print("💾 缓存已保存: \(key)")
        } catch {
            print("⚠️ 缓存保存失败: \(error.localizedDescription)")
        }
    }

    /// 检索分析结果
    func retrieve(key: String) -> AnalysisResult? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let result = try decoder.decode(AnalysisResult.self, from: data)
            return result
        } catch {
            print("⚠️ 缓存读取失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 清除所有缓存
    func clearAll() {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            print("🗑️ 缓存已清空")
        } catch {
            print("⚠️ 清空缓存失败: \(error.localizedDescription)")
        }
    }

    /// 清除特定缓存
    func clear(key: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        try? fileManager.removeItem(at: fileURL)
    }

    /// 获取缓存大小
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0

        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            for file in files {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
        } catch {
            print("⚠️ 获取缓存大小失败: \(error.localizedDescription)")
        }

        return totalSize
    }

    /// 格式化缓存大小
    func getFormattedCacheSize() -> String {
        let size = getCacheSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
