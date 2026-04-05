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
    @State private var showActivationSheet = false
    @State private var editingNickname = ""
    @State private var activationCode = ""
    @State private var activationMessage: ActivationMessage?

    private let pageBlue = Color(red: 0.52, green: 0.76, blue: 0.98)
    private let pagePurple = Color(red: 0.66, green: 0.54, blue: 0.96)
    private let pageIndigo = Color(red: 0.35, green: 0.45, blue: 0.82)

    var body: some View {
        NavigationStack {
            ZStack {
                profileBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        profileHeaderCard

                        if let activationMessage {
                            activationMessageCard(activationMessage)
                        }

                        activationCenterCard

                        cacheCard
                        aboutCard

                        if profileStore.isLoggedIn {
                            logoutCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .tint(pageIndigo)
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
            .sheet(isPresented: $showActivationSheet) {
                activationSheet
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

    private var profileBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.92, green: 0.94, blue: 1.0),
                Color(red: 0.99, green: 0.99, blue: 1.0),
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(pagePurple.opacity(0.18))
                .frame(width: 250, height: 250)
                .blur(radius: 24)
                .offset(x: 84, y: -60)
        }
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(pageBlue.opacity(0.14))
                .frame(width: 220, height: 220)
                .blur(radius: 20)
                .offset(x: -78, y: -72)
        }
        .ignoresSafeArea()
    }

    // MARK: - Cards

    private var profileHeaderCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                if profileStore.isLoggedIn {
                    loggedInHeader
                } else {
                    loggedOutHeader
                }
            }
        }
    }

    private func activationMessageCard(_ message: ActivationMessage) -> some View {
        SurfaceCard {
            HStack(spacing: 12) {
                TintedIconBadge(
                    icon: message.icon,
                    primary: message.kind == .success ? pagePurple : pageBlue,
                    secondary: pageIndigo
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(message.message)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private var activationCenterCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SoftSectionHeader(
                        title: "激活中心",
                        subtitle: "输入激活码后，可在这里承接后续会员/权益提示"
                    )
                    Spacer()
                    TintedIconBadge(icon: "ticket.fill", primary: pageBlue, secondary: pagePurple)
                }

                HStack(spacing: 10) {
                    CapsuleInfoTag(title: "今晚可先走 UI 闭环", icon: "wand.and.stars", tint: pagePurple)
                    CapsuleInfoTag(title: "后续可接正式校验", icon: "link.badge.plus", tint: pageBlue)
                }

                Button {
                    showActivationSheet = true
                } label: {
                    HStack(spacing: 10) {
                        TintedIconBadge(icon: "key.fill", size: 34, iconSize: 13, primary: pageBlue, secondary: pagePurple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("输入激活码")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text("支持后续接入激活成功、失败、过期等提示")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(pagePurple)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.72), pagePurple.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .buttonStyle(LiftPressButtonStyle(scale: 0.985))
            }
        }
    }

    private var cacheCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SoftSectionHeader(title: "缓存管理", subtitle: "把音频和分析缓存清得更明白一些")

                profileRow(title: "音频缓存", value: audioCacheSize, icon: "waveform.circle.fill", interactive: false)
                profileRow(title: "分析缓存", value: analysisCacheSize, icon: "brain.head.profile", interactive: false)

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    HStack(spacing: 12) {
                        TintedIconBadge(icon: "trash.fill", size: 34, iconSize: 13, primary: pagePurple, secondary: pageIndigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("清除所有缓存")
                                .font(.subheadline.weight(.semibold))
                            Text("会移除本地音频、分析和 TTS 缓存")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                .foregroundStyle(.red)
                .confirmationDialog("确定要清除所有缓存吗？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                    Button("清除", role: .destructive) {
                        clearAllCaches()
                    }
                    Button("取消", role: .cancel) {}
                }
            }
        }
    }

    private var aboutCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SoftSectionHeader(title: "关于扶摇", subtitle: "当前构建环境与能力概览")
                profileRow(title: "版本号", value: Config.appVersion, icon: "shippingbox.fill", interactive: false)
                profileRow(title: "AI编排引擎", value: aiProviderName, icon: "sparkles", interactive: false)
                profileRow(title: "TTS 引擎", value: ttsProviderName, icon: "waveform.and.mic", interactive: false)
            }
        }
    }

    private var logoutCard: some View {
        SurfaceCard {
            Button(role: .destructive) {
                showLogoutConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("退出登录")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Header Views

    @ViewBuilder
    private var loggedInHeader: some View {
        HStack(spacing: 16) {
            Button {
                showAvatarPicker = true
            } label: {
                avatarView(size: 64)
            }
            .buttonStyle(LiftPressButtonStyle(scale: 0.96))

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    editingNickname = profileStore.nickname
                    showNicknameEdit = true
                } label: {
                    HStack(spacing: 6) {
                        Text(profileStore.nickname)
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Image(systemName: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(pagePurple)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(profileStore.maskedPhone)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("点击头像更换头像")
                    .font(.caption)
                    .foregroundStyle(pagePurple.opacity(0.92))
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var loggedOutHeader: some View {
        Button {
            showLogin = true
        } label: {
            HStack(spacing: 16) {
                TintedIconBadge(icon: "person.fill", size: 60, iconSize: 22, primary: pageBlue, secondary: pagePurple)

                VStack(alignment: .leading, spacing: 6) {
                    Text("点击登录")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("登录后可保存头像、昵称和个性化设置")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(pagePurple)
            }
        }
        .buttonStyle(LiftPressButtonStyle(scale: 0.985))
    }

    // MARK: - Shared Rows

    private func profileRow(title: String, value: String, icon: String, interactive: Bool) -> some View {
        HStack(spacing: 12) {
            TintedIconBadge(icon: icon, size: 34, iconSize: 13, primary: pageBlue, secondary: pagePurple)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            if interactive {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(pagePurple)
            }
        }
    }

    // MARK: - Activation

    private var activationSheet: some View {
        NavigationStack {
            ZStack {
                profileBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    TintedIconBadge(icon: "ticket.fill", primary: pageBlue, secondary: pagePurple)
                                    Spacer()
                                    CapsuleInfoTag(title: "UI 已准备", icon: "wand.and.stars", tint: pagePurple)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("输入激活码")
                                        .font(.title3.bold())
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                    Text("先把输入、提示和状态反馈做完整。正式激活校验接入后，这里可以直接承接成功、失败、过期等场景。")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                            }
                        }

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("激活码")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.Colors.textPrimary)

                                TextField("请输入激活码，例如 [REMOVED_ACTIVATION_CODE]", text: $activationCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .onChange(of: activationCode) { newValue in
                                        let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
                                        activationCode = String(filtered.prefix(24))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.white.opacity(0.64))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(pagePurple.opacity(0.18), lineWidth: 1)
                                            )
                                    )

                                HStack(spacing: 8) {
                                    CapsuleInfoTag(title: "支持大写字母与数字", icon: "keyboard", tint: pageBlue)
                                    CapsuleInfoTag(title: "适配成功/失败提示", icon: "exclamationmark.bubble", tint: pagePurple)
                                }
                            }
                        }

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("激活提示预览")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                Text("提交后会先展示本地提示文案，方便今晚先验证视觉与交互流程。")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)

                                Button {
                                    submitActivationCode()
                                } label: {
                                    Label("立即激活", systemImage: "checkmark.circle.fill")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(AppTheme.Colors.brandGradient)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                                .disabled(activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .opacity(activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("激活码")
            .navigationBarTitleDisplayMode(.inline)
            .tint(pageIndigo)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showActivationSheet = false }
                }
            }
        }
    }

    private func submitActivationCode() {
        let trimmed = activationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        activationMessage = ActivationMessage(
            title: "激活码已提交",
            message: "当前版本已完成激活码输入与状态提示 UI，后续接入正式校验服务后，可直接复用这条流程。输入码：\(trimmed)",
            kind: .success
        )
        showActivationSheet = false
    }

    // MARK: - Avatar View

    @ViewBuilder
    private func avatarView(size: CGFloat) -> some View {
        switch profileStore.avatarSource {
        case .preset(let id):
            PresetAvatarCircle(presetId: id, size: size)
        case .custom:
            if let uiImage = profileStore.loadAvatarImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                PresetAvatarCircle(presetId: AvatarPresetCatalog.defaultId, size: size)
            }
        }
    }

    // MARK: - Provider Names

    private var aiProviderName: String {
        "Kimi、通义千问"
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

    // MARK: - Labels

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

private struct ActivationMessage {
    enum Kind {
        case success
        case info
    }

    let title: String
    let message: String
    let kind: Kind

    var icon: String {
        switch kind {
        case .success:
            return "checkmark.shield.fill"
        case .info:
            return "info.circle.fill"
        }
    }
}
