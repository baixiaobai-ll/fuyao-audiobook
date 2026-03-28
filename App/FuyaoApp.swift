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
    @State private var scale: CGFloat = 1.05
    @State private var opacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.93, green: 0.95, blue: 0.98)
                    .ignoresSafeArea()

                Image("splash")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .clipped()
                    .ignoresSafeArea()
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 1
            }
            withAnimation(.easeInOut(duration: 3.0)) {
                scale = 1.0
            }
        }
    }
}
