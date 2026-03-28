import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioBookPlayer

    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var showSleepTimer = false
    @State private var showPlaylist = false

    private let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            Group {
                if player.currentPlaylist != nil {
                    playerContent
                } else {
                    emptyState
                }
            }
            .navigationTitle("播放中")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("empty_playing")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)

            Text("暂无播放内容")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("去书架选一本书吧")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Player Content

    private var playerContent: some View {
        VStack(spacing: 24) {
            Spacer()

            // 书名 / 章节标题
            VStack(spacing: 8) {
                Text(player.currentPlaylist?.title ?? "")
                    .font(.headline)
                    .foregroundColor(.secondary)

                if let item = player.currentPlaylist?.currentItem {
                    Text("第 \(item.order + 1) 段")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // 大图标
            Image(systemName: "headphones")
                .font(.system(size: 100))
                .foregroundColor(.accentColor)
                .padding(.vertical, 24)

            // 进度条
            progressSection

            // 倍速选择
            rateSelector

            // 控制按钮
            controlButtons

            // 底部功能行
            bottomActions

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: {
                        isDragging ? dragValue : sliderValue
                    },
                    set: { newValue in
                        isDragging = true
                        dragValue = newValue
                    }
                ),
                in: 0...safeMaxDuration,
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(to: dragValue)
                        isDragging = false
                    }
                }
            )
            .accentColor(.accentColor)

            HStack {
                Text(formatTime(isDragging ? dragValue : player.progress.currentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(player.progress.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
    }

    private var safeMaxDuration: Double {
        let d = player.progress.duration
        return d.isFinite && d > 0 ? d : 1
    }

    private var sliderValue: Double {
        guard player.progress.duration > 0,
              player.progress.currentTime.isFinite,
              player.progress.duration.isFinite else { return 0 }
        return min(player.progress.currentTime, safeMaxDuration)
    }

    // MARK: - Rate Selector

    private var rateSelector: some View {
        HStack(spacing: 12) {
            ForEach(rates, id: \.self) { rate in
                Button {
                    player.setPlaybackRate(rate)
                } label: {
                    Text(rateLabel(rate))
                        .font(.caption)
                        .fontWeight(player.config.playbackRate == rate ? .bold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            player.config.playbackRate == rate
                                ? Color.accentColor.opacity(0.2)
                                : Color.gray.opacity(0.1)
                        )
                        .cornerRadius(16)
                }
                .foregroundColor(player.config.playbackRate == rate ? .accentColor : .primary)
            }
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        if rate == Float(Int(rate)) {
            return "\(Int(rate)).0x"
        }
        return "\(rate)x"
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 48) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }
            .disabled(!(player.currentPlaylist?.hasPrevious ?? false))

            Button {
                if player.state == .playing {
                    player.pause()
                } else {
                    player.play()
                }
            } label: {
                Image(systemName: playButtonIcon)
                    .font(.system(size: 60))
            }

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            .disabled(!(player.currentPlaylist?.hasNext ?? false))
        }
        .foregroundColor(.primary)
        .padding(.vertical, 8)
    }

    private var playButtonIcon: String {
        switch player.state {
        case .playing: return "pause.circle.fill"
        case .loading: return "hourglass.circle"
        default: return "play.circle.fill"
        }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        HStack(spacing: 40) {
            // 循环模式
            Button {
                cycleRepeatMode()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: repeatIcon)
                        .font(.title3)
                    Text(repeatLabel)
                        .font(.caption2)
                }
            }
            .foregroundColor(player.config.repeatMode == .none ? .secondary : .accentColor)

            // 定时关闭
            Button { showSleepTimer = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.title3)
                    if let remaining = player.sleepTimerRemaining {
                        Text(formatTime(remaining))
                            .font(.caption2)
                    } else {
                        Text("定时")
                            .font(.caption2)
                    }
                }
            }
            .foregroundColor(player.sleepTimerRemaining != nil ? .accentColor : .secondary)
            .confirmationDialog("定时关闭", isPresented: $showSleepTimer) {
                Button("15 分钟") { player.setSleepTimer(minutes: 15) }
                Button("30 分钟") { player.setSleepTimer(minutes: 30) }
                Button("60 分钟") { player.setSleepTimer(minutes: 60) }
                if player.sleepTimerRemaining != nil {
                    Button("取消定时", role: .destructive) { player.setSleepTimer(minutes: nil) }
                }
                Button("取消", role: .cancel) {}
            }

            // 段落列表
            Button { showPlaylist = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                    Text("段落")
                        .font(.caption2)
                }
            }
            .foregroundColor(.secondary)
            .sheet(isPresented: $showPlaylist) {
                playlistSheet
            }
        }
    }

    private var repeatIcon: String {
        switch player.config.repeatMode {
        case .none: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }

    private var repeatLabel: String {
        switch player.config.repeatMode {
        case .none: return "不循环"
        case .one: return "单段"
        case .all: return "列表"
        }
    }

    private func cycleRepeatMode() {
        switch player.config.repeatMode {
        case .none: player.setRepeatMode(.one)
        case .one: player.setRepeatMode(.all)
        case .all: player.setRepeatMode(.none)
        }
    }

    // MARK: - Playlist Sheet

    private var playlistSheet: some View {
        NavigationStack {
            List {
                if let playlist = player.currentPlaylist {
                    ForEach(Array(playlist.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            player.jumpTo(index: index)
                            showPlaylist = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("第 \(item.order + 1) 段")
                                        .font(.subheadline)
                                        .fontWeight(index == playlist.currentIndex ? .bold : .regular)
                                    Text(item.segment.text.prefix(50) + (item.segment.text.count > 50 ? "..." : ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if index == playlist.currentIndex {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("段落列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showPlaylist = false }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
