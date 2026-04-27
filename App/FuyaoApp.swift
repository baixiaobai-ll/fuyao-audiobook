import SwiftUI

@main
struct FuyaoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = BookshelfStore()
    @StateObject private var player = AudioBookPlayer()
    @StateObject private var profileStore = UserProfileStore()
    @StateObject private var tabRouter = MainTabRouter()
    @State private var showSplash = true
    @State private var splashAssetName = SplashView.nextAssetName()

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
                }
            }
        }
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
    @State private var isReady = false

    static let assetNames = [
            "splash",
            "splash_alt_1",
            "splash_alt_2",
            "splash_sakura",
            "splash_ink",
            "splash_cyber"
    ]

    static func nextAssetName() -> String {
        guard !assetNames.isEmpty else { return "splash" }

        let defaults = UserDefaults.standard
        let key = "fuyao.splash.next-index"
        let index = defaults.integer(forKey: key) % assetNames.count
        let nextIndex = (index + 1) % assetNames.count
        defaults.set(nextIndex, forKey: key)
        return assetNames[index]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.92, blue: 0.88),
                    Color(red: 0.87, green: 0.92, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .scaleEffect(isReady ? 1 : 1.06)
                .opacity(isReady ? 1 : 0.92)
                .animation(.easeOut(duration: 1.1), value: isReady)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.16, blue: 0.28).opacity(0.12),
                            .clear,
                            Color(red: 0.98, green: 0.90, blue: 0.78).opacity(0.36)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(spacing: 12) {
                    Text("正在整理你的听书宇宙")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.96))

                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 112, height: 5)
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.99, green: 0.89, blue: 0.62),
                                            .white
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: isReady ? 96 : 42, height: 5)
                                .animation(.easeOut(duration: 1.2), value: isReady)
                        }
                }
                .padding(.bottom, 58)
                .opacity(isReady ? 1 : 0)
                .offset(y: isReady ? 0 : 14)
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            isReady = true
        }
    }
}
