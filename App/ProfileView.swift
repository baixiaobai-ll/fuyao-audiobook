import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var player: AudioBookPlayer
    @EnvironmentObject var profileStore: UserProfileStore
    @EnvironmentObject var tabRouter: MainTabRouter

    @State private var audioCacheSize: String = "计算中..."
    @State private var analysisCacheSize: String = "计算中..."
    @State private var showClearConfirm = false
    @State private var showAvatarPicker = false
    @State private var showNicknameEdit = false
    @State private var showLogoutConfirm = false
    @State private var showActivationSheet = false
    @State private var editingNickname = ""
    @State private var activationCode = ""
    @State private var activationMessage: ActivationMessage?
    @State private var isSubmittingActivation = false
    @AppStorage("fuyao_activation_status") private var activationStatusRaw = ActivationState.inactive.rawValue
    @AppStorage("fuyao_activation_plan_name") private var activationPlanName = "扶摇云端畅听"
    @AppStorage("fuyao_activation_remaining_quota") private var activationRemainingQuota = 0
    @AppStorage("fuyao_activation_expiry_text") private var activationExpiryText = ""
    @AppStorage("fuyao_activation_last_code") private var activationLastCode = ""
    @AppStorage("fuyao_daily_quota_total") private var dailyQuotaTotal = 120
    @AppStorage("fuyao_daily_quota_used") private var dailyQuotaUsed = 0
    @AppStorage("fuyao_daily_quota_reset_text") private var dailyQuotaResetText = "每日 00:00 重置"

    private let pageBlue = Color(red: 0.52, green: 0.76, blue: 0.98)
    private let pagePurple = Color(red: 0.66, green: 0.54, blue: 0.96)
    private let pageIndigo = Color(red: 0.35, green: 0.45, blue: 0.82)

    private enum ActivationState: String {
        case inactive
        case active
        case expired
    }

    private var activationState: ActivationState {
        ActivationState(rawValue: activationStatusRaw) ?? .inactive
    }

    private var hasCloudAccess: Bool {
        profileStore.isLoggedIn && activationState == .active
    }

    private var dailyQuotaRemaining: Int {
        max(dailyQuotaTotal - dailyQuotaUsed, 0)
    }

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
        SurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                if profileStore.isLoggedIn {
                    loggedInHeader
                    Divider().overlay(AppTheme.Colors.divider.opacity(0.45))
                    accessSummary
                } else {
                    loggedOutHeader
                    Divider().overlay(AppTheme.Colors.divider.opacity(0.45))
                    guestAccessSummary
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
                        subtitle: activationCenterSubtitle
                    )
                    Spacer()
                    TintedIconBadge(icon: activationCenterIcon, primary: pageBlue, secondary: pagePurple)
                }

                if !profileStore.isLoggedIn {
                    HStack(spacing: 10) {
                        CapsuleInfoTag(title: "未登录仅可用本地书籍", icon: "books.vertical.fill", tint: pageBlue)
                        CapsuleInfoTag(title: "一键登录后可继续激活", icon: "iphone.gen3.radiowaves.left.and.right", tint: pagePurple)
                    }

                    Button {
                        tabRouter.presentLogin()
                    } label: {
                        actionEntryRow(
                            icon: "iphone.gen3.radiowaves.left.and.right.circle.fill",
                            title: "先完成一键登录",
                            subtitle: "登录后才能输入激活码，解锁发现页和云端书籍"
                        )
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                } else if activationState == .active {
                    HStack(spacing: 10) {
                        CapsuleInfoTag(title: activationPlanName, icon: "sparkles", tint: pagePurple)
                        CapsuleInfoTag(title: "今日剩余 \(dailyQuotaRemaining) 章", icon: "headphones", tint: pageBlue)
                    }

                    LazyVGrid(columns: summaryColumns, spacing: 12) {
                        metricTile(title: "每日额度", value: "\(dailyQuotaTotal) 章/天", icon: "waveform", tint: pageBlue)
                        metricTile(title: "今日剩余", value: "\(dailyQuotaRemaining) 章", icon: "headphones", tint: pagePurple)
                        metricTile(title: "今日已用", value: "\(dailyQuotaUsed) 章", icon: "chart.bar.fill", tint: pageBlue)
                        metricTile(title: "有效期至", value: activationExpiryText, icon: "calendar", tint: pagePurple)
                    }

                    Button {
                        presentActivationSheet(source: "reactivate")
                    } label: {
                        actionEntryRow(
                            icon: "arrow.clockwise.circle.fill",
                            title: "重新输入激活码",
                            subtitle: "重新提交到激活服务，以后端真实返回为准"
                        )
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                } else {
                    HStack(spacing: 10) {
                        CapsuleInfoTag(title: "已登录未激活", icon: "lock.fill", tint: pageBlue)
                        CapsuleInfoTag(title: "发现页与云端书籍待解锁", icon: "sparkles", tint: pagePurple)
                    }

                    HStack(spacing: 12) {
                        metricTile(title: "当前可用", value: "本地书籍", icon: "books.vertical.fill", tint: pageBlue)
                        metricTile(title: "云端状态", value: activationState == .expired ? "已过期" : "待激活", icon: "key.fill", tint: pagePurple)
                    }

                    Button {
                        presentActivationSheet(source: activationState == .expired ? "expired_reactivate" : "activate")
                    } label: {
                        actionEntryRow(
                            icon: "key.fill",
                            title: activationState == .expired ? "重新激活云端权限" : "输入激活码",
                            subtitle: "激活后开放发现页和云端书籍，当前仍可正常使用本地书籍"
                        )
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                }
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
            tabRouter.presentLogin()
        } label: {
            HStack(spacing: 16) {
                TintedIconBadge(icon: "person.fill", size: 60, iconSize: 22, primary: pageBlue, secondary: pagePurple)

                VStack(alignment: .leading, spacing: 6) {
                    Text("点击登录")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("未登录只能使用本地书籍；登录并激活后可解锁发现页和云端书籍")
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

    private var accessSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CapsuleInfoTag(title: "已登录", icon: "person.fill.checkmark", tint: pageBlue)
                CapsuleInfoTag(title: accessStatusTitle, icon: accessStatusIcon, tint: accessStatusTint)
                if hasCloudAccess {
                    CapsuleInfoTag(title: activationPlanName, icon: "sparkles", tint: pagePurple)
                }
            }

            Text(accessStatusDescription)
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            LazyVGrid(columns: summaryColumns, spacing: 12) {
                metricTile(
                    title: "登录状态",
                    value: "已登录",
                    icon: "person.fill.checkmark",
                    tint: pageBlue
                )
                metricTile(
                    title: "激活状态",
                    value: hasCloudAccess ? "已激活" : (activationState == .expired ? "已过期" : "待激活"),
                    icon: hasCloudAccess ? "checkmark.shield.fill" : "lock.fill",
                    tint: pagePurple
                )
                metricTile(
                    title: "每日额度",
                    value: hasCloudAccess ? "\(dailyQuotaTotal) 章/天" : "激活后开放",
                    icon: "waveform",
                    tint: pageBlue
                )
                metricTile(
                    title: "今日剩余",
                    value: hasCloudAccess ? "\(dailyQuotaRemaining) 章" : "0 章",
                    icon: "headphones",
                    tint: pagePurple
                )
            }

            if hasCloudAccess {
                Text(dailyQuotaResetText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private var guestAccessSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CapsuleInfoTag(title: "本地模式", icon: "books.vertical.fill", tint: pageBlue)
                CapsuleInfoTag(title: "发现页需登录并激活", icon: "sparkles", tint: pagePurple)
            }

            Text("当前账号未登录，书架内的本地导入内容可继续使用；公开来源和云端书籍会保持锁定。")
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 12) {
                metricTile(title: "当前可用", value: "本地书籍", icon: "tray.full.fill", tint: pageBlue)
                metricTile(title: "解锁方式", value: "一键登录 + 激活", icon: "key.fill", tint: pagePurple)
            }
        }
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
                                    CapsuleInfoTag(title: profileStore.isLoggedIn ? "可直接输入激活码" : "需先完成一键登录", icon: "wand.and.stars", tint: pagePurple)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("输入激活码")
                                        .font(.title3.bold())
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                    Text(profileStore.isLoggedIn ? "提交后会真实调用激活兑换接口，成功与失败都以后端返回为准。" : "请先完成一键登录。登录后才能激活云端权限，开放发现页和云端书籍。")
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
                                    .disabled(!profileStore.isLoggedIn)
                                    .opacity(profileStore.isLoggedIn ? 1 : 0.68)

                                HStack(spacing: 8) {
                                    CapsuleInfoTag(title: "支持大写字母与数字", icon: "keyboard", tint: pageBlue)
                                    CapsuleInfoTag(title: "提交后真实兑换", icon: "network", tint: pagePurple)
                                }

                                Text("输入后会调用后端兑换接口，并同步本地登录态、激活态与额度信息。")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)

                                if profileStore.isLoggedIn {
                                    LazyVGrid(columns: summaryColumns, spacing: 12) {
                                        metricTile(title: "登录状态", value: "已登录", icon: "person.fill.checkmark", tint: pageBlue)
                                        metricTile(title: "激活状态", value: hasCloudAccess ? "已激活" : (activationState == .expired ? "已过期" : "待激活"), icon: hasCloudAccess ? "checkmark.shield.fill" : "lock.fill", tint: pagePurple)
                                        metricTile(title: "每日额度", value: hasCloudAccess ? "\(dailyQuotaTotal) 章/天" : "激活后开放", icon: "waveform", tint: pageBlue)
                                        metricTile(title: "今日剩余", value: hasCloudAccess ? "\(dailyQuotaRemaining) 章" : "0 章", icon: "headphones", tint: pagePurple)
                                    }
                                }
                            }
                        }

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("提交激活请求")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                Text("点击按钮后会立即发起真实网络请求，结果以后端返回为准。")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)

                                Button {
                                    Task {
                                        await submitActivationCode()
                                    }
                                } label: {
                                    Label(
                                        profileStore.isLoggedIn
                                            ? (isSubmittingActivation ? "激活中..." : "立即激活")
                                            : "请先完成一键登录",
                                        systemImage: profileStore.isLoggedIn ? "checkmark.circle.fill" : "iphone.gen3.radiowaves.left.and.right"
                                    )
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(AppTheme.Colors.brandGradient)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                                .disabled(!profileStore.isLoggedIn || activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingActivation)
                                .opacity(!profileStore.isLoggedIn || activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingActivation ? 0.6 : 1)
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

    private func presentActivationSheet(source: String) {
        logActivation(
            stage: "激活入口",
            code: "CLIENT_ACTIVATION_ENTRY",
            message: "source=\(source) loggedIn=\(profileStore.isLoggedIn ? "YES" : "NO") activation=\(activationStatusRaw)"
        )
        showActivationSheet = true
    }

    private func submitActivationCode() async {
        let trimmed = activationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSubmittingActivation else { return }
        guard profileStore.isLoggedIn else {
            activationMessage = ActivationMessage(
                title: "请先完成一键登录",
                message: "当前账号未登录，仍只能使用本地书籍。完成一键登录后再输入激活码，即可继续完成云端权限解锁。",
                kind: .info
            )
            logActivation(
                stage: "激活结果",
                code: "CLIENT_ACTIVATION_BLOCKED",
                message: "未登录，已阻止激活请求。"
            )
            showActivationSheet = false
            return
        }
        guard !trimmed.isEmpty else { return }

        let normalized = trimmed.uppercased()
        activationLastCode = normalized
        isSubmittingActivation = true
        logActivation(
            stage: "提交兑换",
            code: "CLIENT_ACTIVATION_SUBMIT",
            message: "准备提交真实激活请求，code=\(normalized)"
        )

        defer { isSubmittingActivation = false }

        do {
            let payload = try await ActivationCodeAPIClient.redeem(
                code: normalized,
                sessionToken: profileStore.sessionToken
            )

            profileStore.applyActivationSuccess(
                activationStatusRaw: payload.activationStatusRaw,
                activationPlanName: payload.activationPlanName,
                dailyQuotaTotal: payload.dailyQuotaTotal,
                dailyQuotaUsed: payload.dailyQuotaUsed,
                dailyQuotaRemaining: payload.dailyQuotaRemaining,
                dailyQuotaResetText: payload.dailyQuotaResetText,
                activationExpiryText: payload.activationExpiryText
            )

            activationMessage = ActivationMessage(
                title: activationMessageTitle(for: payload.activationStatusRaw),
                message: payload.message,
                kind: payload.activationStatusRaw == ActivationState.active.rawValue ? .success : .info
            )

            logActivation(
                stage: "激活结果",
                code: "CLIENT_ACTIVATION_SUCCESS",
                message: "status=\(payload.activationStatusRaw) plan=\(payload.activationPlanName ?? "-") quotaRemaining=\(payload.dailyQuotaRemaining.map(String.init) ?? "-")"
            )

            activationCode = ""
            showActivationSheet = false
        } catch let error as ActivationCodeAPIError {
            activationMessage = ActivationMessage(
                title: "激活失败",
                message: error.userMessage,
                kind: .info
            )
            logActivation(
                stage: "激活结果",
                code: "CLIENT_ACTIVATION_ERROR",
                message: error.userMessage
            )
            showActivationSheet = false
        } catch {
            activationMessage = ActivationMessage(
                title: "激活失败",
                message: error.localizedDescription,
                kind: .info
            )
            logActivation(
                stage: "激活结果",
                code: "CLIENT_ACTIVATION_ERROR",
                message: error.localizedDescription
            )
            showActivationSheet = false
        }
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

    private var accessStatusTitle: String {
        if hasCloudAccess { return "云端已激活" }
        if activationState == .expired { return "云端已过期" }
        return "已登录待激活"
    }

    private var accessStatusIcon: String {
        if hasCloudAccess { return "checkmark.shield.fill" }
        if activationState == .expired { return "clock.arrow.circlepath" }
        return "lock.fill"
    }

    private var accessStatusTint: Color {
        hasCloudAccess ? pagePurple : pageBlue
    }

    private var accessStatusDescription: String {
        if hasCloudAccess {
            return "当前账号已解锁发现页与云端书籍，每日额度、今日剩余和有效期以后端权益返回为准。"
        }
        if activationState == .expired {
            return "账号仍保持登录，但激活权益已过期。当前仍可继续使用本地书籍，输入新激活码后可重新开放云端内容。"
        }
        return "账号已登录，但还未激活。当前只能使用本地书籍，发现页和云端书籍会继续保持锁定。"
    }

    private var activationCenterSubtitle: String {
        if !profileStore.isLoggedIn {
            return "请先完成一键登录，登录后才能输入激活码"
        }
        if activationState == .active {
            return "已解锁发现页和云端书籍，可继续查看每日额度与有效期"
        }
        if activationState == .expired {
            return "激活权益已过期，可重新输入激活码"
        }
        return "已登录，可输入激活码解锁发现页和云端书籍"
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private var activationCenterIcon: String {
        if !profileStore.isLoggedIn { return "lock.fill" }
        if activationState == .active { return "sparkles" }
        return "ticket.fill"
    }

    private func metricTile(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TintedIconBadge(icon: icon, size: 30, iconSize: 11, primary: pageBlue, secondary: pagePurple)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.74), tint.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.64), lineWidth: 1)
                )
        )
    }

    private func actionEntryRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            TintedIconBadge(icon: icon, size: 34, iconSize: 13, primary: pageBlue, secondary: pagePurple)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
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

    private func activationMessageTitle(for status: String) -> String {
        switch ActivationState(rawValue: status) ?? .inactive {
        case .active:
            return "云端权限已激活"
        case .expired:
            return "激活权益已过期"
        case .inactive:
            return "激活结果已返回"
        }
    }

    private func logActivation(stage: String, code: String, message: String) {
        print("[Activation] stage=\(stage) code=\(code) message=\(message)")
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

private struct ActivationRedeemPayload {
    let activationStatusRaw: String
    let activationPlanName: String?
    let dailyQuotaTotal: Int?
    let dailyQuotaUsed: Int?
    let dailyQuotaRemaining: Int?
    let dailyQuotaResetText: String?
    let activationExpiryText: String?
    let message: String
}

private enum ActivationCodeAPIError: Error {
    case missingBaseURL
    case missingSessionToken
    case invalidResponse(String)
    case server(String)
    case transport(String)

    var userMessage: String {
        switch self {
        case .missingBaseURL:
            return "未配置激活服务地址，请先检查 `AUTH_API_BASE_URL`。"
        case .missingSessionToken:
            return "当前登录态缺少会话令牌，请重新登录后再试。"
        case .invalidResponse(let message):
            return "激活服务返回内容无法识别：\(message)"
        case .server(let message):
            return message
        case .transport(let message):
            return message
        }
    }
}

private enum ActivationCodeAPIClient {
    private static let redeemPath = "v1/activation/redeem"

    static func redeem(code: String, sessionToken: String?) async throws -> ActivationRedeemPayload {
        guard let rawSessionToken = sessionToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSessionToken.isEmpty else {
            throw ActivationCodeAPIError.missingSessionToken
        }

        let body: [String: Any] = [
            "activationCode": code,
            "activation_code": code,
            "code": code,
            "redeemCode": code,
            "redeem_code": code
        ]

        let data = try await request(
            path: redeemPath,
            sessionToken: rawSessionToken,
            jsonBody: body
        )
        let json = try parseJSON(data)
        logResponseShape(json)
        return parsePayload(from: json)
    }

    private static func request(
        path: String,
        sessionToken: String,
        jsonBody: [String: Any]
    ) async throws -> Data {
        guard let base = Config.authAPIBaseURL else {
            throw ActivationCodeAPIError.missingBaseURL
        }

        let trimmed = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, let baseURL = URL(string: trimmed) else {
            throw ActivationCodeAPIError.missingBaseURL
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(sessionToken, forHTTPHeaderField: "X-Session-Token")
        request.setValue(sessionToken, forHTTPHeaderField: "X-Auth-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)

        print("[Activation] stage=请求后端 code=CLIENT_ACTIVATION_REQUEST message=POST \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ActivationCodeAPIError.invalidResponse("缺少 HTTP 状态码")
            }

            guard (200...299).contains(http.statusCode) else {
                let json = try? parseJSON(data)
                let message = json.flatMap {
                    firstString(in: $0, keys: ["message", "msg", "error", "errorMessage", "detail"])
                } ?? "激活服务返回 \(http.statusCode)"
                throw ActivationCodeAPIError.server(message)
            }

            return data
        } catch let error as ActivationCodeAPIError {
            throw error
        } catch let error as URLError {
            throw ActivationCodeAPIError.transport(describeTransportError(error, url: url))
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                let urlError = URLError(URLError.Code(rawValue: nsError.code))
                throw ActivationCodeAPIError.transport(describeTransportError(urlError, url: url))
            }
            throw ActivationCodeAPIError.transport(error.localizedDescription)
        }
    }

    private static func parsePayload(from json: Any) -> ActivationRedeemPayload {
        let entitlement = firstObject(in: json, keys: ["entitlement", "member", "membership", "plan", "rights"]) ?? json
        let permissions = firstObject(in: json, keys: ["permissions", "perms", "abilities"]) ?? json
        let quota = firstObject(in: entitlement, keys: ["dailyQuota", "quota", "quotaInfo", "usage"]) ?? entitlement
        let activatedAt = firstString(in: entitlement, keys: ["activatedAt", "activationAt", "activated_at"])
        let usageDay = firstString(in: quota, keys: ["usageDay", "usageDate", "day"])

        let activationStatusRaw = normalizeActivationStatus(
            raw: firstString(in: entitlement, keys: ["activationStatus", "status", "state", "memberStatus"])
                ?? firstString(in: json, keys: ["activationStatus", "status", "state", "memberStatus"]),
            permissions: permissions,
            root: json
        )

        let message = firstString(in: json, keys: ["message", "msg", "detail", "errorMessage"])
            ?? defaultMessage(for: activationStatusRaw)

        let payload = ActivationRedeemPayload(
            activationStatusRaw: activationStatusRaw,
            activationPlanName: firstString(in: entitlement, keys: ["activationPlanName", "planName", "name", "title", "planTitle"]),
            dailyQuotaTotal: firstInt(in: quota, keys: ["dailyQuotaTotal", "quotaTotal", "total", "limit", "dailyLimit", "dailyChapterLimit", "chapterLimit"]),
            dailyQuotaUsed: firstInt(in: quota, keys: ["dailyQuotaUsed", "quotaUsed", "used", "consumed", "usedToday", "todayUsed"]),
            dailyQuotaRemaining: firstInt(in: quota, keys: ["dailyQuotaRemaining", "quotaRemaining", "remaining", "rest", "remainingToday", "todayRemaining"]),
            dailyQuotaResetText: firstString(in: quota, keys: ["dailyQuotaResetText", "resetText", "resetAt", "refreshAt"]) ?? usageDay.map { "统计日：\($0)" },
            activationExpiryText: firstString(in: entitlement, keys: ["activationExpiryText", "expireAt", "expiredAt", "expiryDate", "validUntil"]),
            message: message
        )

        print(
            "[Activation] stage=后端解析 code=CLIENT_ACTIVATION_PARSED message=status=\(payload.activationStatusRaw) plan=\(payload.activationPlanName ?? "-") total=\(payload.dailyQuotaTotal.map(String.init) ?? "-") used=\(payload.dailyQuotaUsed.map(String.init) ?? "-") remaining=\(payload.dailyQuotaRemaining.map(String.init) ?? "-") expiry=\(payload.activationExpiryText ?? "-") activatedAt=\(activatedAt ?? "-") usageDay=\(usageDay ?? "-")"
        )

        return payload
    }

    private static func defaultMessage(for status: String) -> String {
        switch status {
        case "active":
            return "激活码兑换成功，发现页和云端书籍已解锁。"
        case "expired":
            return "激活服务已返回过期结果，请更换新的激活码。"
        default:
            return "激活服务已返回结果，但当前云端权限仍未开放。"
        }
    }

    private static func describeTransportError(_ error: URLError, url: URL) -> String {
        let host = url.host ?? url.absoluteString

        switch error.code {
        case .notConnectedToInternet:
            return "无法连接激活服务 `\(host)`，当前网络不可用，请检查手机联网状态后重试。"
        case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .timedOut:
            return "无法连接激活服务 `\(host)`。请确认后端服务已启动，地址和端口可从手机访问。"
        default:
            return "调用激活服务 `\(host)` 失败：\(error.localizedDescription)"
        }
    }

    private static func parseJSON(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                throw ActivationCodeAPIError.invalidResponse(raw)
            }
            throw ActivationCodeAPIError.invalidResponse(error.localizedDescription)
        }
    }

    private static func logResponseShape(_ value: Any) {
        let top = summarizeKeys(in: value)
        let data = firstObject(in: value, keys: ["data", "result", "payload", "response"])
        let entitlement = firstObject(in: value, keys: ["entitlement", "member", "membership", "plan", "rights"])
        let quota = firstObject(in: value, keys: ["dailyQuota", "quota", "quotaInfo", "usage"])

        let message = [
            "top=\(top)",
            "data=\(summarizeKeys(in: data as Any))",
            "entitlement=\(summarizeKeys(in: entitlement as Any))",
            "quota=\(summarizeKeys(in: quota as Any))"
        ].joined(separator: " ")

        print("[Activation] stage=后端返回 code=CLIENT_ACTIVATION_RESPONSE_SHAPE message=\(message)")
    }

    private static func summarizeKeys(in value: Any) -> String {
        guard let dict = value as? [String: Any], !dict.isEmpty else { return "-" }
        let keys = dict.keys.sorted()
        return keys.joined(separator: ",")
    }

    private static func normalizeActivationStatus(raw: String?, permissions: Any, root: Any) -> String {
        if let raw {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "active", "activated", "valid", "enabled", "success":
                return "active"
            case "expired", "expire", "invalid":
                return "expired"
            case "inactive", "pending", "locked", "none":
                return "inactive"
            default:
                break
            }
        }

        let permissionKeys = [
            "canUseDiscover", "discoverEnabled", "canUseCloudBooks", "cloudBooksEnabled",
            "canUseRemoteBooks", "cloudEnabled", "activated", "isActivated", "hasCloudAccess"
        ]
        if let hasCloudAccess = firstBool(in: permissions, keys: permissionKeys)
            ?? firstBool(in: root, keys: permissionKeys) {
            return hasCloudAccess ? "active" : "inactive"
        }
        return "inactive"
    }

    private static func firstObject(in value: Any, keys: [String], depth: Int = 4) -> Any? {
        guard depth >= 0 else { return nil }

        if let dict = value as? [String: Any] {
            for key in keys {
                if let nested = dict[key] {
                    return nested
                }
            }

            for nestedKey in ["data", "result", "payload", "response"] {
                if let nested = dict[nestedKey],
                   let result = firstObject(in: nested, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        }

        return nil
    }

    private static func firstString(in value: Any, keys: [String], depth: Int = 5) -> String? {
        guard depth >= 0 else { return nil }

        if let dict = value as? [String: Any] {
            for key in keys {
                if let raw = dict[key] as? String,
                   !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let raw = dict[key] as? NSNumber {
                    return raw.stringValue
                }
            }

            for nestedKey in ["data", "result", "model", "payload", "user", "userInfo", "account", "profile", "entitlement", "permissions", "quota"] {
                if let nested = dict[nestedKey],
                   let result = firstString(in: nested, keys: keys, depth: depth - 1) {
                    return result
                }
            }

            for nested in dict.values {
                if let result = firstString(in: nested, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let result = firstString(in: item, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        }

        return nil
    }

    private static func firstInt(in value: Any, keys: [String], depth: Int = 5) -> Int? {
        guard depth >= 0 else { return nil }

        if let dict = value as? [String: Any] {
            for key in keys {
                if let raw = dict[key] as? Int {
                    return raw
                }
                if let raw = dict[key] as? Double {
                    return Int(raw)
                }
                if let raw = dict[key] as? NSNumber {
                    return raw.intValue
                }
                if let raw = dict[key] as? String, let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return value
                }
            }

            for nestedKey in ["data", "result", "model", "payload", "entitlement", "quota", "usage"] {
                if let nested = dict[nestedKey],
                   let result = firstInt(in: nested, keys: keys, depth: depth - 1) {
                    return result
                }
            }

            for nested in dict.values {
                if let result = firstInt(in: nested, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let result = firstInt(in: item, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        }

        return nil
    }

    private static func firstBool(in value: Any, keys: [String], depth: Int = 5) -> Bool? {
        guard depth >= 0 else { return nil }

        if let dict = value as? [String: Any] {
            for key in keys {
                if let raw = dict[key] as? Bool {
                    return raw
                }
                if let raw = dict[key] as? NSNumber {
                    return raw.boolValue
                }
                if let raw = dict[key] as? String {
                    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "true", "1", "yes", "y", "enabled", "active":
                        return true
                    case "false", "0", "no", "n", "disabled", "inactive":
                        return false
                    default:
                        break
                    }
                }
            }

            for nestedKey in ["data", "result", "payload", "permissions", "entitlement", "user"] {
                if let nested = dict[nestedKey],
                   let result = firstBool(in: nested, keys: keys, depth: depth - 1) {
                    return result
                }
            }

            for nested in dict.values {
                if let result = firstBool(in: nested, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let result = firstBool(in: item, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        }

        return nil
    }
}
