import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var player: AudioBookPlayer
    @EnvironmentObject var profileStore: UserProfileStore

    @State private var audioCacheSize: String = "计算中..."
    @State private var analysisCacheSize: String = "计算中..."
    @State private var showClearConfirm = false
    @State private var showLogin = false
    @State private var showAvatarPicker = false
    @State private var showNicknameEdit = false
    @State private var showLogoutConfirm = false
    @State private var editingNickname = ""

    // 预设头像颜色映射
    private let presetColors: [String: Color] = [
        "person.fill": .blue,
        "star.fill": .orange,
        "heart.fill": .pink,
        "leaf.fill": .green,
        "flame.fill": .red,
        "book.fill": .purple,
        "music.note": .teal,
        "gamecontroller.fill": .indigo,
    ]

    var body: some View {
        NavigationStack {
            List {
                // 头部用户信息
                Section {
                    if profileStore.isLoggedIn {
                        loggedInHeader
                    } else {
                        loggedOutHeader
                    }
                }

                // 账号信息（已登录）
                if profileStore.isLoggedIn {
                    Section("账号") {
                        // 昵称
                        Button {
                            editingNickname = profileStore.nickname
                            showNicknameEdit = true
                        } label: {
                            HStack {
                                Text("昵称")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(profileStore.nickname)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 手机号
                        HStack {
                            Text("手机号")
                            Spacer()
                            Text(profileStore.maskedPhone)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 播放设置
                Section("播放设置") {
                    HStack {
                        Text("默认倍速")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { player.config.playbackRate },
                            set: { player.setPlaybackRate($0) }
                        )) {
                            Text("0.75x").tag(Float(0.75))
                            Text("1.0x").tag(Float(1.0))
                            Text("1.25x").tag(Float(1.25))
                            Text("1.5x").tag(Float(1.5))
                            Text("2.0x").tag(Float(2.0))
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle("自动连播", isOn: Binding(
                        get: { player.config.enableAutoNext },
                        set: { player.config.enableAutoNext = $0 }
                    ))

                    HStack {
                        Text("循环模式")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { player.config.repeatMode },
                            set: { player.setRepeatMode($0) }
                        )) {
                            Text("不循环").tag(PlaybackConfig.RepeatMode.none)
                            Text("单段循环").tag(PlaybackConfig.RepeatMode.one)
                            Text("列表循环").tag(PlaybackConfig.RepeatMode.all)
                        }
                        .pickerStyle(.menu)
                    }
                }

                // 缓存管理
                Section("缓存管理") {
                    HStack {
                        Text("音频缓存")
                        Spacer()
                        Text(audioCacheSize)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("分析缓存")
                        Spacer()
                        Text(analysisCacheSize)
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("清除所有缓存")
                        }
                    }
                    .confirmationDialog("确定要清除所有缓存吗？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                        Button("清除", role: .destructive) {
                            clearAllCaches()
                        }
                        Button("取消", role: .cancel) {}
                    }
                }

                // 关于
                Section("关于") {
                    HStack {
                        Text("版本号")
                        Spacer()
                        Text(Config.appVersion)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("AI 引擎")
                        Spacer()
                        Text(aiProviderName)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("TTS 引擎")
                        Spacer()
                        Text(ttsProviderName)
                            .foregroundColor(.secondary)
                    }
                }

                // 退出登录
                if profileStore.isLoggedIn {
                    Section {
                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("退出登录")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                calculateCacheSizes()
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
                    .environmentObject(profileStore)
            }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerView()
                    .environmentObject(profileStore)
            }
            .alert("修改昵称", isPresented: $showNicknameEdit) {
                TextField("输入新昵称", text: $editingNickname)
                Button("保存") {
                    let trimmed = editingNickname.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        profileStore.updateNickname(trimmed)
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("确定要退出登录吗？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    profileStore.logout()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - Header Views

    @ViewBuilder
    private var loggedInHeader: some View {
        HStack(spacing: 16) {
            // 头像（可点击更换）
            Button {
                showAvatarPicker = true
            } label: {
                avatarView(size: 56)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profileStore.nickname)
                    .font(.title2)
                    .bold()
                    .foregroundColor(.primary)
                Text(profileStore.maskedPhone)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var loggedOutHeader: some View {
        Button {
            showLogin = true
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
                VStack(alignment: .leading, spacing: 4) {
                    Text("点击登录")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.primary)
                    Text("登录后享受完整体验")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Avatar View

    @ViewBuilder
    private func avatarView(size: CGFloat) -> some View {
        switch profileStore.avatarSource {
        case .preset(let symbol):
            let color = presetColors[symbol] ?? .blue
            Image(systemName: symbol)
                .font(.system(size: size * 0.45))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(color)
                .clipShape(Circle())
        case .custom:
            if let uiImage = profileStore.loadAvatarImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundColor(.white)
                    .frame(width: size, height: size)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Provider Names

    private var aiProviderName: String {
        switch Config.aiProvider {
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .qwen: return "通义千问"
        }
    }

    private var ttsProviderName: String {
        switch Config.ttsProvider {
        case .openai: return "OpenAI"
        case .azure: return "Azure"
        case .aliyun: return "阿里云"
        case .xfyun: return "科大讯飞"
        case .local: return "本地"
        }
    }

    // MARK: - Cache Management

    private func calculateCacheSizes() {
        DispatchQueue.global(qos: .utility).async {
            let audioSize = directorySize(at: player.audioCacheDirectory)
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let analysisDir = documentsURL.appendingPathComponent("AnalysisCache")
            let analysisSize = directorySize(at: analysisDir)

            DispatchQueue.main.async {
                audioCacheSize = formatBytes(audioSize)
                analysisCacheSize = formatBytes(analysisSize)
            }
        }
    }

    private func clearAllCaches() {
        let fm = FileManager.default

        let audioCacheDir = player.audioCacheDirectory
        try? fm.removeItem(at: audioCacheDir)
        try? fm.createDirectory(at: audioCacheDir, withIntermediateDirectories: true)

        let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let analysisDir = documentsURL.appendingPathComponent("AnalysisCache")
        try? fm.removeItem(at: analysisDir)
        try? fm.createDirectory(at: analysisDir, withIntermediateDirectories: true)

        let ttsDir = documentsURL.appendingPathComponent("TTSCache")
        try? fm.removeItem(at: ttsDir)
        try? fm.createDirectory(at: ttsDir, withIntermediateDirectories: true)

        calculateCacheSizes()
    }

    private func directorySize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
