#if canImport(ActivityKit) && canImport(WidgetKit)
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct FuyaoLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FuyaoPlaybackAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    coverArtwork(url: context.state.bookCoverURL, size: 52)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 10) {
                        controlLink(systemName: "backward.fill", url: "fuyao://player/previous")
                        controlLink(systemName: context.state.isPlaying ? "pause.fill" : "play.fill", url: "fuyao://player/toggle")
                        controlLink(systemName: "forward.fill", url: "fuyao://player/next")
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text(context.state.bookTitle)
                                .font(.headline)
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                            Text(context.state.chapterTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                        }

                        ProgressView(value: context.state.progress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text(timeString(context.state.elapsedTime))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(timeString(context.state.duration))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } compactLeading: {
                brandIcon(size: 22)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
            } minimal: {
                brandIcon(size: 18)
            }
        }
    }

    private func lockScreenView(context: ActivityViewContext<FuyaoPlaybackAttributes>) -> some View {
        HStack(spacing: 16) {
            coverArtwork(url: context.state.bookCoverURL, size: 78)

            VStack(spacing: 12) {
                VStack(spacing: 5) {
                    Text(context.state.bookTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)

                    Text(context.state.chapterTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                ProgressView(value: context.state.progress)
                    .progressViewStyle(.linear)

                HStack(spacing: 18) {
                    controlLink(systemName: "backward.fill", url: "fuyao://player/previous")
                    controlLink(systemName: context.state.isPlaying ? "pause.fill" : "play.fill", url: "fuyao://player/toggle", size: 38)
                    controlLink(systemName: "forward.fill", url: "fuyao://player/next")
                }

                HStack {
                    Text(timeString(context.state.elapsedTime))
                    Spacer()
                    Text(timeString(context.state.duration))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.accentColor)
    }

    private func controlLink(systemName: String, url: String, size: CGFloat = 32) -> some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func brandIcon(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.white.opacity(0.08))
            Image("fuyao_live_icon")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .padding(size * 0.06)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    @ViewBuilder
    private func coverArtwork(url: String?, size: CGFloat) -> some View {
        if let url, let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholderArtwork(size: size)
                }
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        } else {
            placeholderArtwork(size: size)
        }
    }

    private func placeholderArtwork(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.93, green: 0.88, blue: 0.79), Color(red: 0.83, green: 0.72, blue: 0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            brandIcon(size: size * 0.58)
        }
        .frame(width: size, height: size)
    }

    private func timeString(_ value: TimeInterval) -> String {
        let totalSeconds = max(Int(value), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
