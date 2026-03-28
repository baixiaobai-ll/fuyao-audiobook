import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: AudioBookPlayer
    let chapterTitle: String

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Book/chapter icon
            Image(systemName: "headphones")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            // Chapter title
            Text(chapterTitle)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Progress
            VStack(spacing: 8) {
                let d = player.progress.duration
                let t = player.progress.currentTime
                let prog = (d.isFinite && d > 0 && t.isFinite) ? min(t / d, 1.0) : 0.0
                ProgressView(value: prog, total: 1.0)
                    .progressViewStyle(.linear)
                    .padding(.horizontal)

                HStack {
                    Text(formatTime(player.progress.currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(player.progress.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            // Controls
            HStack(spacing: 48) {
                Button(action: { player.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.title)
                }
                .disabled(!(player.currentPlaylist?.hasPrevious ?? false))

                Button(action: {
                    if player.state == .playing {
                        player.pause()
                    } else {
                        player.play()
                    }
                }) {
                    Image(systemName: playButtonIcon)
                        .font(.system(size: 56))
                }

                Button(action: { player.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.title)
                }
                .disabled(!(player.currentPlaylist?.hasNext ?? false))
            }
            .foregroundColor(.primary)

            Spacer()
        }
        .navigationTitle("正在播放")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var playButtonIcon: String {
        switch player.state {
        case .playing: return "pause.circle.fill"
        case .loading: return "hourglass"
        default: return "play.circle.fill"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
