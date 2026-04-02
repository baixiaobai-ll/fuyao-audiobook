import SwiftUI
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

@main
struct FuyaoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = BookshelfStore()
    @StateObject private var player = AudioBookPlayer()
    @StateObject private var profileStore = UserProfileStore()
    @StateObject private var tabRouter = MainTabRouter()
    @State private var showSplash = true
    @State private var splashAssetName = SplashView.randomAssetName()

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .environmentObject(player)
                    .environmentObject(profileStore)
                    .environmentObject(tabRouter)

                if showSplash {
                    SplashView(imageName: splashAssetName)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                clearResidualLiveActivitiesIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeOut(duration: 0.6)) {
                        showSplash = false
                    }
                }
            }
            .onOpenURL { url in
                handlePlayerShortcut(url: url)
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background, player.state == .playing {
                    player.play()
                } else if newPhase == .inactive, player.state == .stopped {
                    clearResidualLiveActivitiesIfNeeded()
                }
            }
        }
    }

    private func clearResidualLiveActivitiesIfNeeded() {
        #if os(iOS) && canImport(ActivityKit)
        if #available(iOS 16.1, *), player.state == .idle || player.state == .stopped {
            FuyaoLiveActivityManager.shared.clearAllActivities()
        }
        #endif
    }

    private func handlePlayerShortcut(url: URL) {
        guard url.scheme == "fuyao", url.host == "player" else { return }

        switch url.path {
        case "/play":
            player.play()
            tabRouter.openPlayTab()
        case "/pause":
            player.pause()
            tabRouter.openPlayTab()
        case "/toggle":
            if player.state == .playing {
                player.pause()
            } else {
                player.play()
            }
            tabRouter.openPlayTab()
        case "/next":
            player.next()
            tabRouter.openPlayTab()
        case "/previous":
            player.previous()
            tabRouter.openPlayTab()
        default:
            break
        }
    }
}

struct SplashView: View {
    let imageName: String

    static func randomAssetName() -> String {
        ["splash", "splash_alt_1", "splash_alt_2"].randomElement() ?? "splash"
    }

    var body: some View {
        ZStack {
            Color(red: 0.91, green: 0.85, blue: 0.80)
                .ignoresSafeArea()

            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .ignoresSafeArea()
        }
    }
}
