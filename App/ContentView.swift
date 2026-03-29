import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BookshelfStore
    @EnvironmentObject var tabRouter: MainTabRouter

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let normal = UITabBarItemAppearance()
        normal.normal.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        normal.selected.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor(AppTheme.Colors.brandPrimary)
        ]
        normal.normal.iconColor = UIColor.secondaryLabel
        normal.selected.iconColor = UIColor(AppTheme.Colors.brandPrimary)

        appearance.stackedLayoutAppearance = normal
        appearance.inlineLayoutAppearance = normal
        appearance.compactInlineLayoutAppearance = normal

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            BookshelfView()
                .environmentObject(store)
                .tabItem {
                    Label("书架", image: "tab_bookshelf")
                }
                .tag(MainTabRouter.Tab.bookshelf.rawValue)

            BookSearchView()
                .environmentObject(store)
                .tabItem {
                    Label("发现", image: "tab_discover")
                }
                .tag(MainTabRouter.Tab.discover.rawValue)

            NowPlayingView()
                .environmentObject(store)
                .tabItem {
                    Label("播放", image: "tab_play")
                }
                .tag(MainTabRouter.Tab.play.rawValue)

            ProfileView()
                .tabItem {
                    Label("我的", image: "tab_profile")
                }
                .tag(MainTabRouter.Tab.profile.rawValue)
        }
        .tint(AppTheme.Colors.brandPrimary)
    }
}

#Preview {
    ContentView()
        .environmentObject(BookshelfStore())
        .environmentObject(AudioBookPlayer())
        .environmentObject(MainTabRouter())
}
