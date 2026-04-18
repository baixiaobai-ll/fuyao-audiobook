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
        .fullScreenCover(isPresented: $tabRouter.isLoginPresented) {
            LoginView()
                .environmentObject(profileStore)
        }
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
}
