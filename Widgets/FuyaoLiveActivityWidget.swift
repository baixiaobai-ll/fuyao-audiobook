#if canImport(ActivityKit) && canImport(WidgetKit)
import ActivityKit
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

private struct WidgetRemoteArtwork: View {
    let url: URL
    let title: String
    let size: CGFloat
    let cornerRatio: CGFloat
    let showsSubtitle: Bool

    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                loadingArtwork
            } else {
                fallbackArtwork
                    .task(id: url.absoluteString) {
                        await loadImage()
                    }
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous))
    }

    @MainActor
    private func loadImage() async {
        guard !isLoading, loadedImage == nil else { return }
        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let host = url.host, host.contains("bqg291.cc") {
            request.setValue("https://www.bqg291.cc", forHTTPHeaderField: "Referer")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let image = UIImage(data: data) {
                loadedImage = image
            }
        } catch {
            loadedImage = nil
        }
    }

    private var loadingArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.90, green: 0.94, blue: 0.98), Color(red: 0.82, green: 0.88, blue: 0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            ProgressView()
                .tint(Color.white)
        }
    }

    private var fallbackArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.86, green: 0.93, blue: 0.98),
                            Color(red: 0.77, green: 0.85, blue: 0.96),
                            Color(red: 0.97, green: 0.85, blue: 0.73)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: max(size * 0.07, 6)) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: size * 0.18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))

                Text(bookMonogram)
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if showsSubtitle && size >= 72 {
                    Text(shortTitle)
                        .font(.system(size: size * 0.11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, size * 0.08)
                }
            }
        }
    }

    private var bookMonogram: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).isEmpty ? "书" : String(trimmed.prefix(1))
    }

    private var shortTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(8))
    }
}

@available(iOSApplicationExtension 16.1, *)
struct FuyaoLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FuyaoPlaybackAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    coverArtwork(
                        url: context.state.bookCoverURL,
                        title: context.state.bookTitle,
                        size: 58
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 10) {
                        controlLink(systemName: "backward.fill", url: "fuyao://player/previous")
                        controlLink(systemName: "toggle", url: "fuyao://player/toggle", emphasize: true, isPlaying: context.state.isPlaying)
                        controlLink(systemName: "forward.fill", url: "fuyao://player/next")
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            brandIcon(size: 18)
                            Text(statusTitle(isPlaying: context.state.isPlaying))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(activityAccentColor)
                            Spacer()
                            Text(progressText(progress: context.state.progress))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(context.state.bookTitle)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                            Text(context.state.chapterTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        ProgressView(value: context.state.progress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text(timeString(context.state.elapsedTime))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(timeString(context.state.duration))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                compactLogoIcon(size: 24)
            } compactTrailing: {
                compactPlaybackButton(isPlaying: context.state.isPlaying, size: 20)
            } minimal: {
                ZStack {
                    Circle()
                        .fill(activityAccentColor.opacity(0.16))
                    compactLogoIcon(size: 14)
                }
            }
            .keylineTint(activityAccentColor)
        }
    }

    private func lockScreenView(context: ActivityViewContext<FuyaoPlaybackAttributes>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            coverArtwork(
                url: context.state.bookCoverURL,
                title: context.state.bookTitle,
                size: 76
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.bookTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(context.state.chapterTitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    statusBadge(isPlaying: context.state.isPlaying, compact: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: context.state.progress)
                        .tint(.white)
                        .progressViewStyle(.linear)

                    HStack {
                        Text(timeString(context.state.elapsedTime))
                        Spacer()
                        Text(timeString(context.state.duration))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 22) {
                        controlLink(
                            systemName: "backward.fill",
                            url: "fuyao://player/previous",
                            size: 34,
                            foregroundColor: .white,
                            backgroundColor: Color.white.opacity(0.14)
                        )
                        controlLink(
                            systemName: "toggle",
                            url: "fuyao://player/toggle",
                            size: 44,
                            emphasize: true,
                            isPlaying: context.state.isPlaying,
                            foregroundColor: activityDarkColor,
                            backgroundColor: .white
                        )
                        controlLink(
                            systemName: "forward.fill",
                            url: "fuyao://player/next",
                            size: 34,
                            foregroundColor: .white,
                            backgroundColor: Color.white.opacity(0.14)
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.62),
                            Color(red: 0.28, green: 0.19, blue: 0.12).opacity(0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
        .activityBackgroundTint(.clear)
        .activitySystemActionForegroundColor(activityAccentColor)
    }

    private var activityAccentColor: Color {
        Color(red: 0.47, green: 0.31, blue: 0.19)
    }

    private var activityDarkColor: Color {
        Color(red: 0.20, green: 0.15, blue: 0.12)
    }

    private var brandBlueColor: Color {
        Color(red: 0.39, green: 0.67, blue: 0.98)
    }

    private var brandPurpleColor: Color {
        Color(red: 0.58, green: 0.39, blue: 0.92)
    }

    private var activityBackgroundColor: Color {
        Color(red: 0.98, green: 0.95, blue: 0.90)
    }

    private func controlLink(
        systemName: String,
        url: String,
        size: CGFloat = 32,
        emphasize: Bool = false,
        isPlaying: Bool? = nil,
        foregroundColor: Color? = nil,
        backgroundColor: Color? = nil
    ) -> some View {
        Link(destination: URL(string: url)!) {
            Group {
                if systemName == "toggle", let isPlaying {
                    playbackStatusGlyph(
                        isPlaying: isPlaying,
                        size: max(size * 0.42, 12),
                        emphasized: emphasize,
                        foregroundColor: foregroundColor
                    )
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(foregroundColor ?? (emphasize ? Color.white : activityAccentColor))
                }
            }
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(backgroundColor ?? (emphasize ? activityAccentColor : Color.white.opacity(0.92)))
            )
        }
        .buttonStyle(.plain)
    }

    private func brandIcon(size: CGFloat) -> some View {
        brandAssetImage()
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: max(size * 0.03, 0.8))
            )
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    @ViewBuilder
    private func compactLogoIcon(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.black)
            compactBrandAssetImage()
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .padding(size * 0.02)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }

    private func brandAssetImage() -> Image {
        #if canImport(UIKit)
        if let image = UIImage(named: "fuyao_live_icon", in: .main, with: nil) {
            return Image(uiImage: image).renderingMode(.original)
        }
        #endif
        return Image("fuyao_live_icon")
            .renderingMode(.original)
    }

    private func compactBrandAssetImage() -> Image {
        #if canImport(UIKit)
        if let image = UIImage(named: "fuyao_live_compact_icon", in: .main, with: nil) {
            return Image(uiImage: image).renderingMode(.original)
        }
        #endif
        return brandAssetImage()
    }

    @ViewBuilder
    private func coverArtwork(url: String?, title: String, size: CGFloat) -> some View {
        if let imageURL = resolvedCoverURL(from: url) {
            WidgetRemoteArtwork(
                url: imageURL,
                title: title,
                size: size,
                cornerRatio: 0.18,
                showsSubtitle: true
            )
            .contentShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        } else {
            bookCoverFallback(title: title, size: size)
        }
    }

    private func bookCoverFallback(
        title: String,
        size: CGFloat,
        showsSubtitle: Bool = true,
        cornerRatio: CGFloat = 0.18
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.86, green: 0.93, blue: 0.98),
                            Color(red: 0.77, green: 0.85, blue: 0.96),
                            Color(red: 0.97, green: 0.85, blue: 0.73)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: max(size * 0.07, 6)) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: size * 0.18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))

                Text(bookMonogram(from: title))
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if showsSubtitle && size >= 72 {
                    Text(shortTitle(from: title))
                        .font(.system(size: size * 0.11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, size * 0.08)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .frame(width: size, height: size)
    }

    private func statusTitle(isPlaying: Bool) -> String {
        isPlaying ? "正在播放" : "播放已暂停"
    }

    private func statusBadge(isPlaying: Bool, compact: Bool = false) -> some View {
        Text(isPlaying ? "播放中" : "已暂停")
            .font((compact ? Font.caption2 : Font.caption2).weight(.semibold))
            .foregroundStyle(.white.opacity(isPlaying ? 0.96 : 0.74))
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isPlaying ? Color.white.opacity(0.16) : Color.white.opacity(0.10))
            )
    }

    private func progressText(progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }

    private func compactPlaybackButton(isPlaying: Bool, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [brandBlueColor, brandPurpleColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            playbackStatusGlyph(
                isPlaying: isPlaying,
                size: max(size * 0.44, 8),
                emphasized: true,
                foregroundColor: .white
            )
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: brandPurpleColor.opacity(0.28), radius: 4, x: 0, y: 1)
    }

    @ViewBuilder
    private func playbackStatusGlyph(
        isPlaying: Bool,
        size: CGFloat,
        emphasized: Bool = false,
        foregroundColor: Color? = nil
    ) -> some View {
        if let assetImage = bundledPlaybackStatusImage(isPlaying: isPlaying) {
            assetImage
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(foregroundColor ?? (emphasized ? Color.white : activityAccentColor))
        }
    }

    private func bundledPlaybackStatusImage(isPlaying: Bool) -> Image? {
        #if canImport(UIKit)
        let assetName = isPlaying ? "fuyao_live_pause_icon" : "fuyao_live_play_icon"
        if let image = UIImage(named: assetName, in: .main, with: nil) {
            return Image(uiImage: image).renderingMode(.original)
        }
        #endif
        return nil
    }

    private func resolvedCoverURL(from rawURL: String?) -> URL? {
        guard let raw = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        if let direct = URL(string: raw), direct.scheme != nil {
            return direct
        }

        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }

        if raw.hasPrefix("/") {
            return URL(string: "https://www.bqg291.cc\(raw)")
        }

        return URL(string: "https://www.bqg291.cc/\(raw)")
    }

    private func bookMonogram(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).isEmpty ? "书" : String(trimmed.prefix(1))
    }

    private func shortTitle(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(8))
    }

    private func timeString(_ value: TimeInterval) -> String {
        let totalSeconds = max(Int(value), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
