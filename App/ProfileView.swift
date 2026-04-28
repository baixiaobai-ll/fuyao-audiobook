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
    @State private var isSavingNickname = false
    @State private var nicknameEditError: String?
    @FocusState private var nicknameFieldFocused: Bool
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

                        if profileStore.isLoggedIn {
                            activationCenterCard
                        }

                        cacheCard
                        aboutCard

                        if profileStore.isLoggedIn {
                            logoutCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }

                if showLogoutConfirm {
                    logoutConfirmationOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(10)
                }

                if showActivationSheet {
                    activationDialogOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(9)
                }

                if showNicknameEdit {
                    nicknameEditOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(11)
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .tint(pageIndigo)
            .animation(.spring(response: 0.24, dampingFraction: 0.88), value: showLogoutConfirm)
            .animation(.spring(response: 0.24, dampingFraction: 0.88), value: showActivationSheet)
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: showNicknameEdit)
            .onAppear {
                calculateCacheSizes()
            }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerView()
                    .environmentObject(profileStore)
                    .presentationDetents([.height(520), .large])
                    .presentationDragIndicator(.visible)
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
                        subtitle: activationCenterSubtitle
                    )
                    Spacer()
                    TintedIconBadge(icon: activationCenterIcon, primary: pageBlue, secondary: pagePurple)
                }

                if !profileStore.isLoggedIn {
                    HStack(spacing: 10) {
                        CapsuleInfoTag(title: "未登录仅可用本地内容", icon: "books.vertical.fill", tint: pageBlue)
                        CapsuleInfoTag(title: "登录后再输入激活码", icon: "iphone.gen3.radiowaves.left.and.right", tint: pagePurple)
                    }

                    Button {
                        tabRouter.presentLogin()
                    } label: {
                        actionEntryRow(
                            icon: "iphone.gen3.radiowaves.left.and.right.circle.fill",
                            title: "去登录并解锁云端内容",
                            subtitle: "支持一键登录和验证码登录，登录后再输入激活码"
                        )
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                } else if activationState == .active {
                    Button {
                        presentActivationSheet(source: "reactivate")
                    } label: {
                        actionEntryRow(
                            icon: "arrow.clockwise.circle.fill",
                            title: "重新提交激活码",
                            subtitle: "如需更换激活码，可再次提交，以后端真实返回为准"
                        )
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                } else {
                    HStack(spacing: 10) {
                        CapsuleInfoTag(title: "已登录未激活", icon: "lock.fill", tint: pageBlue)
                        CapsuleInfoTag(title: "当前仅可用本地内容", icon: "books.vertical.fill", tint: pagePurple)
                    }

                    Button {
                        presentActivationSheet(source: activationState == .expired ? "expired_reactivate" : "activate")
                    } label: {
                        actionEntryRow(
                            icon: "key.fill",
                            title: activationState == .expired ? "重新激活云端能力" : "输入激活码解锁云端能力",
                            subtitle: "激活后开放发现页和云端书籍，当前仍可正常使用本地内容"
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

    private var logoutConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    showLogoutConfirm = false
                }

            VStack(spacing: 18) {
                Text("确定要退出登录吗？")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("退出后仍可使用本地内容，重新登录后会同步账号与激活状态。")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: 12) {
                    Button {
                        showLogoutConfirm = false
                    } label: {
                        Text("取消")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.88))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(pageIndigo.opacity(0.18), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.98))

                    Button(role: .destructive) {
                        showLogoutConfirm = false
                        profileStore.logout()
                    } label: {
                        Text("退出登录")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.red.opacity(0.78))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.98))
                }
            }
            .padding(22)
            .frame(maxWidth: 330)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                    .shadow(color: Color.black.opacity(0.12), radius: 30, x: 0, y: 16)
            )
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Header Views

    @ViewBuilder
    private var loggedInHeader: some View {
        HStack(spacing: 16) {
            Button {
                showAvatarPicker = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    avatarView(size: 68)

                    Image(systemName: "camera.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [pageBlue, pagePurple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
                .frame(width: 82, height: 82)
                .contentShape(Circle())
            }
            .buttonStyle(LiftPressButtonStyle(scale: 0.96))

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    presentNicknameEditor()
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profileStore.nickname)
                                .font(.title2.bold())
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)

                            Text("点击修改昵称")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(pagePurple.opacity(0.92))
                        }

                        Image(systemName: "square.and.pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(pagePurple.opacity(0.86))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(pagePurple.opacity(0.16)))
                            .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 1))
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 6)
                    .padding(.trailing, 8)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private var nicknameEditOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissNicknameEditor()
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("修改昵称")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Spacer()

                    Button {
                        dismissNicknameEditor()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.72)))
                    }
                    .buttonStyle(.plain)
                }

                TextField("输入新昵称", text: $editingNickname)
                    .focused($nicknameFieldFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.82))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(pagePurple.opacity(0.22), lineWidth: 1)
                            )
                    )

                if let nicknameEditError {
                    Text(nicknameEditError)
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    saveNicknameEdit()
                } label: {
                    HStack(spacing: 8) {
                        if isSavingNickname {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSavingNickname ? "保存中..." : "保存")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [pageBlue, pagePurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(LiftPressButtonStyle(scale: 0.98))
                .disabled(editingNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingNickname)
                .opacity(editingNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .shadow(color: Color.black.opacity(0.12), radius: 30, x: 0, y: 16)
            )
            .padding(.horizontal, 28)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                nicknameFieldFocused = true
            }
        }
    }

    private func presentNicknameEditor() {
        editingNickname = profileStore.nickname
        nicknameEditError = nil
        showNicknameEdit = true
    }

    private func dismissNicknameEditor() {
        guard !isSavingNickname else { return }
        nicknameFieldFocused = false
        showNicknameEdit = false
        nicknameEditError = nil
    }

    private func saveNicknameEdit() {
        let trimmed = editingNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSavingNickname else { return }
        isSavingNickname = true
        nicknameEditError = nil

        Task {
            do {
                let savedNickname = try await ProfileAPIClient.updateNickname(
                    trimmed,
                    sessionToken: profileStore.sessionToken
                )
                await MainActor.run {
                    profileStore.updateNickname(savedNickname)
                    isSavingNickname = false
                    dismissNicknameEditor()
                }
            } catch let error as ProfileAPIError {
                await MainActor.run {
                    nicknameEditError = error.userMessage
                    isSavingNickname = false
                }
            } catch {
                await MainActor.run {
                    nicknameEditError = error.localizedDescription
                    isSavingNickname = false
                }
            }
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
                    Text("登录账号")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("未登录只能使用本地内容；完成登录并输入激活码后，才会开放发现页和云端书籍")
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
                    value: hasCloudAccess ? "已解锁" : (activationState == .expired ? "已过期" : "待解锁"),
                    icon: hasCloudAccess ? "checkmark.shield.fill" : "lock.fill",
                    tint: pagePurple
                )
                metricTile(
                    title: "发现页",
                    value: hasCloudAccess ? "已开放" : "未开放",
                    icon: "safari.fill",
                    tint: pageBlue
                )
                metricTile(
                    title: "当前可用",
                    value: hasCloudAccess ? "本地 + 云端" : "本地内容",
                    icon: "books.vertical.fill",
                    tint: pagePurple
                )
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
                metricTile(title: "当前可用", value: "本地内容", icon: "tray.full.fill", tint: pageBlue)
                metricTile(title: "解锁方式", value: "登录 + 激活", icon: "key.fill", tint: pagePurple)
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

    private var activationDialogOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSubmittingActivation {
                        showActivationSheet = false
                    }
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("激活码")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Spacer()

                    Button {
                        showActivationSheet = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.78))
                            .clipShape(Circle())
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.94))
                    .disabled(isSubmittingActivation)
                }

                TextField("请输入激活码", text: $activationCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: activationCode) { newValue in
                        let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
                        activationCode = String(filtered.prefix(24))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.82))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(pagePurple.opacity(0.22), lineWidth: 1)
                            )
                    )
                    .disabled(!profileStore.isLoggedIn || isSubmittingActivation)

                Button {
                    Task {
                        await submitActivationCode()
                    }
                } label: {
                    Label(
                        profileStore.isLoggedIn
                            ? (isSubmittingActivation ? "激活中..." : "立即激活")
                            : "请先完成登录",
                        systemImage: profileStore.isLoggedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.plus"
                    )
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppTheme.Colors.brandGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                .disabled(!profileStore.isLoggedIn || activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingActivation)
                .opacity(!profileStore.isLoggedIn || activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingActivation ? 0.6 : 1)
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                    .shadow(color: Color.black.opacity(0.12), radius: 30, x: 0, y: 16)
            )
            .padding(.horizontal, 28)
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
                title: "请先完成登录",
                message: "当前账号未登录，仍只能使用本地内容。完成登录后再输入激活码，即可继续完成云端能力解锁。",
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
        if hasCloudAccess { return "云端能力已解锁" }
        if activationState == .expired { return "云端能力已过期" }
        return "已登录待解锁"
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
            return "当前账号已解锁云端能力，发现页与云端书籍现已开放，本地与云端内容都可以正常使用。"
        }
        if activationState == .expired {
            return "账号仍保持登录，但激活权益已过期。当前仍可继续使用本地内容，输入新激活码后可重新开放云端内容。"
        }
        return "账号已登录，但云端能力还未解锁。当前只能使用本地内容，发现页和云端书籍会继续保持锁定。"
    }

    private var activationCenterSubtitle: String {
        if !profileStore.isLoggedIn {
            return "请先完成登录，登录后才能输入激活码"
        }
        if activationState == .active {
            return "已解锁云端能力，可继续使用发现页和云端书籍"
        }
        if activationState == .expired {
            return "激活权益已过期，可重新输入激活码"
        }
        return "已登录，可输入激活码解锁云端能力"
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
            return "云端能力已解锁"
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

private enum ProfileAPIError: Error, Equatable {
    case missingBaseURL
    case missingSessionToken
    case invalidResponse(String)
    case server(String)
    case transport(String)

    var userMessage: String {
        switch self {
        case .missingBaseURL:
            return "未配置用户资料服务地址，请先检查 `AUTH_API_BASE_URL`。"
        case .missingSessionToken:
            return "当前登录态缺少会话令牌，请重新登录后再试。"
        case .invalidResponse(let message):
            return "用户资料服务返回内容无法识别：\(message)"
        case .server(let message):
            return message
        case .transport(let message):
            return message
        }
    }
}

private enum ProfileAPIClient {
    private static let updateProfilePath = "v1/profile"

    static func updateNickname(_ nickname: String, sessionToken: String?) async throws -> String {
        guard let rawSessionToken = sessionToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSessionToken.isEmpty else {
            throw ProfileAPIError.missingSessionToken
        }

        let data = try await request(
            path: updateProfilePath,
            method: "PATCH",
            sessionToken: rawSessionToken,
            jsonBody: ["nickname": nickname]
        )
        let json = try parseJSON(data)
        let user = firstObject(in: json, keys: ["user", "profile", "account"]) ?? json
        guard let savedNickname = firstString(in: user, keys: ["nickname", "nickName", "displayName", "name"]) else {
            throw ProfileAPIError.invalidResponse("缺少 user.nickname")
        }
        return savedNickname
    }

    private static func request(
        path: String,
        method: String,
        sessionToken: String,
        jsonBody: [String: Any]
    ) async throws -> Data {
        guard let base = Config.authAPIBaseURL else {
            throw ProfileAPIError.missingBaseURL
        }

        let trimmed = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, let baseURL = URL(string: trimmed) else {
            throw ProfileAPIError.missingBaseURL
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(sessionToken, forHTTPHeaderField: "X-Session-Token")
        request.setValue(sessionToken, forHTTPHeaderField: "X-Auth-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)

        print("[Profile] stage=请求后端 code=CLIENT_PROFILE_REQUEST message=\(method) \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProfileAPIError.invalidResponse("缺少 HTTP 状态码")
            }

            guard (200...299).contains(http.statusCode) else {
                let json = try? parseJSON(data)
                let message = json.flatMap {
                    firstString(in: $0, keys: ["message", "msg", "error", "errorMessage", "detail"])
                } ?? "用户资料服务返回 \(http.statusCode)"
                throw ProfileAPIError.server(message)
            }

            return data
        } catch let error as ProfileAPIError {
            throw error
        } catch let error as URLError {
            throw ProfileAPIError.transport(describeTransportError(error, url: url))
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                let code = URLError.Code(rawValue: nsError.code)
                let urlError = URLError(code)
                throw ProfileAPIError.transport(describeTransportError(urlError, url: url))
            }
            throw ProfileAPIError.transport(error.localizedDescription)
        }
    }

    private static func parseJSON(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                throw ProfileAPIError.invalidResponse(raw)
            }
            throw ProfileAPIError.invalidResponse(error.localizedDescription)
        }
    }

    private static func firstString(in value: Any, keys: [String], depth: Int = 5) -> String? {
        guard depth >= 0 else { return nil }
        if let dictionary = value as? [String: Any] {
            for key in keys {
                if let string = dictionary[key] as? String,
                   !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return string
                }
                if let number = dictionary[key] as? NSNumber {
                    return number.stringValue
                }
            }
            for nested in dictionary.values {
                if let result = firstString(in: nested, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let result = firstString(in: item, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        }
        return nil
    }

    private static func firstObject(in value: Any, keys: [String], depth: Int = 5) -> Any? {
        guard depth >= 0 else { return nil }
        if let dictionary = value as? [String: Any] {
            for key in keys {
                if let object = dictionary[key] {
                    return object
                }
            }
            for nested in dictionary.values {
                if let result = firstObject(in: nested, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let result = firstObject(in: item, keys: keys, depth: depth - 1) {
                    return result
                }
            }
        }
        return nil
    }

    private static func describeTransportError(_ error: URLError, url: URL) -> String {
        let host = url.host ?? url.absoluteString
        switch error.code {
        case .notConnectedToInternet:
            return "当前网络不可用，无法访问用户资料服务 `\(host)`。请检查手机联网状态后重试。"
        case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .timedOut:
            return "无法连接用户资料服务 `\(host)`。请确认后端服务已启动，且地址与端口可以从真机访问。"
        default:
            return "调用用户资料服务 `\(host)` 失败：\(error.localizedDescription)"
        }
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
            return "激活服务已返回结果，但当前云端能力仍未开放。"
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
