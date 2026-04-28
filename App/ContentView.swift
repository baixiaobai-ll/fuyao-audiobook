import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var store: BookshelfStore
    @EnvironmentObject var tabRouter: MainTabRouter
    @EnvironmentObject var profileStore: UserProfileStore

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        appearance.backgroundColor = UIColor.white.withAlphaComponent(0.88)
        appearance.shadowColor = UIColor(red: 0.41, green: 0.52, blue: 0.80, alpha: 0.12)
        appearance.shadowImage = UIImage()

        let normal = UITabBarItemAppearance()
        normal.normal.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor(red: 0.48, green: 0.54, blue: 0.65, alpha: 1)
        ]
        normal.selected.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor(red: 0.39, green: 0.41, blue: 0.78, alpha: 1)
        ]
        normal.normal.iconColor = UIColor.secondaryLabel
        normal.selected.iconColor = UIColor(AppTheme.Colors.brandPrimary)

        appearance.stackedLayoutAppearance = normal
        appearance.inlineLayoutAppearance = normal
        appearance.compactInlineLayoutAppearance = normal
        appearance.selectionIndicatorImage = Self.selectionIndicatorImage()

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().itemPositioning = .automatic
    }

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            BookshelfView()
                .environmentObject(store)
                .tabItem {
                    tabItemLabel(title: "书架", imageName: "tab_bookshelf")
                }
                .tag(MainTabRouter.Tab.bookshelf.rawValue)

            BookSearchView()
                .environmentObject(store)
                .tabItem {
                    tabItemLabel(title: "发现", imageName: "tab_discover")
                }
                .tag(MainTabRouter.Tab.discover.rawValue)

            NowPlayingView()
                .environmentObject(store)
                .tabItem {
                    tabItemLabel(title: "播放", imageName: "tab_play")
                }
                .tag(MainTabRouter.Tab.play.rawValue)

            ProfileView()
                .tabItem {
                    tabItemLabel(title: "我的", imageName: "tab_profile")
                }
                .tag(MainTabRouter.Tab.profile.rawValue)
        }
        .tint(AppTheme.Colors.brandPrimary)
        .onChange(of: profileStore.isLoggedIn) { isLoggedIn in
            if isLoggedIn {
                tabRouter.dismissLogin()
            }
        }
        .background(
            OneClickLoginLauncher()
                .environmentObject(profileStore)
                .environmentObject(tabRouter)
                .allowsHitTesting(false)
        )
        .fullScreenCover(isPresented: smsLoginPresented) {
            LoginView()
                .environmentObject(profileStore)
                .environmentObject(tabRouter)
        }
        .overlay(alignment: .top) {
            if let preparation = tabRouter.playbackPreparation {
                playbackPreparationBanner(preparation)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: tabRouter.playbackPreparation)
    }

    private var smsLoginPresented: Binding<Bool> {
        Binding(
            get: {
                tabRouter.isLoginPresented && tabRouter.loginPresentationMode == .sms
            },
            set: { isPresented in
                if !isPresented && tabRouter.loginPresentationMode == .sms {
                    tabRouter.dismissLogin()
                }
            }
        )
    }

    @ViewBuilder
    private func tabItemLabel(title: String, imageName: String) -> some View {
        VStack(spacing: 4) {
            Image(imageName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text(title)
        }
    }

    private func playbackPreparationBanner(_ preparation: MainTabRouter.PlaybackPreparation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.43, green: 0.66, blue: 0.97),
                                Color(red: 0.62, green: 0.49, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.82)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("正在缓冲，准备好后自动播放")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("\(preparation.bookTitle) · \(preparation.chapterTitle)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                if !preparation.message.isEmpty {
                    Text(preparation.message)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.86))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.09), radius: 18, x: 0, y: 10)
        )
    }

    private static func selectionIndicatorImage() -> UIImage? {
        let size = CGSize(width: 78, height: 38)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let shadowPath = UIBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), cornerRadius: 19)

            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 6),
                blur: 16,
                color: UIColor(red: 0.57, green: 0.57, blue: 0.91, alpha: 0.18).cgColor
            )
            UIColor.clear.setFill()
            shadowPath.fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            let fillRect = rect.insetBy(dx: 5, dy: 5)
            let fillPath = UIBezierPath(roundedRect: fillRect, cornerRadius: 19)
            UIColor(red: 0.91, green: 0.95, blue: 1.0, alpha: 0.92).setFill()
            fillPath.fill()

            UIColor(red: 0.76, green: 0.78, blue: 0.99, alpha: 0.82).setStroke()
            fillPath.lineWidth = 1
            fillPath.stroke()
        }
        .resizableImage(withCapInsets: UIEdgeInsets(top: 14, left: 26, bottom: 14, right: 26))
    }
}

#Preview {
    ContentView()
        .environmentObject(BookshelfStore())
        .environmentObject(AudioBookPlayer())
        .environmentObject(MainTabRouter())
        .environmentObject(UserProfileStore())
}
