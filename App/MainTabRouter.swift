import SwiftUI

/// 主界面底部 Tab 切换（发现页播放时跳转「播放」标签）
@MainActor
final class MainTabRouter: ObservableObject {
    enum Tab: Int {
        case bookshelf = 0
        case discover = 1
        case play = 2
        case profile = 3
    }

    @Published var selectedTab: Int = Tab.bookshelf.rawValue

    func openPlayTab() {
        selectedTab = Tab.play.rawValue
    }
}
