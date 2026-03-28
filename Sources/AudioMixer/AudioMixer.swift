//
//  AudioMixer.swift
//  AI有声书
//
//  音频混合器 - 混合语音、背景音乐和音效
//

import Foundation
import AVFoundation

/// 音频混合器协议
protocol AudioMixerProtocol {
    func mix(task: AudioMixTask) async throws -> AudioMixResult
}

/// 音频混合器
class AudioMixer: AudioMixerProtocol {

    private let musicSelector: SceneMusicSelector
    private let fileManager = FileManager.default
    private let tempDirectory: URL

    init(musicSelector: SceneMusicSelector = SceneMusicSelector()) {
        self.musicSelector = musicSelector

        // 创建临时目录
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent("AudioMixer", isDirectory: true)
        try? fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)
        self.tempDirectory = tempURL
    }

    /// 混合音频
    func mix(task: AudioMixTask) async throws -> AudioMixResult {
        print("🎵 开始混合音频...")

        // 1. 保存语音音频到临时文件
        let voiceURL = try saveToTempFile(task.voiceAudio, name: "voice")

        // 2. 创建音频组合
        let composition = AVMutableComposition()

        // 3. 添加语音轨道
        guard let voiceTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioMixerError.trackCreationFailed
        }

        let voiceAsset = AVURLAsset(url: voiceURL)
        guard let voiceAssetTrack = try await voiceAsset.loadTracks(withMediaType: .audio).first else {
            throw AudioMixerError.invalidAudioFile
        }

        let voiceDuration = try await voiceAsset.load(.duration)
        try voiceTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: voiceDuration),
            of: voiceAssetTrack,
            at: .zero
        )

        // 4. 添加背景音乐（如果启用）
        if task.config.enableBackgroundMusic, let backgroundMusic = task.backgroundMusic {
            try await addBackgroundMusic(
                backgroundMusic,
                to: composition,
                duration: voiceDuration,
                volume: task.config.backgroundMusicVolume
            )
        }

        // 5. 添加音效（如果启用）
        if task.config.enableSoundEffects && !task.soundEffects.isEmpty {
            try await addSoundEffects(
                task.soundEffects,
                to: composition,
                duration: voiceDuration,
                volume: task.config.soundEffectsVolume
            )
        }

        // 6. 设置音量
        let audioMix = AVMutableAudioMix()
        var audioMixParameters: [AVMutableAudioMixInputParameters] = []

        // 语音音量
        let voiceParams = AVMutableAudioMixInputParameters(track: voiceTrack)
        voiceParams.setVolume(task.config.voiceVolume, at: .zero)
        audioMixParameters.append(voiceParams)

        audioMix.inputParameters = audioMixParameters

        // 7. 导出混合后的音频
        let outputURL = tempDirectory.appendingPathComponent("mixed_\(UUID().uuidString).m4a")
        let mixedAudioData = try await exportComposition(
            composition,
            audioMix: audioMix,
            to: outputURL
        )

        // 8. 创建结果
        let duration = CMTimeGetSeconds(voiceDuration)
        let result = AudioMixResult(
            audioData: mixedAudioData,
            duration: duration,
            voiceSegments: [
                AudioMixResult.VoiceSegment(
                    startTime: 0,
                    endTime: duration,
                    text: task.segment.text
                )
            ]
        )

        // 9. 清理临时文件
        try? fileManager.removeItem(at: voiceURL)

        print("✅ 音频混合完成")

        return result
    }

    // MARK: - Private Methods

    /// 添加背景音乐
    private func addBackgroundMusic(
        _ music: BackgroundMusic,
        to composition: AVMutableComposition,
        duration: CMTime,
        volume: Float
    ) async throws {
        guard let musicTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioMixerError.trackCreationFailed
        }

        // 获取音乐文件 URL
        let musicURL = getMusicFileURL(music)
        guard fileManager.fileExists(atPath: musicURL.path) else {
            print("⚠️ 背景音乐文件不存在: \(music.fileName)")
            return
        }

        let musicAsset = AVURLAsset(url: musicURL)
        guard let musicAssetTrack = try await musicAsset.loadTracks(withMediaType: .audio).first else {
            return
        }

        let musicDuration = try await musicAsset.load(.duration)
        let targetDuration = duration

        // 如果音乐可循环且时长不够，则循环播放
        if music.isLoopable && CMTimeCompare(musicDuration, targetDuration) < 0 {
            var currentTime = CMTime.zero
            while CMTimeCompare(currentTime, targetDuration) < 0 {
                let remainingTime = CMTimeSubtract(targetDuration, currentTime)
                let insertDuration = CMTimeCompare(musicDuration, remainingTime) < 0 ? musicDuration : remainingTime

                try musicTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: insertDuration),
                    of: musicAssetTrack,
                    at: currentTime
                )

                currentTime = CMTimeAdd(currentTime, insertDuration)
            }
        } else {
            // 直接插入
            let insertDuration = CMTimeCompare(musicDuration, targetDuration) < 0 ? musicDuration : targetDuration
            try musicTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: musicAssetTrack,
                at: .zero
            )
        }

        // 设置音量（通过 AVMutableAudioMixInputParameters）
        let musicParams = AVMutableAudioMixInputParameters(track: musicTrack)
        musicParams.setVolume(volume, at: .zero)
    }

    /// 添加音效
    private func addSoundEffects(
        _ effects: [SoundEffect],
        to composition: AVMutableComposition,
        duration: CMTime,
        volume: Float
    ) async throws {
        for effect in effects {
            guard let effectTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }

            let effectURL = getSoundEffectFileURL(effect)
            guard fileManager.fileExists(atPath: effectURL.path) else {
                print("⚠️ 音效文件不存在: \(effect.fileName)")
                continue
            }

            let effectAsset = AVURLAsset(url: effectURL)
            guard let effectAssetTrack = try await effectAsset.loadTracks(withMediaType: .audio).first else {
                continue
            }

            let effectDuration = try await effectAsset.load(.duration)

            // 在随机位置插入音效（可以根据需求调整）
            let insertTime = CMTime.zero  // 简单起见，从开始插入

            try effectTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: effectDuration),
                of: effectAssetTrack,
                at: insertTime
            )

            let effectParams = AVMutableAudioMixInputParameters(track: effectTrack)
            effectParams.setVolume(volume, at: .zero)
        }
    }

    /// 导出组合
    private func exportComposition(
        _ composition: AVMutableComposition,
        audioMix: AVMutableAudioMix,
        to outputURL: URL
    ) async throws -> AudioData {
        // 删除已存在的文件
        try? fileManager.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioMixerError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.audioMix = audioMix

        await exportSession.export()

        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                throw AudioMixerError.exportFailed
            }
            throw AudioMixerError.exportFailed
        }

        // 读取导出的文件
        let data = try Data(contentsOf: outputURL)
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)

        return AudioData(
            data: data,
            format: .aac,
            duration: CMTimeGetSeconds(duration),
            sampleRate: 44100
        )
    }

    /// 保存音频数据到临时文件
    private func saveToTempFile(_ audioData: AudioData, name: String) throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent("\(name).\(audioData.format.rawValue)")
        try audioData.data.write(to: fileURL)
        return fileURL
    }

    /// 获取音乐文件 URL
    private func getMusicFileURL(_ music: BackgroundMusic) -> URL {
        // 实际使用时应该从 Resources 目录加载
        // 这里返回一个占位路径
        return Bundle.main.url(forResource: music.fileName.replacingOccurrences(of: ".mp3", with: ""), withExtension: "mp3")
            ?? tempDirectory.appendingPathComponent(music.fileName)
    }

    /// 获取音效文件 URL
    private func getSoundEffectFileURL(_ effect: SoundEffect) -> URL {
        // 实际使用时应该从 Resources 目录加载
        return Bundle.main.url(forResource: effect.fileName.replacingOccurrences(of: ".mp3", with: ""), withExtension: "mp3")
            ?? tempDirectory.appendingPathComponent(effect.fileName)
    }

    /// 清理临时文件
    func cleanupTempFiles() {
        do {
            let files = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            print("🗑️ 临时文件已清理")
        } catch {
            print("⚠️ 清理临时文件失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - 场景音乐选择器

/// 场景音乐选择器
class SceneMusicSelector {

    /// 为场景选择音乐
    func selectMusic(for scene: NovelScene) -> BackgroundMusic? {
        return MusicLibrary.randomMusic(for: scene.type)
    }

    /// 为文本片段选择音乐
    func selectMusic(for segment: TextSegment) -> BackgroundMusic? {
        return selectMusic(for: segment.scene)
    }

    /// 批量为片段选择音乐
    func selectMusic(for segments: [TextSegment]) -> [TextSegment: BackgroundMusic] {
        var musicMap: [TextSegment: BackgroundMusic] = [:]

        for segment in segments {
            if let music = selectMusic(for: segment) {
                musicMap[segment] = music
            }
        }

        return musicMap
    }
}

// MARK: - 错误类型

enum AudioMixerError: LocalizedError {
    case trackCreationFailed
    case invalidAudioFile
    case exportFailed
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .trackCreationFailed:
            return "创建音频轨道失败"
        case .invalidAudioFile:
            return "无效的音频文件"
        case .exportFailed:
            return "导出音频失败"
        case .fileNotFound:
            return "文件不存在"
        }
    }
}
