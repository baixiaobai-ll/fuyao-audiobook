//
//  TTSCache.swift
//  AI有声书
//
//  TTS 音频缓存管理
//

import Foundation

/// TTS 缓存管理器
class TTSCache {

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024  // 500 MB

    init() {
        // 获取缓存目录
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = docsURL.appendingPathComponent("TTSCache", isDirectory: true)

        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // 启动时清理过期缓存
        cleanupExpiredCache()
    }

    /// 存储音频数据
    func store(_ audioData: AudioData, key: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).\(audioData.format.rawValue)")

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(audioData)
            try data.write(to: fileURL)

            // 检查缓存大小
            checkCacheSize()
        } catch {
            print("⚠️ TTS 缓存保存失败: \(error.localizedDescription)")
        }
    }

    /// 检索音频数据
    func retrieve(key: String) -> AudioData? {
        // 尝试不同的音频格式
        let formats: [AudioData.AudioFormat] = [.mp3, .wav, .aac, .opus]

        for format in formats {
            let fileURL = cacheDirectory.appendingPathComponent("\(key).\(format.rawValue)")

            guard fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                let audioData = try decoder.decode(AudioData.self, from: data)

                // 更新访问时间
                try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)

                return audioData
            } catch {
                print("⚠️ TTS 缓存读取失败: \(error.localizedDescription)")
            }
        }

        return nil
    }

    /// 清除所有缓存
    func clearAll() {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            print("🗑️ TTS 缓存已清空")
        } catch {
            print("⚠️ 清空 TTS 缓存失败: \(error.localizedDescription)")
        }
    }

    /// 清除特定缓存
    func clear(key: String) {
        let formats: [AudioData.AudioFormat] = [.mp3, .wav, .aac, .opus]

        for format in formats {
            let fileURL = cacheDirectory.appendingPathComponent("\(key).\(format.rawValue)")
            try? fileManager.removeItem(at: fileURL)
        }
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
            print("⚠️ 获取 TTS 缓存大小失败: \(error.localizedDescription)")
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

    /// 获取缓存文件数量
    func getCacheCount() -> Int {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            return files.count
        } catch {
            return 0
        }
    }

    // MARK: - Private Methods

    /// 检查缓存大小并清理
    private func checkCacheSize() {
        let currentSize = getCacheSize()

        if currentSize > maxCacheSize {
            print("⚠️ 缓存超出限制，开始清理...")
            cleanupOldestCache(targetSize: maxCacheSize * 80 / 100)  // 清理到 80%
        }
    }

    /// 清理最旧的缓存
    private func cleanupOldestCache(targetSize: Int64) {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )

            // 按修改时间排序
            let sortedFiles = files.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 < date2
            }

            var currentSize = getCacheSize()
            var deletedCount = 0

            for file in sortedFiles {
                if currentSize <= targetSize {
                    break
                }

                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let size = attributes[.size] as? Int64 {
                    try fileManager.removeItem(at: file)
                    currentSize -= size
                    deletedCount += 1
                }
            }

            print("🗑️ 已清理 \(deletedCount) 个旧缓存文件")
        } catch {
            print("⚠️ 清理缓存失败: \(error.localizedDescription)")
        }
    }

    /// 清理过期缓存（超过 30 天）
    private func cleanupExpiredCache() {
        let expirationDays: TimeInterval = 30 * 24 * 60 * 60  // 30 天

        do {
            let files = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )

            var deletedCount = 0

            for file in files {
                let resourceValues = try file.resourceValues(forKeys: [.contentModificationDateKey])
                if let modificationDate = resourceValues.contentModificationDate {
                    let age = Date().timeIntervalSince(modificationDate)
                    if age > expirationDays {
                        try fileManager.removeItem(at: file)
                        deletedCount += 1
                    }
                }
            }

            if deletedCount > 0 {
                print("🗑️ 已清理 \(deletedCount) 个过期缓存文件")
            }
        } catch {
            print("⚠️ 清理过期缓存失败: \(error.localizedDescription)")
        }
    }
}
