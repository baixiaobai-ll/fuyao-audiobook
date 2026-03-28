//
//  Extensions.swift
//  AI有声书
//
//  常用扩展和工具函数
//

import Foundation

// MARK: - Array 扩展

extension Array {

    /// 安全访问数组元素
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }

    /// 将数组分块
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - String 扩展

extension String {

    /// 移除首尾空白字符
    var trimmed: String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 是否为空（包括只有空白字符）
    var isBlank: Bool {
        return trimmed.isEmpty
    }

    /// 字符数（中文按 1 个字符计算）
    var characterCount: Int {
        return count
    }

    /// 字节数
    var byteCount: Int {
        return utf8.count
    }

    /// 截取指定长度
    func truncate(to length: Int, trailing: String = "...") -> String {
        if count <= length {
            return self
        }
        return String(prefix(length)) + trailing
    }

    /// 移除 HTML 标签
    var removingHTMLTags: String {
        return replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// 转换为 URL
    var asURL: URL? {
        return URL(string: self)
    }
}

// MARK: - Date 扩展

extension Date {

    /// 格式化为字符串
    func formatted(style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: self)
    }

    /// 格式化为时间字符串
    func formattedTime(style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = style
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: self)
    }

    /// 格式化为日期时间字符串
    func formattedDateTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: self)
    }

    /// 相对时间描述（如：刚刚、5分钟前）
    var relativeDescription: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分钟前"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)小时前"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)天前"
        } else {
            return formatted()
        }
    }
}

// MARK: - TimeInterval 扩展

extension TimeInterval {

    /// 格式化为时长字符串（HH:MM:SS）
    var formattedDuration: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// 格式化为中文时长（X小时X分钟）
    var formattedChineseDuration: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)小时\(minutes)分钟"
            } else {
                return "\(hours)小时"
            }
        } else if minutes > 0 {
            return "\(minutes)分钟"
        } else {
            return "\(seconds)秒"
        }
    }
}

// MARK: - Data 扩展

extension Data {

    /// 格式化文件大小
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(count))
    }

    /// 转换为十六进制字符串
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Int 扩展

extension Int {

    /// 格式化为文件大小
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(self))
    }

    /// 格式化为千分位数字
    var formattedNumber: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// MARK: - Double 扩展

extension Double {

    /// 格式化为百分比
    var formattedPercentage: String {
        return String(format: "%.1f%%", self * 100)
    }

    /// 四舍五入到指定小数位
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

// MARK: - URL 扩展

extension URL {

    /// 文件大小
    var fileSize: Int64? {
        let values = try? resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map { Int64($0) }
    }

    /// 创建日期
    var creationDate: Date? {
        let values = try? resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate
    }

    /// 修改日期
    var modificationDate: Date? {
        let values = try? resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}

// MARK: - Result 扩展

extension Result {

    /// 是否成功
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    /// 是否失败
    var isFailure: Bool {
        return !isSuccess
    }

    /// 获取成功值
    var value: Success? {
        switch self {
        case .success(let value):
            return value
        case .failure:
            return nil
        }
    }

    /// 获取错误
    var error: Failure? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}

// MARK: - Collection 扩展

extension Collection {

    /// 是否不为空
    var isNotEmpty: Bool {
        return !isEmpty
    }
}

// MARK: - Optional 扩展

extension Optional {

    /// 是否为 nil
    var isNil: Bool {
        return self == nil
    }

    /// 是否不为 nil
    var isNotNil: Bool {
        return self != nil
    }
}

// MARK: - 工具函数

/// 延迟执行
func delay(_ seconds: TimeInterval, execute: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: execute)
}

/// 主线程执行
func onMainThread(_ execute: @escaping () -> Void) {
    if Thread.isMainThread {
        execute()
    } else {
        DispatchQueue.main.async(execute: execute)
    }
}

/// 后台线程执行
func onBackgroundThread(_ execute: @escaping () -> Void) {
    DispatchQueue.global(qos: .background).async(execute: execute)
}

/// 测量执行时间
func measureTime(_ label: String = "执行", block: () throws -> Void) rethrows {
    let start = Date()
    try block()
    let duration = Date().timeIntervalSince(start)
    print("⏱️ [\(label)] 耗时: \(String(format: "%.3f", duration))秒")
}

/// 异步测量执行时间
func measureTimeAsync(_ label: String = "执行", block: () async throws -> Void) async rethrows {
    let start = Date()
    try await block()
    let duration = Date().timeIntervalSince(start)
    print("⏱️ [\(label)] 耗时: \(String(format: "%.3f", duration))秒")
}

// MARK: - 调试工具

/// 打印调试信息（仅在 Debug 模式）
func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    Swift.print("🔍 [DEBUG]", output, terminator: terminator)
    #endif
}

/// 打印错误信息
func errorPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let output = items.map { "\($0)" }.joined(separator: separator)
    Swift.print("❌ [ERROR]", output, terminator: terminator)
}

/// 打印警告信息
func warningPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let output = items.map { "\($0)" }.joined(separator: separator)
    Swift.print("⚠️ [WARNING]", output, terminator: terminator)
}

/// 打印成功信息
func successPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let output = items.map { "\($0)" }.joined(separator: separator)
    Swift.print("✅ [SUCCESS]", output, terminator: terminator)
}

// MARK: - 文件工具

struct FileHelper {

    /// 获取文档目录
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// 获取缓存目录
    static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    /// 获取临时目录
    static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory
    }

    /// 创建目录
    static func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// 删除文件或目录
    static func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// 文件是否存在
    static func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// 获取目录下的所有文件
    static func files(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
    }

    /// 获取目录大小
    static func directorySize(at url: URL) -> Int64 {
        var totalSize: Int64 = 0

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            if let size = fileURL.fileSize {
                totalSize += size
            }
        }

        return totalSize
    }
}

// MARK: - JSON 工具

struct JSONHelper {

    /// 编码为 JSON 字符串
    static func encode<T: Encodable>(_ value: T, prettyPrinted: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = .prettyPrinted
        }
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 从 JSON 字符串解码
    static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let data = string.data(using: .utf8)!
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}
