import SwiftUI

/// 主界面底部 Tab 切换（发现页播放时跳转「播放」标签）
@MainActor
final class MainTabRouter: ObservableObject {
    struct PlaybackPreparation: Equatable {
        let bookTitle: String
        let chapterTitle: String
        var message: String
    }

    enum Tab: Int {
        case bookshelf = 0
        case discover = 1
        case play = 2
        case profile = 3
    }

    enum LoginPresentationMode: Equatable {
        case oneClick
        case sms
    }

    @Published var selectedTab: Int = Tab.bookshelf.rawValue
    @Published var isLoginPresented = false
    @Published var loginPresentationMode: LoginPresentationMode = .oneClick
    @Published var playbackPreparation: PlaybackPreparation? = nil

    func openPlayTab() {
        selectedTab = Tab.play.rawValue
    }

    func presentLogin(mode: LoginPresentationMode = .oneClick) {
        loginPresentationMode = mode
        isLoginPresented = true
    }

    func dismissLogin() {
        isLoginPresented = false
    }

    func beginPlaybackPreparation(bookTitle: String, chapterTitle: String, message: String) {
        playbackPreparation = PlaybackPreparation(
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            message: message
        )
    }

    func updatePlaybackPreparation(message: String) {
        guard var current = playbackPreparation else { return }
        current.message = message
        playbackPreparation = current
    }

    func finishPlaybackPreparation(openPlayer: Bool) {
        playbackPreparation = nil
        if openPlayer {
            openPlayTab()
        }
    }
}
