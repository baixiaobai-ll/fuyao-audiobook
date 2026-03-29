import SwiftUI

@main
struct FuyaoApp: App {
    @StateObject private var store = BookshelfStore()
    @StateObject private var player = AudioBookPlayer()
    @StateObject private var profileStore = UserProfileStore()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .environmentObject(player)
                    .environmentObject(profileStore)

                if showSplash {
                    SplashView()
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
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(red: 0.91, green: 0.85, blue: 0.80)
                .ignoresSafeArea()

            Image("splash")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .ignoresSafeArea()
        }
    }
}
