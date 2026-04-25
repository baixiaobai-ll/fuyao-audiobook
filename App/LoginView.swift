import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ATAuthSDK)
import ATAuthSDK
#endif

struct LoginView: View {
    @EnvironmentObject var profileStore: UserProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var authPhase: OneClickAuthPhase = .idle
    @State private var loginNotice: LoginNotice?
    @State private var sdkEventHistory: [OneClickSDKEvent] = []
    @State private var resolvedPresenter: UIViewController?

    private let pageBlue = Color(red: 0.52, green: 0.76, blue: 0.98)
    private let pagePurple = Color(red: 0.66, green: 0.54, blue: 0.96)
    private let pageIndigo = Color(red: 0.35, green: 0.45, blue: 0.82)

    var body: some View {
        NavigationStack {
            ZStack {
                loginBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        heroCard

                        if let loginNotice {
                            statusCard(loginNotice)
                        }

                        authEntryCard
                        flowCard
                        tipsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .background(
                LoginPresenterResolver { controller in
                    resolvedPresenter = controller
                }
                .allowsHitTesting(false)
            )
            .navigationBarTitleDisplayMode(.inline)
            .tint(pageIndigo)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var loginBackground: some View {
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
                .frame(width: 220, height: 220)
                .blur(radius: 22)
                .offset(x: 72, y: -56)
        }
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(pageBlue.opacity(0.14))
                .frame(width: 190, height: 190)
                .blur(radius: 20)
                .offset(x: -68, y: -72)
        }
        .ignoresSafeArea()
    }

    private var heroCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    TintedIconBadge(icon: "iphone.gen3.radiowaves.left.and.right", size: 54, iconSize: 20, primary: pageBlue, secondary: pagePurple)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("号码认证一键登录")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text("使用阿里云号码认证 SDK 获取 `accessToken`，再调用后端 `POST /v1/auth/one-click/login` 完成登录。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                HStack(spacing: 8) {
                    CapsuleInfoTag(title: "未登录仅可用本地书籍", icon: "books.vertical.fill", tint: pageBlue)
                    CapsuleInfoTag(title: "登录后仍需激活码", icon: "key.fill", tint: pagePurple)
                }
            }
        }
    }

    private func statusCard(_ notice: LoginNotice) -> some View {
        SurfaceCard {
            HStack(spacing: 12) {
                TintedIconBadge(
                    icon: notice.kind == .success ? "checkmark.shield.fill" : "bolt.horizontal.circle.fill",
                    size: 38,
                    iconSize: 14,
                    primary: notice.kind == .success ? pagePurple : pageBlue,
                    secondary: pageIndigo
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(notice.message)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private var authEntryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                SoftSectionHeader(title: "一键登录入口", subtitle: "号码认证 SDK 先取 accessToken，再交给后端换取会话")

                HStack(spacing: 12) {
                    authMetric(title: "当前链路", value: "号码认证", icon: "lock.iphone")
                    authMetric(title: "状态", value: authPhase.displayText, icon: authPhase.icon)
                }

                Button {
                    startOneClickLogin()
                } label: {
                    HStack(spacing: 10) {
                        if authPhase.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "iphone.gen3.radiowaves.left.and.right.circle.fill")
                                .font(.headline)
                        }

                        Text(authPhase.buttonTitle)
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.Colors.brandGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(LiftPressButtonStyle(scale: 0.985))
                .disabled(authPhase.isLoading)
                .opacity(authPhase.isLoading ? 0.78 : 1)

                if authPhase == .fallbackOptions {
                    fallbackFlowCard
                }

                Text("当前正式链路：SDK 鉴权并拉起授权页，拿到 `accessToken` 后调用 `POST /v1/auth/one-click/login`，再同步本地登录态、激活态与每日额度。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                if let latestSDKEvent = sdkEventHistory.last {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("最近 SDK 回调：[\(latestSDKEvent.stage)] \(latestSDKEvent.code) \(latestSDKEvent.message)")
                            .font(.caption2)
                            .foregroundStyle(pagePurple.opacity(0.92))

                        if sdkEventHistory.count > 1 {
                            ForEach(Array(sdkEventHistory.suffix(8).dropLast().enumerated()), id: \.offset) { _, event in
                                Text("此前：[\(event.stage)] \(event.code) \(event.message)")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var fallbackFlowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("其他登录方式回退")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("你刚刚点击了授权页里的“切换其他方式”。当前我们会先回到扶摇自己的登录页，再由这里决定下一步，而不是停留在 SDK 默认行为里。")
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                Button {
                    startOneClickLogin()
                } label: {
                    Text("继续一键登录")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.Colors.brandGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(LiftPressButtonStyle(scale: 0.985))

                Button {
                    dismiss()
                } label: {
                    Text("暂时返回应用")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(pageIndigo)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.82))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(pagePurple.opacity(0.25), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(LiftPressButtonStyle(scale: 0.985))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.84), pageBlue.opacity(0.10)],
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

    private var flowCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SoftSectionHeader(title: "认证流程", subtitle: "按当前后端的一键登录协议组织前端状态")

                VStack(spacing: 10) {
                    flowRow(step: "1", title: "SDK 鉴权", subtitle: "读取本地 `NUMBER_AUTH_SDK_INFO` 初始化阿里云号码认证 SDK")
                    flowRow(step: "2", title: "检查当前环境", subtitle: "确认设备、SIM 卡和蜂窝网络支持一键登录")
                    flowRow(step: "3", title: "拉起授权页", subtitle: "展示号码认证授权页，用户确认后发起登录")
                    flowRow(step: "4", title: "获取 accessToken", subtitle: "SDK 成功回调返回一键登录 token")
                    flowRow(step: "5", title: "提交后端完成登录", subtitle: "客户端调用 `POST /v1/auth/one-click/login` 换取会话与权益")
                }
            }
        }
    }

    private var tipsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                SoftSectionHeader(title: "登录提示", subtitle: "一键登录只负责拿到本机登录凭证，云端权限仍由激活码控制")

                HStack(spacing: 8) {
                    CapsuleInfoTag(title: "失败态可直接回显", icon: "sparkles", tint: pageBlue)
                    CapsuleInfoTag(title: "登录后仍需激活码", icon: "ticket.fill", tint: pagePurple)
                }

                Text("登录成功后，如果账号尚未激活，仍只能使用本地书籍。输入激活码后，才会开放发现页和云端书籍，并展示每日额度。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private func authMetric(title: String, value: String, icon: String) -> some View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.74), pagePurple.opacity(0.12)],
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

    private func flowRow(step: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    LinearGradient(
                        colors: [pageBlue, pagePurple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func startOneClickLogin() {
        guard !authPhase.isLoading else { return }

        Task {
            do {
                await MainActor.run {
                    sdkEventHistory.removeAll()
                }
                await MainActor.run {
                    authPhase = .presentingAuthorizationPage
                    loginNotice = LoginNotice(
                        title: "正在切换到系统宿主",
                        message: "当前登录页通过 `fullScreenCover` 展示。客户端会先退出这层登录页，再从底层宿主 controller 拉起号码认证授权页，避免 `600002`。",
                        kind: .info
                    )
                    requestDismissForSDKLaunch()
                }
                let presenter = try await sdkAwaitBasePresenterAfterDismiss()

                await MainActor.run {
                    let event = OneClickSDKEvent(
                        stage: "展示容器",
                        code: "CLIENT_BASE_CONTROLLER_READY",
                        message: "\(type(of: presenter)) window=\(presenter.view.window == nil ? "NO" : "YES")"
                    )
                    sdkEventHistory.append(event)
                    if sdkEventHistory.count > 12 {
                        sdkEventHistory.removeFirst(sdkEventHistory.count - 12)
                    }
                    print("[OneClickLogin] stage=\(event.stage) code=\(event.code) message=\(event.message)")
                }

                let sdkResult = try await OneClickAuthSDKBridge.startLogin(
                    presenter: presenter,
                    onProgress: { progress in
                        apply(progress: progress)
                    },
                    onEvent: { event in
                        sdkEventHistory.append(event)
                        if sdkEventHistory.count > 12 {
                            sdkEventHistory.removeFirst(sdkEventHistory.count - 12)
                        }
                        apply(event: event)
                    }
                )

                await MainActor.run {
                    authPhase = .submittingAccessToken
                    loginNotice = LoginNotice(
                        title: "正在提交登录请求",
                        message: "SDK 已返回 `accessToken`，客户端正在调用 `POST /v1/auth/one-click/login` 换取登录会话。",
                        kind: .info
                    )
                }

                let loginPayload = try await OneClickAuthAPIClient.login(accessToken: sdkResult.accessToken)

                await MainActor.run {
                    profileStore.applyLoginSuccess(
                        phone: loginPayload.phone,
                        nickname: loginPayload.nickname,
                        userId: loginPayload.userId,
                        sessionToken: loginPayload.sessionToken,
                        activationStatusRaw: loginPayload.activationStatusRaw,
                        activationPlanName: loginPayload.activationPlanName,
                        dailyQuotaTotal: loginPayload.dailyQuotaTotal,
                        dailyQuotaUsed: loginPayload.dailyQuotaUsed,
                        dailyQuotaRemaining: loginPayload.dailyQuotaRemaining,
                        dailyQuotaResetText: loginPayload.dailyQuotaResetText,
                        activationExpiryText: loginPayload.activationExpiryText
                    )

                    authPhase = .success
                    loginNotice = LoginNotice(
                        title: "一键登录成功",
                        message: loginPayload.activationStatusRaw == "active"
                            ? "账号已登录且云端权限已激活，Profile 页会同步展示每日额度、剩余额度和有效期。"
                            : "账号已完成登录。若尚未激活，仍只能使用本地书籍，可前往“我的”页继续输入激活码。",
                        kind: .success
                    )
                    dismiss()
                }
            } catch {
                print("[OneClickLogin] stage=登录结果 code=CLIENT_LOGIN_FLOW_ERROR message=\(error.localizedDescription)")
                await MainActor.run {
                    if let authError = error as? OneClickAuthError, authError == .fallbackRequested {
                        authPhase = .fallbackOptions
                        loginNotice = LoginNotice(
                            title: "已切换到其他方式",
                            message: "SDK 授权页已经关闭，当前已回到扶摇自己的登录页。你可以重新发起一键登录，或暂时返回应用。",
                            kind: .info
                        )
                    } else {
                        loginNotice = LoginNotice(
                            title: "一键登录未完成",
                            message: error.localizedDescription,
                            kind: .info
                        )
                        authPhase = .idle
                    }
                }
            }
        }
    }

    @MainActor
    private func apply(progress: OneClickSDKProgress) {
        switch progress {
        case .configuringSDK:
            authPhase = .configuringSDK
            loginNotice = LoginNotice(
                title: "正在初始化号码认证 SDK",
                message: "客户端正在读取本地鉴权串，调用 `setAuthSDKInfo` 完成 SDK 鉴权。",
                kind: .info
            )
        case .checkingEnvironment:
            authPhase = .checkingEnvironment
            loginNotice = LoginNotice(
                title: "正在检查号码认证环境",
                message: "客户端正在检查当前设备、SIM 卡和蜂窝网络是否支持一键登录。",
                kind: .info
            )
        case .warmingAuthorizationPage:
            authPhase = .presentingAuthorizationPage
            loginNotice = LoginNotice(
                title: "正在预热授权页",
                message: "环境校验通过，客户端正在等待号码认证 SDK 完成授权页预热，再正式唤起授权页。",
                kind: .info
            )
        case .presentingAuthorizationPage:
            authPhase = .presentingAuthorizationPage
            loginNotice = LoginNotice(
                title: "正在拉起一键登录授权页",
                message: "环境校验通过后，将展示号码认证授权页，成功后由 SDK 返回 `accessToken`。",
                kind: .info
            )
        }
    }

    @MainActor
    private func apply(event: OneClickSDKEvent) {
        switch event.code {
        case "600001":
            authPhase = .waitingUserAction
            loginNotice = LoginNotice(
                title: "授权页已展示",
                message: "用户现在可以在运营商授权页里点击“一键登录”或“切换其他方式”。",
                kind: .info
            )
        case "700002":
            let isChecked = event.message.contains("isChecked=true") || event.message.contains("isChecked=1")
            if isChecked {
                authPhase = .processingAuthorization
                loginNotice = LoginNotice(
                    title: "已点击一键登录",
                    message: "SDK 正在处理登录按钮点击并获取 `accessToken`。",
                    kind: .info
                )
            } else {
                authPhase = .waitingUserAction
                loginNotice = LoginNotice(
                    title: "请先勾选协议",
                    message: "用户点击了“一键登录”，但当前隐私协议未勾选，SDK 不会继续获取 `accessToken`。",
                    kind: .info
                )
            }
        case "700003":
            loginNotice = LoginNotice(
                title: "协议勾选状态已变化",
                message: "用户刚刚点击了协议勾选框，授权页会根据勾选状态决定是否继续获取 `accessToken`。",
                kind: .info
            )
        case "700004":
            loginNotice = LoginNotice(
                title: "正在查看协议",
                message: "用户点击了授权页协议内容，SDK 仍停留在授权页等待后续操作。",
                kind: .info
            )
        case "700006":
            loginNotice = LoginNotice(
                title: "二次隐私弹窗已出现",
                message: "SDK 拉起了二次隐私确认弹窗，等待用户确认是否继续。",
                kind: .info
            )
        case "700008":
            authPhase = .processingAuthorization
            loginNotice = LoginNotice(
                title: "已确认继续登录",
                message: "用户已在二次隐私弹窗中确认继续，SDK 正在获取 `accessToken`。",
                kind: .info
            )
        case "700009":
            loginNotice = LoginNotice(
                title: "正在查看二次隐私协议",
                message: "用户点击了二次隐私弹窗中的协议内容，授权流程仍在等待后续操作。",
                kind: .info
            )
        case "700001":
            authPhase = .fallbackOptions
            loginNotice = LoginNotice(
                title: "已点击切换其他方式",
                message: "已收到 SDK 的 700001 回调，授权页将关闭并回到扶摇自己的登录页。",
                kind: .info
            )
        default:
            break
        }
    }

    @MainActor
    private var currentPresenter: UIViewController? {
        #if canImport(UIKit)
        if let resolvedPresenter {
            let candidates = sdkPresenterCandidates(from: resolvedPresenter)
            if let preferred = candidates.first(where: sdkPresenterIsPreferred(_:)) {
                return preferred
            }
            return candidates.first
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .topMostPresentedController
        #else
        return nil
        #endif
    }

    @MainActor
    private func requestDismissForSDKLaunch() {
        #if canImport(UIKit)
        let dismissalCandidates = sdkDismissalPresenterCandidates(from: resolvedPresenter)
        if !dismissalCandidates.isEmpty {
            let event = OneClickSDKEvent(
                stage: "退出登录页",
                code: "CLIENT_DISMISS_CANDIDATES",
                message: dismissalCandidates.map { String(describing: type(of: $0)) }.joined(separator: " -> ")
            )
            sdkEventHistory.append(event)
            if sdkEventHistory.count > 12 {
                sdkEventHistory.removeFirst(sdkEventHistory.count - 12)
            }
            print("[OneClickLogin] stage=\(event.stage) code=\(event.code) message=\(event.message)")
        }

        dismiss()
        #endif
    }
}

private enum OneClickAuthPhase {
    case idle
    case configuringSDK
    case checkingEnvironment
    case presentingAuthorizationPage
    case waitingUserAction
    case processingAuthorization
    case fallbackOptions
    case submittingAccessToken
    case success

    var isLoading: Bool {
        switch self {
        case .idle, .waitingUserAction, .fallbackOptions, .success:
            return false
        case .configuringSDK, .checkingEnvironment, .presentingAuthorizationPage, .processingAuthorization, .submittingAccessToken:
            return true
        }
    }

    var displayText: String {
        switch self {
        case .idle: return "待发起"
        case .configuringSDK: return "SDK 鉴权中"
        case .checkingEnvironment: return "环境检查中"
        case .presentingAuthorizationPage: return "授权页展示中"
        case .waitingUserAction: return "等待用户确认"
        case .processingAuthorization: return "SDK 处理中"
        case .fallbackOptions: return "已回退到扶摇登录页"
        case .submittingAccessToken: return "提交登录中"
        case .success: return "登录成功"
        }
    }

    var buttonTitle: String {
        switch self {
        case .idle: return "使用一键登录"
        case .configuringSDK: return "正在初始化 SDK..."
        case .checkingEnvironment: return "正在检查当前环境..."
        case .presentingAuthorizationPage: return "正在打开授权页..."
        case .waitingUserAction: return "等待授权页操作..."
        case .processingAuthorization: return "SDK 正在处理..."
        case .fallbackOptions: return "重新发起一键登录"
        case .submittingAccessToken: return "正在完成登录..."
        case .success: return "重新发起一键登录"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "sparkles"
        case .configuringSDK: return "shield.lefthalf.filled"
        case .checkingEnvironment: return "antenna.radiowaves.left.and.right"
        case .presentingAuthorizationPage: return "iphone.radiowaves.left.and.right"
        case .waitingUserAction: return "hand.tap.fill"
        case .processingAuthorization: return "hourglass"
        case .fallbackOptions: return "arrow.uturn.backward.circle.fill"
        case .submittingAccessToken: return "checkmark.seal.fill"
        case .success: return "person.crop.circle.badge.checkmark"
        }
    }
}

private struct LoginNotice {
    enum Kind {
        case info
        case success
    }

    let title: String
    let message: String
    let kind: Kind
}

private struct OneClickSDKEvent: Equatable {
    let stage: String
    let code: String
    let message: String
}

private enum OneClickSDKProgress {
    case configuringSDK
    case checkingEnvironment
    case warmingAuthorizationPage
    case presentingAuthorizationPage
}

private struct OneClickAuthSDKResult: Equatable {
    let accessToken: String
    let carrierName: String?
}

private struct OneClickLoginPayload: Equatable {
    let phone: String
    let nickname: String?
    let userId: String?
    let sessionToken: String?
    let activationStatusRaw: String
    let activationPlanName: String?
    let dailyQuotaTotal: Int?
    let dailyQuotaUsed: Int?
    let dailyQuotaRemaining: Int?
    let dailyQuotaResetText: String?
    let activationExpiryText: String?
}

private enum OneClickAuthError: LocalizedError, Equatable {
    case missingBaseURL
    case missingSDKInfo
    case missingField(String)
    case invalidResponse(String)
    case server(String)
    case sdkCallback(stage: String, code: String, message: String)
    case transport(String)
    case sdkNotIntegrated
    case missingPresenter
    case cancelled
    case fallbackRequested
    case envUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "未配置认证服务地址，请检查 `AUTH_API_BASE_URL` 或 `DISCOVER_API_BASE_URL`。"
        case .missingSDKInfo:
            return "未配置 `NUMBER_AUTH_SDK_INFO`，暂时无法拉起阿里云号码认证授权页。"
        case .missingField(let field):
            return "认证接口缺少必要字段：\(field)。"
        case .invalidResponse(let message):
            return "认证接口返回格式无法识别：\(message)"
        case .server(let message):
            return message
        case .sdkCallback(let stage, let code, let message):
            if code.isEmpty {
                return "\(stage)失败：\(message)"
            }
            return "\(stage)失败 [\(code)]：\(message)"
        case .transport(let message):
            return message
        case .sdkNotIntegrated:
            return "阿里云号码认证 iOS SDK 尚未集成到当前工程。"
        case .missingPresenter:
            return "无法找到当前页面控制器，暂时无法拉起号码认证授权页。"
        case .cancelled:
            return "你已取消一键登录。"
        case .fallbackRequested:
            return "你已切换到其他登录方式，当前已回到扶摇自己的登录页。"
        case .envUnavailable(let message):
            return message
        }
    }
}

private enum OneClickAuthAPIClient {
    static func login(accessToken: String) async throws -> OneClickLoginPayload {
        let body: [String: Any] = [
            "accessToken": accessToken,
            "token": accessToken,
            "loginType": "one_click"
        ]

        let data = try await request(path: "v1/auth/one-click/login", method: "POST", jsonBody: body)
        let json = try parseJSON(data)

        let user = firstObject(in: json, keys: ["user", "userInfo", "account", "profile"]) ?? json
        let entitlement = firstObject(in: json, keys: ["entitlement", "member", "membership", "plan", "rights"]) ?? json
        let permissions = firstObject(in: json, keys: ["permissions", "perms", "abilities"]) ?? json
        let quota = firstObject(in: entitlement, keys: ["dailyQuota", "quota", "quotaInfo", "usage"]) ?? entitlement

        let phone = firstString(in: user, keys: ["phone", "phoneNumber", "mobile", "mobilePhone"])
            ?? firstString(in: json, keys: ["phone", "phoneNumber", "mobile", "mobilePhone"])
        guard let phone, !phone.isEmpty else {
            throw OneClickAuthError.missingField("user.phone")
        }

        let activationStatusRaw = normalizeActivationStatus(
            raw: firstString(in: entitlement, keys: ["activationStatus", "status", "state", "memberStatus"])
                ?? firstString(in: json, keys: ["activationStatus", "status", "state", "memberStatus"]),
            permissions: permissions,
            root: json
        )

        return OneClickLoginPayload(
            phone: phone,
            nickname: firstString(in: user, keys: ["nickname", "nickName", "displayName", "name"]),
            userId: firstString(in: user, keys: ["userId", "uid", "id"]),
            sessionToken: firstString(in: json, keys: ["sessionToken", "session", "accessToken", "access_token", "token", "jwt"]),
            activationStatusRaw: activationStatusRaw,
            activationPlanName: firstString(in: entitlement, keys: ["activationPlanName", "planName", "name", "title"]),
            dailyQuotaTotal: firstInt(in: quota, keys: ["dailyQuotaTotal", "quotaTotal", "total", "limit", "dailyLimit"]),
            dailyQuotaUsed: firstInt(in: quota, keys: ["dailyQuotaUsed", "quotaUsed", "used", "consumed"]),
            dailyQuotaRemaining: firstInt(in: quota, keys: ["dailyQuotaRemaining", "quotaRemaining", "remaining", "rest"]),
            dailyQuotaResetText: firstString(in: quota, keys: ["dailyQuotaResetText", "resetText", "resetAt", "refreshAt"]),
            activationExpiryText: firstString(in: entitlement, keys: ["activationExpiryText", "expireAt", "expiredAt", "expiryDate", "validUntil"])
        )
    }

    private static func request(
        path: String,
        method: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> Data {
        guard let base = Config.authAPIBaseURL else {
            throw OneClickAuthError.missingBaseURL
        }

        let trimmed = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              let baseURL = URL(string: trimmed) else {
            throw OneClickAuthError.missingBaseURL
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OneClickAuthError.invalidResponse("缺少 HTTP 状态码")
            }
            guard (200...299).contains(http.statusCode) else {
                let json = try? parseJSON(data)
                let message = json.flatMap {
                    firstString(in: $0, keys: ["message", "msg", "error", "errorMessage", "detail"])
                } ?? "认证服务返回 \(http.statusCode)"
                throw OneClickAuthError.server(message)
            }
            return data
        } catch let error as OneClickAuthError {
            throw error
        } catch let error as URLError {
            throw OneClickAuthError.transport(describeTransportError(error, url: url))
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                let code = URLError.Code(rawValue: nsError.code)
                let urlError = URLError(code)
                throw OneClickAuthError.transport(describeTransportError(urlError, url: url))
            }
            throw OneClickAuthError.transport(error.localizedDescription)
        }
    }

    private static func describeTransportError(_ error: URLError, url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let underlyingDescription = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription ?? ""
        let localNetworkBlocked = underlyingDescription.contains("Local network prohibited")
            || error.localizedDescription.contains("Local network prohibited")

        switch error.code {
        case .notConnectedToInternet:
            if localNetworkBlocked || isLikelyLocalNetworkHost(host) {
                return "已拿到 `accessToken`，但无法访问登录服务 `\(host)`。当前更像是 iPhone 未开放“本地网络”权限，或手机无法访问局域网后端。请检查扶摇的本地网络权限、手机与后端是否在同一 Wi-Fi，以及后端地址和端口是否可达。"
            }
            return "已拿到 `accessToken`，但当前网络不可用，无法访问登录服务 `\(host)`。请检查手机联网状态后重试。"

        case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .timedOut:
            if isLikelyLocalNetworkHost(host) {
                return "已拿到 `accessToken`，但无法连接局域网登录服务 `\(host)`。请确认手机与后端在同一局域网、后端服务已启动，且 `AUTH_API_BASE_URL` 可从手机访问。"
            }
            return "已拿到 `accessToken`，但连接登录服务 `\(host)` 失败：\(error.localizedDescription)"

        default:
            return "已拿到 `accessToken`，但调用登录服务 `\(host)` 失败：\(error.localizedDescription)"
        }
    }

    private static func isLikelyLocalNetworkHost(_ host: String) -> Bool {
        let value = host.lowercased()
        if value == "localhost" || value.hasSuffix(".local") {
            return true
        }
        if value.hasPrefix("10.") || value.hasPrefix("192.168.") || value.hasPrefix("169.254.") {
            return true
        }
        if value.hasPrefix("172.") {
            let parts = value.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    private static func parseJSON(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                throw OneClickAuthError.invalidResponse(raw)
            }
            throw OneClickAuthError.invalidResponse(error.localizedDescription)
        }
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
                if let raw = dict[key] as? NSNumber {
                    return raw.intValue
                }
                if let raw = dict[key] as? String,
                   let intValue = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return intValue
                }
            }

            for nestedKey in ["data", "result", "model", "payload", "entitlement", "quota", "usage"] {
                if let nested = dict[nestedKey],
                   let result = firstInt(in: nested, keys: keys, depth: depth - 1) {
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
                    case "true", "1", "yes", "enabled", "active":
                        return true
                    case "false", "0", "no", "disabled", "inactive":
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
        }

        return nil
    }
}

#if canImport(UIKit) && canImport(ATAuthSDK)
@MainActor
private enum OneClickAuthSDKBridge {
    private static var activeSession: OneClickAuthSDKSession?

    static func startLogin(
        presenter: UIViewController,
        onProgress: @escaping @MainActor (OneClickSDKProgress) -> Void,
        onEvent: @escaping @MainActor (OneClickSDKEvent) -> Void
    ) async throws -> OneClickAuthSDKResult {
        try await withCheckedThrowingContinuation { continuation in
            let session = OneClickAuthSDKSession(
                presenter: presenter,
                onProgress: onProgress,
                onEvent: onEvent,
                continuation: continuation
            )
            activeSession = session
            session.start()
        }
    }

    static func clear(_ session: OneClickAuthSDKSession) {
        guard activeSession === session else { return }
        activeSession = nil
    }
}

@MainActor
private final class OneClickAuthSDKSession {
    private let sdkInfo: String
    private weak var presenter: UIViewController?
    private let onProgress: @MainActor (OneClickSDKProgress) -> Void
    private let onEvent: @MainActor (OneClickSDKEvent) -> Void
    private var continuation: CheckedContinuation<OneClickAuthSDKResult, Error>?
    private var authorizationPresentationTimeoutTask: Task<Void, Never>?
    private var tokenResultTimeoutTask: Task<Void, Never>?
    private var hasPresentedAuthorizationPage = false
    private var isAwaitingTokenResult = false
    private var proxyRefreshTasks: [Task<Void, Never>] = []
    private var customLoginProxyButton: UIButton?
    private var customFallbackButton: UIButton?
    private weak var authorizationControllerSnapshot: UIViewController?
    private weak var authorizationWindowSnapshot: UIWindow?
    private weak var discoveredLoginControl: UIControl?
    private weak var discoveredFallbackControl: UIControl?
    private weak var observedLoginControl: UIControl?
    private weak var observedFallbackControl: UIControl?
    private var gestureProbeTargets: [GestureProbeTarget] = []
    private var observedGestureIDs: Set<ObjectIdentifier> = []
    private var gestureForwardTargets: [GestureForwardTarget] = []
    private var forwardedGestureIDs: Set<ObjectIdentifier> = []
    private var passiveTouchBridgeTargets: [TouchProxyGestureTarget] = []
    private var passiveTouchBridgeIDs: Set<ObjectIdentifier> = []
    private weak var overlayHostView: UIView?
    private weak var sdkCustomSuperview: UIView?
    private weak var embeddedLoginProxyButton: TouchProxyButton?
    private weak var embeddedFallbackProxyButton: TouchProxyButton?
    private weak var embeddedGestureHostView: UIView?
    private var embeddedTapRecognizer: UITapGestureRecognizer?
    private var embeddedPressRecognizer: UILongPressGestureRecognizer?
    private var embeddedGestureTarget: TouchProxyGestureTarget?
    private weak var gestureHostView: UIView?
    private var hostTapRecognizer: UITapGestureRecognizer?
    private var hostPressRecognizer: UILongPressGestureRecognizer?
    private var gestureProxyTarget: TouchProxyGestureTarget?
    private var contentViewFrameSnapshot: CGRect?
    private var loginFrameSnapshot: CGRect?
    private var fallbackFrameSnapshot: CGRect?

    init(
        presenter: UIViewController,
        onProgress: @escaping @MainActor (OneClickSDKProgress) -> Void,
        onEvent: @escaping @MainActor (OneClickSDKEvent) -> Void,
        continuation: CheckedContinuation<OneClickAuthSDKResult, Error>
    ) {
        self.sdkInfo = Config.numberAuthSDKInfo?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.presenter = presenter
        self.onProgress = onProgress
        self.onEvent = onEvent
        self.continuation = continuation
    }

    func start() {
        guard !sdkInfo.isEmpty else {
            finish(with: .failure(OneClickAuthError.missingSDKInfo))
            return
        }

        guard validateSDKBundleResource() else {
            finish(with: .failure(OneClickAuthError.envUnavailable("主 App 内未找到 `ATAuthSDK.bundle`，号码认证授权页资源未完成打包。请清理构建产物后重新安装 App。")))
            return
        }

        let environment = captureDeviceEnvironment()
        publishEvent(stage: "设备环境", result: [
            "resultCode": environment.isAvailable ? "CLIENT_ENV_OK" : "CLIENT_ENV_WARN",
            "msg": environment.summary
        ])
        guard environment.hasSIM else {
            finish(with: .failure(OneClickAuthError.envUnavailable("当前设备未检测到 SIM 卡，号码认证一键登录不可用。")))
            return
        }
        guard environment.cellularEnabled || environment.wwanOpen else {
            finish(with: .failure(OneClickAuthError.envUnavailable("当前设备蜂窝数据未开启，号码认证一键登录不可用。请开启蜂窝数据后重试。")))
            return
        }

#if DEBUG
        TXCommonHandler.sharedInstance().getReporter().setConsolePrintLoggerEnable(true)
#endif
        onProgress(.configuringSDK)
        TXCommonHandler.sharedInstance().setAuthSDKInfo(sdkInfo) { [weak self] result in
            Task { @MainActor in
                self?.handleSDKConfigured(result)
            }
        }
    }

    private func handleSDKConfigured(_ result: [AnyHashable: Any]) {
        publishEvent(stage: "SDK 初始化", result: result)
        guard resultCode(from: result) == "600000" else {
            finish(with: .failure(makeSDKError(stage: "SDK 初始化", result: result, fallbackMessage: "号码认证 SDK 初始化失败")))
            return
        }

        onProgress(.checkingEnvironment)
        TXCommonHandler.sharedInstance().checkEnvAvailable(with: .loginToken, complete: { [weak self] result in
            Task { @MainActor in
                self?.handleEnvironmentChecked(result ?? [:])
            }
        })
    }

    private func handleEnvironmentChecked(_ result: [AnyHashable: Any]) {
        publishEvent(stage: "环境校验", result: result)
        guard resultCode(from: result) == "600000" else {
            finish(with: .failure(makeSDKError(stage: "环境校验", result: result, fallbackMessage: "当前设备环境暂不支持一键登录")))
            return
        }

        guard let presenter else {
            finish(with: .failure(OneClickAuthError.missingPresenter))
            return
        }

        presentAuthorizationPage(with: presenter)
    }

    private func presentAuthorizationPage(with presenter: UIViewController) {
        let activePresenter = preferredSDKPresenter(from: presenter)
        hasPresentedAuthorizationPage = false
        isAwaitingTokenResult = false

        publishEvent(stage: "展示容器", result: [
            "resultCode": "CLIENT_CONTROLLER",
            "msg": "\(type(of: activePresenter)) window=\(activePresenter.view.window == nil ? "NO" : "YES")"
        ])
        onProgress(.presentingAuthorizationPage)
        publishEvent(stage: "准备拉起授权页", result: [
            "resultCode": "CLIENT_START",
            "msg": "已调用 getLoginToken，等待 SDK 返回授权页事件"
        ])

        authorizationPresentationTimeoutTask?.cancel()
        tokenResultTimeoutTask?.cancel()
        authorizationPresentationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run {
                guard let self else { return }
                guard !self.hasPresentedAuthorizationPage else { return }
                self.finish(with: .failure(OneClickAuthError.sdkCallback(
                    stage: "授权页唤起",
                    code: "CLIENT_TIMEOUT",
                    message: "调用 getLoginToken 后 8 秒内未收到 SDK 回调，请检查真机蜂窝网络、SIM 卡、鉴权串和当前页面容器。"
                )))
            }
        }

        TXCommonHandler.sharedInstance().getLoginToken(
            withTimeout: 3.0,
            controller: activePresenter,
            model: buildCustomModel(),
            complete: { [weak self] result in
                Task { @MainActor in
                    self?.handleLoginTokenCallback(result)
                }
            }
        )
    }

    private func preferredSDKPresenter(from presenter: UIViewController) -> UIViewController {
        let candidates = sdkPresenterCandidates(from: presenter)

        publishEvent(stage: "展示容器候选", result: [
            "resultCode": "CLIENT_CONTROLLER_CANDIDATES",
            "msg": candidates.map { String(describing: type(of: $0)) }.joined(separator: " -> ")
        ])

        if let preferred = candidates.first(where: sdkPresenterIsPreferred(_:)) {
            return preferred
        }

        return candidates.first ?? presenter
    }

    private func handleLoginTokenCallback(_ result: [AnyHashable: Any]) {
        publishEvent(stage: "授权页回调", result: result)
        let code = resultCode(from: result)

        switch code {
        case "600001":
            hasPresentedAuthorizationPage = true
            authorizationPresentationTimeoutTask?.cancel()
            authorizationPresentationTimeoutTask = nil
            handleAuthorizationPagePresented()
            return
        case "700002":
            if (result["isChecked"] as? Bool) == true || stringValue(result["isChecked"]) == "1" {
                restartTokenTimeout(message: "用户已点击一键登录，SDK 正在获取 `accessToken`。")
            }
            return
        case "700003", "700004", "700006", "700009":
            return
        case "700008":
            restartTokenTimeout(message: "用户已在二次隐私弹窗中确认继续，SDK 正在获取 `accessToken`。")
            return
        case "700020":
            finish(with: .failure(OneClickAuthError.sdkCallback(
                stage: "授权页生命周期",
                code: code,
                message: "号码认证授权页已被销毁，通常是当前登录入口使用 sheet 容器导致授权页生命周期不稳定。"
            )))
        case "600000":
            authorizationPresentationTimeoutTask?.cancel()
            authorizationPresentationTimeoutTask = nil
            tokenResultTimeoutTask?.cancel()
            tokenResultTimeoutTask = nil
            isAwaitingTokenResult = false
            guard let accessToken = stringValue(result["token"]) ?? stringValue(result["accessToken"]) else {
                finish(with: .failure(OneClickAuthError.missingField("accessToken")))
                return
            }
            TXCommonHandler.sharedInstance().cancelLoginVC(animated: true, complete: nil)
            finish(with: .success(OneClickAuthSDKResult(
                accessToken: accessToken,
                carrierName: stringValue(result["carrierName"]) ?? stringValue(result["operatorName"])
            )))
        case "700001":
            authorizationPresentationTimeoutTask?.cancel()
            authorizationPresentationTimeoutTask = nil
            tokenResultTimeoutTask?.cancel()
            tokenResultTimeoutTask = nil
            isAwaitingTokenResult = false
            TXCommonHandler.sharedInstance().cancelLoginVC(animated: true, complete: nil)
            finish(with: .failure(OneClickAuthError.fallbackRequested))
        case "700000", "700010":
            authorizationPresentationTimeoutTask?.cancel()
            authorizationPresentationTimeoutTask = nil
            tokenResultTimeoutTask?.cancel()
            tokenResultTimeoutTask = nil
            isAwaitingTokenResult = false
            TXCommonHandler.sharedInstance().cancelLoginVC(animated: true, complete: nil)
            finish(with: .failure(OneClickAuthError.cancelled))
        case "600002":
            authorizationPresentationTimeoutTask?.cancel()
            authorizationPresentationTimeoutTask = nil
            tokenResultTimeoutTask?.cancel()
            tokenResultTimeoutTask = nil
            isAwaitingTokenResult = false
            finish(with: .failure(makeSDKError(stage: "授权页唤起", result: result, fallbackMessage: "号码认证授权页唤起失败")))
        case "600011":
            authorizationPresentationTimeoutTask?.cancel()
            authorizationPresentationTimeoutTask = nil
            tokenResultTimeoutTask?.cancel()
            tokenResultTimeoutTask = nil
            isAwaitingTokenResult = false
            finish(with: .failure(makeSDKError(stage: "获取 accessToken", result: result, fallbackMessage: "号码认证已拉起，但获取 accessToken 失败")))
        case "600015":
            authorizationPresentationTimeoutTask?.cancel()
            authorizationPresentationTimeoutTask = nil
            tokenResultTimeoutTask?.cancel()
            tokenResultTimeoutTask = nil
            isAwaitingTokenResult = false
            finish(with: .failure(makeSDKError(stage: "获取 accessToken", result: result, fallbackMessage: "号码认证获取 accessToken 超时")))
        default:
            authorizationPresentationTimeoutTask?.cancel()
            authorizationPresentationTimeoutTask = nil
            tokenResultTimeoutTask?.cancel()
            tokenResultTimeoutTask = nil
            isAwaitingTokenResult = false
            finish(with: .failure(makeSDKError(stage: "授权页回调", result: result, fallbackMessage: "一键登录暂不可用，请稍后重试。")))
        }
    }

    private func buildCustomModel() -> TXCustomModel {
        let model = TXCustomModel()
        let indigo = UIColor(red: 0.35, green: 0.45, blue: 0.82, alpha: 1)

        model.prefersStatusBarHidden = false
        model.preferredStatusBarStyle = .darkContent
        model.navColor = .white
        model.navTitle = NSAttributedString(
            string: "扶摇一键登录",
            attributes: [
                .foregroundColor: indigo,
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold)
            ]
        )
        if let backImage = UIImage(systemName: "chevron.left") {
            model.navBackImage = backImage
        }
        model.backgroundColor = UIColor.systemBackground
        model.logoIsHidden = true
        model.sloganIsHidden = true
        model.numberColor = .black
        model.numberFont = UIFont.systemFont(ofSize: 24, weight: .semibold)
        model.showLoginLoading = true
        model.autoHideLoginLoading = true
        model.checkBoxIsChecked = true
        model.changeBtnIsHidden = false
        model.privacyAlignment = .center
        model.privacyColors = [
            UIColor(red: 0.48, green: 0.53, blue: 0.66, alpha: 1),
            indigo
        ]
        model.privacyPreText = "登录即代表同意"
        model.privacySufText = "并授权扶摇完成本机号码认证"
        model.privacyFont = UIFont.systemFont(ofSize: 12)
        model.privacyOperatorColor = indigo
        model.privacyLineSpaceDp = 3
        model.presentDirection = .bottom
        model.animationDuration = 0.25
        model.supportedInterfaceOrientations = .portrait

        return model
    }

    private func handleAuthorizationLayout(contentFrame: CGRect, loginFrame: CGRect, changeFrame: CGRect) {
        contentViewFrameSnapshot = contentFrame.isEmpty ? contentViewFrameSnapshot : contentFrame
        loginFrameSnapshot = loginFrame.isEmpty ? loginFrameSnapshot : loginFrame
        fallbackFrameSnapshot = changeFrame.isEmpty ? fallbackFrameSnapshot : changeFrame
        publishEvent(stage: "授权页布局", result: [
            "resultCode": "CLIENT_LAYOUT",
            "msg": "contentFrame=\(contentFrame.debugSummary) loginFrame=\(loginFrame.debugSummary) changeFrame=\(changeFrame.debugSummary)"
        ])
    }

    private func handleAuthorizationPagePresented() {
        let authController = authorizationContentController()
        authorizationControllerSnapshot = authController
        authorizationWindowSnapshot = authController?.view.window ?? authController?.navigationController?.view.window
        authController?.view.isUserInteractionEnabled = true
        authController?.navigationController?.view.isUserInteractionEnabled = true

        publishEvent(stage: "授权页交互层", result: [
            "resultCode": "CLIENT_AUTH_PAGE_READY",
            "msg": "\(authController.map { String(describing: type(of: $0)) } ?? "nil") interaction=\(authController?.view.isUserInteractionEnabled == true ? "YES" : "NO")"
        ])
        publishEvent(stage: "授权页控制器", result: [
            "resultCode": "CLIENT_AUTH_CONTROLLER",
            "msg": summarizeAuthorizationController()
        ])
    }

    private func handleManualLoginProxyTap() {
        let isChecked = TXCommonHandler.sharedInstance().queryCheckBoxIsChecked()
        publishEvent(stage: "授权页本地按钮", result: [
            "resultCode": "CLIENT_LOGIN_TAP",
            "msg": "扶摇本地登录代理按钮已响应，当前协议勾选=\(isChecked ? "YES" : "NO")"
        ])

        guard let sdkLoginButton = discoveredLoginControl ?? findSDKLoginControlAcrossWindows() else {
            publishEvent(stage: "授权页本地按钮", result: [
                "resultCode": "CLIENT_LOGIN_BUTTON_NOT_FOUND",
                "msg": summarizeAuthControlsAcrossWindows() ?? "未找到带“一键登录”文案的 UIControl"
            ])
            return
        }

        discoveredLoginControl = sdkLoginButton
        publishEvent(stage: "授权页本地按钮", result: [
            "resultCode": "CLIENT_LOGIN_PROXY",
            "msg": "已找到 SDK 登录按钮 \(String(describing: type(of: sdkLoginButton))) enabled=\(sdkLoginButton.isEnabled ? "YES" : "NO") hidden=\(sdkLoginButton.isHidden ? "YES" : "NO") frame=\(sdkLoginButton.frame.debugSummary)"
        ])
        restartTokenTimeout(message: "扶摇本地代理按钮已触发 SDK 登录按钮，正在等待 accessToken 结果。")
        sdkLoginButton.sendActions(for: .touchDown)
        sdkLoginButton.sendActions(for: .primaryActionTriggered)
        sdkLoginButton.sendActions(for: .touchUpInside)
    }

    private func handleManualFallbackTap() {
        publishEvent(stage: "授权页本地按钮", result: [
            "resultCode": "CLIENT_FALLBACK_TAP",
            "msg": "扶摇自定义“切换其他方式”按钮已响应，正在关闭授权页并回到扶摇登录页。"
        ])
        if let fallbackControl = discoveredFallbackControl ?? findFallbackControlAcrossWindows() {
            discoveredFallbackControl = fallbackControl
            fallbackControl.sendActions(for: .touchUpInside)
        }
        authorizationPresentationTimeoutTask?.cancel()
        authorizationPresentationTimeoutTask = nil
        tokenResultTimeoutTask?.cancel()
        tokenResultTimeoutTask = nil
        isAwaitingTokenResult = false
        TXCommonHandler.sharedInstance().cancelLoginVC(animated: true, complete: nil)
        finish(with: .failure(OneClickAuthError.fallbackRequested))
    }

    private func makeButtonImage(colors: [UIColor]) -> UIImage {
        let size = CGSize(width: 16, height: 52)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 26)
            path.addClip()

            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map(\.cgColor) as CFArray,
                locations: [0, 1]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            } else {
                colors.first?.setFill()
                context.fill(rect)
            }
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 26, left: 8, bottom: 26, right: 8))
    }

    private func restartTokenTimeout(message: String) {
        isAwaitingTokenResult = true
        tokenResultTimeoutTask?.cancel()
        tokenResultTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run {
                guard let self else { return }
                guard self.isAwaitingTokenResult else { return }
                self.finish(with: .failure(OneClickAuthError.sdkCallback(
                    stage: "获取 accessToken",
                    code: "CLIENT_TIMEOUT",
                    message: "\(message) 但 8 秒内未收到 token 结果。"
                )))
            }
        }
    }

    private func validateSDKBundleResource() -> Bool {
        let path = Bundle.main.path(forResource: "ATAuthSDK", ofType: "bundle")
        let bundleExists = path.flatMap { Bundle(path: $0) } != nil
        publishEvent(stage: "SDK 资源", result: [
            "resultCode": bundleExists ? "CLIENT_BUNDLE_OK" : "CLIENT_BUNDLE_MISSING",
            "msg": bundleExists ? "已在主包中找到 ATAuthSDK.bundle" : "主包中未找到 ATAuthSDK.bundle"
        ])
        return bundleExists
    }

    private func captureDeviceEnvironment() -> DeviceEnvironment {
        DeviceEnvironment(
            hasSIM: TXCommonUtils.simSupportedIsOK(),
            cellularEnabled: TXCommonUtils.checkDeviceCellularDataEnable(),
            wwanOpen: TXCommonUtils.isWWANOpen(),
            carrierName: stringValue(TXCommonUtils.getCurrentCarrierName()) ?? "未知运营商",
            networkType: stringValue(TXCommonUtils.getNetworktype()) ?? "未知网络"
        )
    }

    private func resultCode(from result: [AnyHashable: Any]) -> String {
        stringValue(result["resultCode"]) ?? stringValue(result["code"]) ?? ""
    }

    private func message(from result: [AnyHashable: Any]) -> String? {
        stringValue(result["msg"]) ?? stringValue(result["message"]) ?? stringValue(result["error"])
    }

    private func publishEvent(stage: String, result: [AnyHashable: Any]) {
        let code = resultCode(from: result)
        var detail = message(from: result) ?? "无附加说明"
        if let isChecked = result["isChecked"] as? Bool {
            detail += " (isChecked=\(isChecked ? "true" : "false"))"
        } else if let isChecked = stringValue(result["isChecked"]) {
            detail += " (isChecked=\(isChecked))"
        }
        let event = OneClickSDKEvent(
            stage: stage,
            code: code.isEmpty ? "-" : code,
            message: detail
        )
#if DEBUG
        print("[OneClickLogin] stage=\(event.stage) code=\(event.code) message=\(event.message)")
#endif
        onEvent(event)
    }

    private func makeSDKError(
        stage: String,
        result: [AnyHashable: Any],
        fallbackMessage: String
    ) -> OneClickAuthError {
        let code = resultCode(from: result)
        let message = message(from: result) ?? fallbackMessage
        return .sdkCallback(stage: stage, code: code, message: message)
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func summarizeAuthButtons(in rootView: UIView?) -> String? {
        guard let rootView else { return nil }
        let buttons = collectButtons(in: rootView)
        guard !buttons.isEmpty else { return nil }
        return buttons.prefix(6).map { button in
            let title = button.currentTitle ?? button.attributedTitle(for: .normal)?.string ?? button.accessibilityLabel ?? "<no-title>"
            return "\"\(title)\" enabled=\(button.isEnabled ? "YES" : "NO") hidden=\(button.isHidden ? "YES" : "NO") alpha=\(String(format: "%.2f", button.alpha)) frame=\(button.frame.debugSummary)"
        }.joined(separator: " | ")
    }

    private func summarizeAuthControlsAcrossWindows() -> String? {
        let controls = authorizationSearchRoots().flatMap { collectControls(in: $0) }
        let labeledControls = controls.compactMap { control -> String? in
            guard let label = displayText(for: control) else {
                return nil
            }
            guard label.contains("一键登录") || label.contains("其他方式") || label.contains("切换") else {
                return nil
            }
            return "\"\(label)\" \(String(describing: type(of: control))) enabled=\(control.isEnabled ? "YES" : "NO") hidden=\(control.isHidden ? "YES" : "NO") frame=\(control.frame.debugSummary)"
        }

        if !labeledControls.isEmpty {
            return labeledControls.prefix(8).joined(separator: " | ")
        }

        let labeledViews = authorizationSearchRoots().flatMap { collectLabeledViews(in: $0) }
        let candidates = labeledViews.compactMap { view, label -> String? in
            guard label.contains("一键登录") || label.contains("其他方式") || label.contains("切换") else {
                return nil
            }
            return "\"\(label)\" \(String(describing: type(of: view))) frame=\(view.frame.debugSummary)"
        }
        return candidates.isEmpty ? nil : candidates.prefix(8).joined(separator: " | ")
    }

    private func collectButtons(in view: UIView) -> [UIButton] {
        var buttons: [UIButton] = []
        if let button = view as? UIButton {
            buttons.append(button)
        }
        for subview in view.subviews {
            buttons.append(contentsOf: collectButtons(in: subview))
        }
        return buttons
    }

    private func collectControls(in view: UIView) -> [UIControl] {
        var controls: [UIControl] = []
        if let control = view as? UIControl {
            controls.append(control)
        }
        for subview in view.subviews {
            controls.append(contentsOf: collectControls(in: subview))
        }
        return controls
    }

    private func collectLabeledViews(in view: UIView) -> [(UIView, String)] {
        var results: [(UIView, String)] = []
        if let label = displayText(for: view) {
            results.append((view, label))
        }
        for subview in view.subviews {
            results.append(contentsOf: collectLabeledViews(in: subview))
        }
        return results
    }

    private func displayText(for view: UIView) -> String? {
        if let button = view as? UIButton {
            if let title = button.currentTitle, !title.isEmpty {
                return title
            }
            if let title = button.attributedTitle(for: .normal)?.string, !title.isEmpty {
                return title
            }
        }
        if let label = view as? UILabel, let text = label.text, !text.isEmpty {
            return text
        }
        if let accessibilityLabel = view.accessibilityLabel, !accessibilityLabel.isEmpty {
            return accessibilityLabel
        }
        return nil
    }

    private func findSDKLoginControlAcrossWindows() -> UIControl? {
        authorizationSearchRoots().flatMap { collectControls(in: $0) }.first { control in
            if control === customLoginProxyButton || control === customFallbackButton {
                return false
            }
            let title = displayText(for: control) ?? ""
            return title.contains("一键登录") || title == "登录" || title.contains("本机号码")
        }
    }

    private func findFallbackControlAcrossWindows() -> UIControl? {
        authorizationSearchRoots().flatMap { collectControls(in: $0) }.first { control in
            if control === customLoginProxyButton || control === customFallbackButton {
                return false
            }
            let title = displayText(for: control) ?? ""
            return title.contains("其他方式") || title.contains("切换")
        }
    }

    private func visibleWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0.01 }
            .sorted { $0.windowLevel.rawValue > $1.windowLevel.rawValue }
    }

    private func summarizeVisibleWindows() -> String {
        let windows = visibleWindows()
        guard !windows.isEmpty else { return "当前未发现任何可见 window" }
        return windows.prefix(6).map { window in
            let root: String
            if let controller = window.rootViewController {
                root = String(describing: type(of: controller))
            } else {
                root = "nil"
            }

            let top: String
            if let controller = window.rootViewController?.topMostPresentedController {
                top = String(describing: type(of: controller))
            } else {
                top = "nil"
            }
            return "level=\(Int(window.windowLevel.rawValue)) key=\(window.isKeyWindow ? "YES" : "NO") root=\(root) top=\(top)"
        }.joined(separator: " | ")
    }

    private func installLocalProxyButtons() {
        customLoginProxyButton?.removeFromSuperview()
        customLoginProxyButton = nil
        customFallbackButton?.removeFromSuperview()

        let snapshotAuthView = authorizationControllerSnapshot?.view
        let snapshotNavigationView = authorizationControllerSnapshot?.navigationController?.view
        let currentAuthView = authorizationContentController()?.view
        let currentNavigationView = authorizationContentController()?.navigationController?.view
        let snapshotWindow = authorizationWindowSnapshot
        let snapshotControllerWindow = authorizationControllerSnapshot?.view.window
        let snapshotNavigationWindow = authorizationControllerSnapshot?.navigationController?.view.window
        let currentAuthWindow = authorizationContentController()?.view.window
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let preferredAuthView = snapshotNavigationView
            ?? snapshotAuthView
            ?? currentNavigationView
            ?? currentAuthView
        let preferredWindow = snapshotWindow
            ?? snapshotControllerWindow
            ?? snapshotNavigationWindow
            ?? currentAuthWindow
            ?? keyWindow
        let preferredHostView = preferredAuthView ?? preferredWindow

        guard let hostView = preferredHostView ?? visibleWindows().first else {
            publishEvent(stage: "授权页本地代理", result: [
                "resultCode": "CLIENT_PROXY_MISSING",
                "msg": "未找到可挂载本地代理按钮的授权页 window，snapshot=\(authorizationWindowSnapshot == nil ? "nil" : "YES"), visibleWindows=\(visibleWindows().count)"
            ])
            return
        }

        overlayHostView = hostView
        hostView.setNeedsLayout()
        hostView.layoutIfNeeded()
        authorizationControllerSnapshot?.view.layoutIfNeeded()
        authorizationControllerSnapshot?.navigationController?.view.layoutIfNeeded()
        publishEvent(stage: "授权页控制器诊断", result: [
            "resultCode": "CLIENT_AUTH_CONTROLLER",
            "msg": summarizeAuthorizationController()
        ])

        if let loginTargetView = (findSDKLoginControlAcrossWindows(in: hostView) as UIView?)
            ?? authorizationSearchRoots().lazy.compactMap({ self.findSDKLoginControlAcrossWindows(in: $0) as UIView? }).first
            ?? findLabeledLoginView(in: hostView)
            ?? authorizationSearchRoots().lazy.compactMap({ self.findLabeledLoginView(in: $0) }).first {
            let resolvedLoginView = resolveTargetView(
                preferredFrame: loginFrameSnapshot,
                in: hostView,
                fallback: loginTargetView,
                matcher: { label in
                    label.contains("一键登录") || label == "登录" || label.contains("本机号码")
                }
            )
            if let loginControl = resolvedLoginView as? UIControl {
                discoveredLoginControl = loginControl
                publishEvent(stage: "授权页控件元数据", result: [
                    "resultCode": "CLIENT_LOGIN_CONTROL_META",
                    "msg": describeControlMetadata(loginControl)
                ])
                publishEvent(stage: "授权页控件层级", result: [
                    "resultCode": "CLIENT_LOGIN_ANCESTRY",
                    "msg": describeViewAncestry(for: resolvedLoginView)
                ])
                installObservation(on: loginControl, kind: .login)
                installGestureDiagnostics(on: resolvedLoginView, codePrefix: "CLIENT_LOGIN_VIEW")
                installGestureForwarding(on: resolvedLoginView, mode: .login)
                if let parentView = resolvedLoginView.superview {
                    installGestureDiagnostics(on: parentView, codePrefix: "CLIENT_LOGIN_PARENT")
                }
            }
            installHostGestureProxy(on: resolvedLoginView.superview ?? hostView)
            publishHitTest(for: resolvedLoginView, in: hostView, stage: "授权页点击命中")
        }

        if let fallbackTargetView = (findFallbackControlAcrossWindows(in: hostView) as UIView?)
            ?? authorizationSearchRoots().lazy.compactMap({ self.findFallbackControlAcrossWindows(in: $0) as UIView? }).first
            ?? findLabeledFallbackView(in: hostView)
            ?? authorizationSearchRoots().lazy.compactMap({ self.findLabeledFallbackView(in: $0) }).first {
            let resolvedFallbackView = resolveTargetView(
                preferredFrame: fallbackFrameSnapshot,
                in: hostView,
                fallback: fallbackTargetView,
                matcher: { label in
                    label.contains("其他方式") || label.contains("切换")
                }
            )
            if let fallbackControl = resolvedFallbackView as? UIControl {
                discoveredFallbackControl = fallbackControl
                publishEvent(stage: "授权页控件元数据", result: [
                    "resultCode": "CLIENT_FALLBACK_CONTROL_META",
                    "msg": describeControlMetadata(fallbackControl)
                ])
                publishEvent(stage: "授权页控件层级", result: [
                    "resultCode": "CLIENT_FALLBACK_ANCESTRY",
                    "msg": describeViewAncestry(for: resolvedFallbackView)
                ])
                installObservation(on: fallbackControl, kind: .fallback)
                installGestureDiagnostics(on: resolvedFallbackView, codePrefix: "CLIENT_FALLBACK_VIEW")
                installGestureForwarding(on: resolvedFallbackView, mode: .fallback)
                if let parentView = resolvedFallbackView.superview {
                    installGestureDiagnostics(on: parentView, codePrefix: "CLIENT_FALLBACK_PARENT")
                }
            }
        }

        publishEvent(stage: "授权页本地代理", result: [
            "resultCode": "CLIENT_PROXY_INSTALLED",
            "msg": "loginObserver=\(discoveredLoginControl == nil ? "NO" : "YES"), loginProxy=\(customLoginProxyButton == nil ? "NO" : "YES"), fallbackProxy=\(customFallbackButton == nil ? "NO" : "YES"), host=\(String(describing: type(of: hostView))) loginFrame=\((discoveredLoginControl?.frame.debugSummary) ?? "nil")"
        ])
    }

    private enum ObservedControlKind {
        case login
        case fallback
    }

    private func installObservation(on control: UIControl, kind: ObservedControlKind) {
        switch kind {
        case .login:
            guard observedLoginControl !== control else { return }
            observedLoginControl = control
            control.addAction(
                UIAction { [weak self, weak control] _ in
                    guard let self else { return }
                    let isChecked = TXCommonHandler.sharedInstance().queryCheckBoxIsChecked()
                    self.publishEvent(stage: "授权页原生按钮", result: [
                        "resultCode": "CLIENT_NATIVE_LOGIN_TAP",
                        "msg": "真实 SDK 登录按钮已收到 touchUpInside，control=\(control.map { String(describing: type(of: $0)) } ?? "nil") checked=\(isChecked ? "YES" : "NO")"
                    ])
                    self.restartTokenTimeout(message: "真实 SDK 登录按钮已触发，正在等待 accessToken 结果。")
                },
                for: .touchUpInside
            )
            control.addAction(
                UIAction { [weak self] _ in
                    self?.publishEvent(stage: "授权页原生按钮", result: [
                        "resultCode": "CLIENT_NATIVE_LOGIN_TOUCH_DOWN",
                        "msg": "真实 SDK 登录按钮已收到 touchDown。"
                    ])
                },
                for: .touchDown
            )
            publishEvent(stage: "授权页原生按钮", result: [
                "resultCode": "CLIENT_NATIVE_LOGIN_HOOKED",
                "msg": "已挂载到真实 SDK 登录按钮，targets=\(control.allTargets.count) events=\(control.allControlEvents.rawValue)"
            ])
        case .fallback:
            guard observedFallbackControl !== control else { return }
            observedFallbackControl = control
            control.addAction(
                UIAction { [weak self, weak control] _ in
                    self?.publishEvent(stage: "授权页原生按钮", result: [
                        "resultCode": "CLIENT_NATIVE_FALLBACK_TAP",
                        "msg": "真实 SDK 其他方式按钮已收到 touchUpInside，control=\(control.map { String(describing: type(of: $0)) } ?? "nil")"
                    ])
                },
                for: .touchUpInside
            )
            control.addAction(
                UIAction { [weak self] _ in
                    self?.publishEvent(stage: "授权页原生按钮", result: [
                        "resultCode": "CLIENT_NATIVE_FALLBACK_TOUCH_DOWN",
                        "msg": "真实 SDK 其他方式按钮已收到 touchDown。"
                    ])
                },
                for: .touchDown
            )
            publishEvent(stage: "授权页原生按钮", result: [
                "resultCode": "CLIENT_NATIVE_FALLBACK_HOOKED",
                "msg": "已挂载到真实 SDK 其他方式按钮，targets=\(control.allTargets.count) events=\(control.allControlEvents.rawValue)"
            ])
        }
    }

    private func installControlDiagnosticsAndFallbackProxy() {
        // Intentionally disabled for the minimal official SDK path.
    }

    private func summarizeAuthorizationController() -> String {
        guard let controller = authorizationControllerSnapshot ?? authorizationContentController() else {
            return "当前未拿到授权页内容控制器"
        }
        let nav = controller.navigationController.map { String(describing: type(of: $0)) } ?? "nil"
        let parent = controller.parent.map { String(describing: type(of: $0)) } ?? "nil"
        return "controller=\(String(describing: type(of: controller))) nav=\(nav) parent=\(parent) children=\(controller.children.count) subviews=\(controller.view.subviews.count) window=\(controller.view.window == nil ? "NO" : "YES")"
    }

    private func scheduleProxyRefreshes() {
        // Intentionally disabled for the minimal official SDK path.
    }

    private func cancelProxyRefreshTasks() {
        proxyRefreshTasks.forEach { $0.cancel() }
        proxyRefreshTasks.removeAll()
    }

    private func authorizationContentController() -> UIViewController? {
        if let snapshot = authorizationControllerSnapshot {
            return snapshot.topMostPresentedControllerIfAvailable
        }
        if let controller = visibleWindows()
            .compactMap(\.rootViewController)
            .compactMap(findAuthorizationController(in:))
            .first {
            return controller
        }
        if let top = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .topMostPresentedControllerIfAvailable {
            return top
        }
        if let presenter {
            return presenter.topMostPresentedControllerIfAvailable
        }
        return nil
    }

    private func authorizationSearchRoots() -> [UIView] {
        var roots: [UIView] = []

        func appendIfNeeded(_ view: UIView?) {
            guard let view else { return }
            if roots.contains(where: { $0 === view }) { return }
            roots.append(view)
        }

        appendIfNeeded(authorizationControllerSnapshot?.view)
        appendIfNeeded(authorizationControllerSnapshot?.navigationController?.view)
        appendIfNeeded(authorizationContentController()?.view)
        appendIfNeeded(authorizationContentController()?.navigationController?.view)
        appendIfNeeded(authorizationWindowSnapshot)
        visibleWindows().forEach { appendIfNeeded($0) }
        return roots
    }

    private func findAuthorizationController(in controller: UIViewController) -> UIViewController? {
        let typeName = String(describing: type(of: controller))
        if typeName.contains("TXSSOLoginViewController") {
            return controller
        }
        if typeName.contains("PNSNavigationController"),
           let top = controller.topMostPresentedControllerIfAvailable as UIViewController? {
            let topType = String(describing: type(of: top))
            if topType.contains("TXSSOLoginViewController") {
                return top
            }
        }

        for child in controller.children {
            if let found = findAuthorizationController(in: child) {
                return found
            }
        }
        if let presented = controller.presentedViewController {
            if let found = findAuthorizationController(in: presented) {
                return found
            }
        }
        if let nav = controller as? UINavigationController,
           let visible = nav.visibleViewController,
           let found = findAuthorizationController(in: visible) {
            return found
        }
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController,
           let found = findAuthorizationController(in: selected) {
            return found
        }
        return nil
    }

    private func resolvedProxyFrame(for targetView: UIView, in hostView: UIView, fallback: CGRect?) -> CGRect {
        let convertedFrame = targetView.convert(targetView.bounds, to: hostView)
        if !convertedFrame.isEmpty && convertedFrame.width > 1 && convertedFrame.height > 1 {
            return convertedFrame
        }
        if let fallback, !fallback.isEmpty {
            return fallback
        }
        return convertedFrame
    }

    private func installHostGestureProxy(on hostView: UIView) {
        if gestureHostView !== hostView {
            removeHostGestureProxy()
        }
        guard gestureHostView == nil else { return }

        let target = TouchProxyGestureTarget()
        target.onTap = { [weak self, weak hostView] point in
            guard let self, let hostView else { return }

            let loginFrame = self.currentLoginBridgeFrame(in: hostView)
            if !loginFrame.isEmpty, loginFrame.contains(point) {
                self.publishEvent(stage: "授权页本地代理", result: [
                    "resultCode": "CLIENT_LOGIN_PROXY_USER_TAP",
                    "msg": "父层手势桥已命中登录区域，point=(\(Int(point.x)),\(Int(point.y))) frame=\(loginFrame.debugSummary)"
                ])
                self.handleManualLoginProxyTap()
                return
            }

            let fallbackFrame = self.currentFallbackBridgeFrame(in: hostView)
            if !fallbackFrame.isEmpty, fallbackFrame.contains(point) {
                self.publishEvent(stage: "授权页本地代理", result: [
                    "resultCode": "CLIENT_FALLBACK_PROXY_USER_TAP",
                    "msg": "父层手势桥已命中其他方式区域，point=(\(Int(point.x)),\(Int(point.y))) frame=\(fallbackFrame.debugSummary)"
                ])
                self.handleManualFallbackTap()
            }
        }
        target.onPress = { [weak self] state, point in
            guard let self else { return }
            guard let hostView = self.gestureHostView else { return }
            let loginFrame = self.currentLoginBridgeFrame(in: hostView)
            let fallbackFrame = self.currentFallbackBridgeFrame(in: hostView)

            switch state {
            case .began:
                if !loginFrame.isEmpty, loginFrame.contains(point) {
                    self.publishEvent(stage: "授权页本地代理", result: [
                        "resultCode": "CLIENT_LOGIN_PROXY_TOUCH_DOWN",
                        "msg": "父层手势桥已收到登录区域 touchDown，point=(\(Int(point.x)),\(Int(point.y)))"
                    ])
                } else if !fallbackFrame.isEmpty, fallbackFrame.contains(point) {
                    self.publishEvent(stage: "授权页本地代理", result: [
                        "resultCode": "CLIENT_FALLBACK_PROXY_TOUCH_DOWN",
                        "msg": "父层手势桥已收到其他方式区域 touchDown，point=(\(Int(point.x)),\(Int(point.y)))"
                    ])
                }
            case .cancelled, .failed:
                self.publishEvent(stage: "授权页本地代理", result: [
                    "resultCode": "CLIENT_PROXY_CANCELLED",
                    "msg": "父层手势桥触摸被取消，point=(\(Int(point.x)),\(Int(point.y)))"
                ])
            default:
                break
            }
        }

        let tap = UITapGestureRecognizer(target: target, action: #selector(TouchProxyGestureTarget.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = target

        let press = UILongPressGestureRecognizer(target: target, action: #selector(TouchProxyGestureTarget.handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = 20
        press.cancelsTouchesInView = false
        press.delegate = target

        hostView.addGestureRecognizer(tap)
        hostView.addGestureRecognizer(press)

        gestureHostView = hostView
        hostTapRecognizer = tap
        hostPressRecognizer = press
        gestureProxyTarget = target
        publishEvent(stage: "授权页本地代理", result: [
            "resultCode": "CLIENT_LOGIN_PROXY_READY",
            "msg": "已挂载父层手势桥，host=\(String(describing: type(of: hostView)))"
        ])
    }

    private func currentLoginBridgeFrame(in hostView: UIView) -> CGRect {
        if let control = discoveredLoginControl as? UIView,
           let superview = control.superview,
           superview === hostView {
            return control.frame
        }
        if let control = discoveredLoginControl as? UIView {
            return resolvedProxyFrame(for: control, in: hostView, fallback: loginFrameSnapshot)
        }
        return loginFrameSnapshot ?? .zero
    }

    private func currentFallbackBridgeFrame(in hostView: UIView) -> CGRect {
        if let control = discoveredFallbackControl as? UIView,
           let superview = control.superview,
           superview === hostView {
            return control.frame
        }
        if let control = discoveredFallbackControl as? UIView {
            return resolvedProxyFrame(for: control, in: hostView, fallback: fallbackFrameSnapshot)
        }
        return fallbackFrameSnapshot ?? .zero
    }

    private func removeHostGestureProxy() {
        if let tap = hostTapRecognizer {
            gestureHostView?.removeGestureRecognizer(tap)
        }
        if let press = hostPressRecognizer {
            gestureHostView?.removeGestureRecognizer(press)
        }
        hostTapRecognizer = nil
        hostPressRecognizer = nil
        gestureProxyTarget = nil
        gestureHostView = nil
    }

    private func installEmbeddedProxyViews(in superCustomView: UIView) {
        sdkCustomSuperview = superCustomView
        installEmbeddedGestureProxy(on: superCustomView)

        if embeddedLoginProxyButton == nil {
            let loginButton = TouchProxyButton(type: .custom)
            loginButton.backgroundColor = UIColor.white.withAlphaComponent(0.01)
            loginButton.accessibilityIdentifier = "fuyao.oneclick.login.embedded"
            loginButton.onTouchDown = { [weak self] in
                self?.publishEvent(stage: "授权页内嵌代理", result: [
                    "resultCode": "CLIENT_EMBED_LOGIN_TOUCH_DOWN",
                    "msg": "SDK 授权页内嵌登录代理已收到 touchDown。"
                ])
            }
            loginButton.onTouchEndedInside = { [weak self] in
                self?.publishEvent(stage: "授权页内嵌代理", result: [
                    "resultCode": "CLIENT_EMBED_LOGIN_PRIMARY",
                    "msg": "SDK 授权页内嵌登录代理已收到触摸抬起。"
                ])
            }
            loginButton.onTap = { [weak self] in
                self?.publishEvent(stage: "授权页内嵌代理", result: [
                    "resultCode": "CLIENT_EMBED_LOGIN_TAP",
                    "msg": "SDK 授权页内嵌登录代理已响应点击。"
                ])
                self?.handleManualLoginProxyTap()
            }
            loginButton.onTouchCancelled = { [weak self] in
                self?.publishEvent(stage: "授权页内嵌代理", result: [
                    "resultCode": "CLIENT_EMBED_LOGIN_CANCELLED",
                    "msg": "SDK 授权页内嵌登录代理触摸被取消。"
                ])
            }
            loginButton.isHidden = true
            superCustomView.addSubview(loginButton)
            embeddedLoginProxyButton = loginButton
        }

        if embeddedFallbackProxyButton == nil {
            let fallbackButton = TouchProxyButton(type: .custom)
            fallbackButton.backgroundColor = UIColor.white.withAlphaComponent(0.01)
            fallbackButton.accessibilityIdentifier = "fuyao.oneclick.fallback.embedded"
            fallbackButton.onTouchDown = { [weak self] in
                self?.publishEvent(stage: "授权页内嵌代理", result: [
                    "resultCode": "CLIENT_EMBED_FALLBACK_TOUCH_DOWN",
                    "msg": "SDK 授权页内嵌其他方式代理已收到 touchDown。"
                ])
            }
            fallbackButton.onTap = { [weak self] in
                self?.publishEvent(stage: "授权页内嵌代理", result: [
                    "resultCode": "CLIENT_EMBED_FALLBACK_TAP",
                    "msg": "SDK 授权页内嵌其他方式代理已响应点击。"
                ])
                self?.handleManualFallbackTap()
            }
            fallbackButton.onTouchCancelled = { [weak self] in
                self?.publishEvent(stage: "授权页内嵌代理", result: [
                    "resultCode": "CLIENT_EMBED_FALLBACK_CANCELLED",
                    "msg": "SDK 授权页内嵌其他方式代理触摸被取消。"
                ])
            }
            fallbackButton.isHidden = true
            superCustomView.addSubview(fallbackButton)
            embeddedFallbackProxyButton = fallbackButton
        }

        superCustomView.bringSubviewToFront(embeddedLoginProxyButton ?? UIView())
        superCustomView.bringSubviewToFront(embeddedFallbackProxyButton ?? UIView())
        layoutEmbeddedProxyViews(loginFrame: loginFrameSnapshot, changeFrame: fallbackFrameSnapshot)
        publishEvent(stage: "授权页内嵌代理", result: [
            "resultCode": "CLIENT_EMBED_PROXY_READY",
            "msg": "已在 SDK 授权页 superCustomView 内挂载代理按钮，host=\(String(describing: type(of: superCustomView)))"
        ])
    }

    private func layoutEmbeddedProxyViews(loginFrame: CGRect?, changeFrame: CGRect?) {
        if let loginFrame = normalizedEmbeddedFrame(loginFrame, reference: discoveredLoginControl?.frame), !loginFrame.isEmpty {
            embeddedLoginProxyButton?.frame = loginFrame
            embeddedLoginProxyButton?.isHidden = false
            sdkCustomSuperview?.bringSubviewToFront(embeddedLoginProxyButton ?? UIView())
        }
        if let changeFrame = normalizedEmbeddedFrame(changeFrame, reference: discoveredFallbackControl?.frame), !changeFrame.isEmpty {
            embeddedFallbackProxyButton?.frame = changeFrame
            embeddedFallbackProxyButton?.isHidden = false
            sdkCustomSuperview?.bringSubviewToFront(embeddedFallbackProxyButton ?? UIView())
        }
    }

    private func normalizedEmbeddedFrame(_ frame: CGRect?, reference: CGRect?) -> CGRect? {
        guard let frame, !frame.isEmpty else { return nil }

        let directFrame = frame
        let offsetFrame: CGRect? = {
            guard let contentViewFrameSnapshot, !contentViewFrameSnapshot.isEmpty else { return nil }
            return frame.offsetBy(dx: contentViewFrameSnapshot.minX, dy: contentViewFrameSnapshot.minY)
        }()

        guard let reference, !reference.isEmpty else {
            return offsetFrame ?? directFrame
        }

        let directDistance = abs(directFrame.minX - reference.minX) + abs(directFrame.minY - reference.minY)
        if let offsetFrame {
            let offsetDistance = abs(offsetFrame.minX - reference.minX) + abs(offsetFrame.minY - reference.minY)
            return offsetDistance < directDistance ? offsetFrame : directFrame
        }
        return directFrame
    }

    private func installEmbeddedGestureProxy(on hostView: UIView) {
        if embeddedGestureHostView !== hostView {
            removeEmbeddedGestureProxy()
        }
        guard embeddedGestureHostView == nil else { return }

        let target = TouchProxyGestureTarget()
        target.onTap = { [weak self, weak hostView] point in
            guard let self, let hostView else { return }

            let loginFrame = self.embeddedLoginProxyButton?.frame ?? self.loginFrameSnapshot ?? .zero
            if !loginFrame.isEmpty, loginFrame.contains(point) {
                self.publishEvent(stage: "授权页内嵌手势", result: [
                    "resultCode": "CLIENT_EMBED_VIEW_LOGIN_TAP",
                    "msg": "SDK superCustomView 点击已命中登录区域，point=(\(Int(point.x)),\(Int(point.y))) frame=\(loginFrame.debugSummary) host=\(String(describing: type(of: hostView)))"
                ])
                self.handleManualLoginProxyTap()
                return
            }

            let fallbackFrame = self.embeddedFallbackProxyButton?.frame ?? self.fallbackFrameSnapshot ?? .zero
            if !fallbackFrame.isEmpty, fallbackFrame.contains(point) {
                self.publishEvent(stage: "授权页内嵌手势", result: [
                    "resultCode": "CLIENT_EMBED_VIEW_FALLBACK_TAP",
                    "msg": "SDK superCustomView 点击已命中其他方式区域，point=(\(Int(point.x)),\(Int(point.y))) frame=\(fallbackFrame.debugSummary) host=\(String(describing: type(of: hostView)))"
                ])
                self.handleManualFallbackTap()
            }
        }
        target.onPress = { [weak self] state, point in
            guard let self else { return }
            let loginFrame = self.embeddedLoginProxyButton?.frame ?? self.loginFrameSnapshot ?? .zero
            let fallbackFrame = self.embeddedFallbackProxyButton?.frame ?? self.fallbackFrameSnapshot ?? .zero

            switch state {
            case .began:
                if !loginFrame.isEmpty, loginFrame.contains(point) {
                    self.publishEvent(stage: "授权页内嵌手势", result: [
                        "resultCode": "CLIENT_EMBED_VIEW_LOGIN_TOUCH_DOWN",
                        "msg": "SDK superCustomView 触摸开始命中登录区域，point=(\(Int(point.x)),\(Int(point.y)))"
                    ])
                } else if !fallbackFrame.isEmpty, fallbackFrame.contains(point) {
                    self.publishEvent(stage: "授权页内嵌手势", result: [
                        "resultCode": "CLIENT_EMBED_VIEW_FALLBACK_TOUCH_DOWN",
                        "msg": "SDK superCustomView 触摸开始命中其他方式区域，point=(\(Int(point.x)),\(Int(point.y)))"
                    ])
                }
            case .cancelled, .failed:
                self.publishEvent(stage: "授权页内嵌手势", result: [
                    "resultCode": "CLIENT_EMBED_VIEW_TOUCH_CANCELLED",
                    "msg": "SDK superCustomView 触摸被取消，point=(\(Int(point.x)),\(Int(point.y)))"
                ])
            default:
                break
            }
        }

        let tap = UITapGestureRecognizer(target: target, action: #selector(TouchProxyGestureTarget.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = target

        let press = UILongPressGestureRecognizer(target: target, action: #selector(TouchProxyGestureTarget.handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = 20
        press.cancelsTouchesInView = false
        press.delegate = target

        hostView.addGestureRecognizer(tap)
        hostView.addGestureRecognizer(press)

        embeddedGestureHostView = hostView
        embeddedTapRecognizer = tap
        embeddedPressRecognizer = press
        embeddedGestureTarget = target
        publishEvent(stage: "授权页内嵌手势", result: [
            "resultCode": "CLIENT_EMBED_GESTURE_READY",
            "msg": "已在 SDK superCustomView 挂载手势代理，host=\(String(describing: type(of: hostView)))"
        ])
    }

    private func removeEmbeddedGestureProxy() {
        if let tap = embeddedTapRecognizer {
            embeddedGestureHostView?.removeGestureRecognizer(tap)
        }
        if let press = embeddedPressRecognizer {
            embeddedGestureHostView?.removeGestureRecognizer(press)
        }
        embeddedTapRecognizer = nil
        embeddedPressRecognizer = nil
        embeddedGestureTarget = nil
        embeddedGestureHostView = nil
    }

    private func publishHitTest(for targetView: UIView, in hostView: UIView, stage: String) {
        let targetFrame = targetView.convert(targetView.bounds, to: hostView)
        let point = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let hitView = hostView.hitTest(point, with: nil)
        let hitDescription = viewDescription(hitView)
        let targetDescription = viewDescription(targetView)
        publishEvent(stage: stage, result: [
            "resultCode": "CLIENT_HIT_TEST",
            "msg": "target=\(targetDescription) frame=\(targetFrame.debugSummary) point=(\(Int(point.x)),\(Int(point.y))) hit=\(hitDescription)"
        ])
    }

    private func viewDescription(_ view: UIView?) -> String {
        guard let view else { return "nil" }
        var description = String(describing: type(of: view))
        if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
            description += "#\(identifier)"
        }
        if let button = view as? UIButton, let title = button.title(for: .normal), !title.isEmpty {
            description += "[\(title)]"
        }
        return description
    }

    private func resolveTargetView(
        preferredFrame: CGRect?,
        in hostView: UIView,
        fallback: UIView,
        matcher: (String) -> Bool
    ) -> UIView {
        if let preferredFrame, !preferredFrame.isEmpty {
            let point = CGPoint(x: preferredFrame.midX, y: preferredFrame.midY)
            if let hitView = hostView.hitTest(point, with: nil),
               let matched = nearestMatchingView(from: hitView, matcher: matcher) {
                publishEvent(stage: "授权页目标解析", result: [
                    "resultCode": "CLIENT_TARGET_FROM_HIT",
                    "msg": "point=(\(Int(point.x)),\(Int(point.y))) hit=\(viewDescription(hitView)) resolved=\(viewDescription(matched))"
                ])
                return matched
            }
        }
        return fallback
    }

    private func nearestMatchingView(from view: UIView, matcher: (String) -> Bool) -> UIView? {
        var current: UIView? = view
        var depth = 0
        while let currentView = current, depth < 6 {
            if let label = displayText(for: currentView), matcher(label) {
                return currentView
            }
            current = currentView.superview
            depth += 1
        }
        return nil
    }

    private func describeControlMetadata(_ control: UIControl) -> String {
        let targetCount = control.allTargets.count
        let allEvents = control.allControlEvents.rawValue
        let touchUpActions = control.actions(forTarget: nil, forControlEvent: .touchUpInside)?.joined(separator: ",") ?? "none"
        let touchDownActions = control.actions(forTarget: nil, forControlEvent: .touchDown)?.joined(separator: ",") ?? "none"
        let gestureSummary = (control.gestureRecognizers ?? []).map { recognizer in
            String(describing: type(of: recognizer))
        }.joined(separator: ",")
        return "id=\(objectIdentifierString(control)) type=\(String(describing: type(of: control))) targets=\(targetCount) events=\(allEvents) touchUpInside=\(touchUpActions) touchDown=\(touchDownActions) gestures=\(gestureSummary.isEmpty ? "none" : gestureSummary)"
    }

    private func describeViewAncestry(for view: UIView) -> String {
        var parts: [String] = []
        var currentView: UIView? = view
        var depth = 0
        while let current = currentView, depth < 6 {
            let gestures = (current.gestureRecognizers ?? []).map { String(describing: type(of: $0)) }.joined(separator: ",")
            let label = displayText(for: current) ?? current.accessibilityIdentifier ?? "-"
            parts.append("\(depth):\(String(describing: type(of: current)))#\(objectIdentifierString(current)) frame=\(current.frame.debugSummary) interaction=\(current.isUserInteractionEnabled ? "YES" : "NO") label=\(label) gestures=\(gestures.isEmpty ? "none" : gestures)")
            currentView = current.superview
            depth += 1
        }
        return parts.joined(separator: " -> ")
    }

    private func objectIdentifierString(_ object: AnyObject) -> String {
        String(UInt(bitPattern: ObjectIdentifier(object)), radix: 16)
    }

    private func installGestureDiagnostics(on view: UIView, codePrefix: String) {
        for recognizer in view.gestureRecognizers ?? [] {
            let identifier = ObjectIdentifier(recognizer)
            guard observedGestureIDs.insert(identifier).inserted else { continue }

            let probe = GestureProbeTarget { [weak self, weak recognizer, weak view] state in
                guard let self, let recognizer, let view else { return }
                self.publishEvent(stage: "授权页手势诊断", result: [
                    "resultCode": "\(codePrefix)_GESTURE",
                    "msg": "view=\(String(describing: type(of: view))) recognizer=\(String(describing: type(of: recognizer))) state=\(state.rawValue)"
                ])
            }
            recognizer.addTarget(probe, action: #selector(GestureProbeTarget.handle(_:)))
            gestureProbeTargets.append(probe)

            publishEvent(stage: "授权页手势诊断", result: [
                "resultCode": "\(codePrefix)_HOOKED",
                "msg": "view=\(String(describing: type(of: view))) recognizer=\(String(describing: type(of: recognizer)))"
            ])
        }
    }

    private enum GestureForwardMode {
        case login
        case fallback
    }

    private func installGestureForwarding(on view: UIView, mode: GestureForwardMode) {
        for recognizer in view.gestureRecognizers ?? [] where recognizer is UITapGestureRecognizer {
            let identifier = ObjectIdentifier(recognizer)
            guard forwardedGestureIDs.insert(identifier).inserted else { continue }

            let forwarder = GestureForwardTarget { [weak self, weak recognizer, weak view] state in
                guard let self, let recognizer, let view else { return }
                guard state == .ended || state == .recognized else { return }

                switch mode {
                case .login:
                    self.publishEvent(stage: "授权页手势转发", result: [
                        "resultCode": "CLIENT_LOGIN_VIEW_FORWARD_TAP",
                        "msg": "识别到 SDK 登录按钮原生 tap 手势，view=\(String(describing: type(of: view))) recognizer=\(String(describing: type(of: recognizer)))"
                    ])
                    self.handleManualLoginProxyTap()
                case .fallback:
                    self.publishEvent(stage: "授权页手势转发", result: [
                        "resultCode": "CLIENT_FALLBACK_VIEW_FORWARD_TAP",
                        "msg": "识别到 SDK 其他方式按钮原生 tap 手势，view=\(String(describing: type(of: view))) recognizer=\(String(describing: type(of: recognizer)))"
                    ])
                    self.handleManualFallbackTap()
                }
            }
            recognizer.addTarget(forwarder, action: #selector(GestureForwardTarget.handle(_:)))
            gestureForwardTargets.append(forwarder)

            let code = mode == .login ? "CLIENT_LOGIN_VIEW_FORWARD_HOOKED" : "CLIENT_FALLBACK_VIEW_FORWARD_HOOKED"
            publishEvent(stage: "授权页手势转发", result: [
                "resultCode": code,
                "msg": "已挂载到 \(mode == .login ? "登录" : "其他方式") 按钮的原生 tap 手势，recognizer=\(String(describing: type(of: recognizer)))"
            ])
        }
    }

    private func installPassiveTouchBridge(on view: UIView, mode: GestureForwardMode) {
        let viewID = ObjectIdentifier(view)
        guard passiveTouchBridgeIDs.insert(viewID).inserted else { return }

        let target = TouchProxyGestureTarget()
        target.onTap = { [weak self, weak view] _ in
            guard let self, let view else { return }
            switch mode {
            case .login:
                self.publishEvent(stage: "授权页被动触摸桥", result: [
                    "resultCode": "CLIENT_LOGIN_PASSIVE_TAP",
                    "msg": "真实 SDK 登录按钮已被动收到 tap，view=\(String(describing: type(of: view)))"
                ])
                self.handleManualLoginProxyTap()
            case .fallback:
                self.publishEvent(stage: "授权页被动触摸桥", result: [
                    "resultCode": "CLIENT_FALLBACK_PASSIVE_TAP",
                    "msg": "真实 SDK 其他方式按钮已被动收到 tap，view=\(String(describing: type(of: view)))"
                ])
                self.handleManualFallbackTap()
            }
        }
        target.onPress = { [weak self, weak view] state, _ in
            guard let self, let view else { return }
            guard state == .began else { return }
            switch mode {
            case .login:
                self.publishEvent(stage: "授权页被动触摸桥", result: [
                    "resultCode": "CLIENT_LOGIN_PASSIVE_TOUCH_DOWN",
                    "msg": "真实 SDK 登录按钮已被动收到 touchDown，view=\(String(describing: type(of: view)))"
                ])
            case .fallback:
                self.publishEvent(stage: "授权页被动触摸桥", result: [
                    "resultCode": "CLIENT_FALLBACK_PASSIVE_TOUCH_DOWN",
                    "msg": "真实 SDK 其他方式按钮已被动收到 touchDown，view=\(String(describing: type(of: view)))"
                ])
            }
        }

        let tap = UITapGestureRecognizer(target: target, action: #selector(TouchProxyGestureTarget.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = target

        let press = UILongPressGestureRecognizer(target: target, action: #selector(TouchProxyGestureTarget.handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = 20
        press.cancelsTouchesInView = false
        press.delegate = target

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(press)
        passiveTouchBridgeTargets.append(target)

        let code = mode == .login ? "CLIENT_LOGIN_PASSIVE_HOOKED" : "CLIENT_FALLBACK_PASSIVE_HOOKED"
        publishEvent(stage: "授权页被动触摸桥", result: [
            "resultCode": code,
            "msg": "已直接挂载到真实 SDK \(mode == .login ? "登录" : "其他方式")按钮，view=\(String(describing: type(of: view)))"
        ])
    }

    private func findSDKLoginControlAcrossWindows(in hostView: UIView) -> UIControl? {
        collectControls(in: hostView).first { control in
            if control === customLoginProxyButton || control === customFallbackButton {
                return false
            }
            let title = displayText(for: control) ?? ""
            return title.contains("一键登录") || title == "登录" || title.contains("本机号码")
        }
    }

    private func findFallbackControlAcrossWindows(in hostView: UIView) -> UIControl? {
        collectControls(in: hostView).first { control in
            if control === customLoginProxyButton || control === customFallbackButton {
                return false
            }
            let title = displayText(for: control) ?? ""
            return title.contains("其他方式") || title.contains("切换")
        }
    }

    private func findLabeledLoginView(in hostView: UIView) -> UIView? {
        collectLabeledViews(in: hostView).first(where: { _, label in
            label.contains("一键登录") || label.contains("本机号码")
        })?.0
    }

    private func findLabeledFallbackView(in hostView: UIView) -> UIView? {
        collectLabeledViews(in: hostView).first(where: { _, label in
            label.contains("其他方式") || label.contains("切换")
        })?.0
    }

    private func finish(with result: Result<OneClickAuthSDKResult, Error>) {
        authorizationPresentationTimeoutTask?.cancel()
        authorizationPresentationTimeoutTask = nil
        tokenResultTimeoutTask?.cancel()
        tokenResultTimeoutTask = nil
        hasPresentedAuthorizationPage = false
        isAwaitingTokenResult = false
        cancelProxyRefreshTasks()
        removeHostGestureProxy()
        removeEmbeddedGestureProxy()
        customLoginProxyButton?.removeFromSuperview()
        customLoginProxyButton = nil
        customFallbackButton?.removeFromSuperview()
        customFallbackButton = nil
        embeddedLoginProxyButton?.removeFromSuperview()
        embeddedLoginProxyButton = nil
        embeddedFallbackProxyButton?.removeFromSuperview()
        embeddedFallbackProxyButton = nil
        sdkCustomSuperview = nil
        authorizationControllerSnapshot = nil
        authorizationWindowSnapshot = nil
        discoveredLoginControl = nil
        discoveredFallbackControl = nil
        observedLoginControl = nil
        observedFallbackControl = nil
        gestureProbeTargets.removeAll()
        observedGestureIDs.removeAll()
        gestureForwardTargets.removeAll()
        forwardedGestureIDs.removeAll()
        passiveTouchBridgeTargets.removeAll()
        passiveTouchBridgeIDs.removeAll()
        loginFrameSnapshot = nil
        fallbackFrameSnapshot = nil
        overlayHostView = nil
        OneClickAuthSDKBridge.clear(self)
        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private struct DeviceEnvironment {
    let hasSIM: Bool
    let cellularEnabled: Bool
    let wwanOpen: Bool
    let carrierName: String
    let networkType: String

    var isAvailable: Bool {
        hasSIM && (cellularEnabled || wwanOpen)
    }

    var summary: String {
        "SIM=\(hasSIM ? "YES" : "NO"), 蜂窝数据=\(cellularEnabled ? "ON" : "OFF"), WWAN=\(wwanOpen ? "ON" : "OFF"), 运营商=\(carrierName), 网络=\(networkType)"
    }
}

private final class TouchProxyButton: UIButton {
    var onTouchDown: (() -> Void)?
    var onTouchEndedInside: (() -> Void)?
    var onTap: (() -> Void)?
    var onTouchCancelled: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
#if DEBUG
        print("[OneClickLogin][RawTouch] TouchProxyButton touchesBegan id=\(accessibilityIdentifier ?? "nil")")
#endif
        onTouchDown?()
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let isInside = touches.first.map { bounds.contains($0.location(in: self)) } ?? false
#if DEBUG
        print("[OneClickLogin][RawTouch] TouchProxyButton touchesEnded id=\(accessibilityIdentifier ?? "nil") inside=\(isInside ? "YES" : "NO")")
#endif
        if isInside {
            onTouchEndedInside?()
            onTap?()
        }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
#if DEBUG
        print("[OneClickLogin][RawTouch] TouchProxyButton touchesCancelled id=\(accessibilityIdentifier ?? "nil")")
#endif
        onTouchCancelled?()
        super.touchesCancelled(touches, with: event)
    }
}

private final class TouchProxyGestureTarget: NSObject, UIGestureRecognizerDelegate {
    var onTap: ((CGPoint) -> Void)?
    var onPress: ((UIGestureRecognizer.State, CGPoint) -> Void)?

    @objc
    func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view = recognizer.view else { return }
#if DEBUG
        print("[OneClickLogin][RawTouch] Gesture tap host=\(String(describing: type(of: view))) point=\(recognizer.location(in: view))")
#endif
        onTap?(recognizer.location(in: view))
    }

    @objc
    func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        guard let view = recognizer.view else { return }
#if DEBUG
        print("[OneClickLogin][RawTouch] Gesture press state=\(recognizer.state.rawValue) host=\(String(describing: type(of: view))) point=\(recognizer.location(in: view))")
#endif
        onPress?(recognizer.state, recognizer.location(in: view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        true
    }
}

private final class GestureProbeTarget: NSObject {
    private let onStateChange: (UIGestureRecognizer.State) -> Void

    init(onStateChange: @escaping (UIGestureRecognizer.State) -> Void) {
        self.onStateChange = onStateChange
    }

    @objc
    func handle(_ recognizer: UIGestureRecognizer) {
        onStateChange(recognizer.state)
    }
}

private final class GestureForwardTarget: NSObject {
    private let onStateChange: (UIGestureRecognizer.State) -> Void

    init(onStateChange: @escaping (UIGestureRecognizer.State) -> Void) {
        self.onStateChange = onStateChange
    }

    @objc
    func handle(_ recognizer: UIGestureRecognizer) {
        onStateChange(recognizer.state)
    }
}

private func sdkAwaitBasePresenterAfterDismiss(
    timeout: TimeInterval = 2.0,
    pollInterval: UInt64 = 80_000_000
) async throws -> UIViewController {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        let rootController = await MainActor.run {
            UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }

        if let rootController,
           rootController.presentedViewController == nil,
           rootController.view.window != nil {
            return await MainActor.run {
                rootController.topMostPresentedController
            }
        }

        try? await Task.sleep(nanoseconds: pollInterval)
    }

    print("[OneClickLogin] stage=展示容器 code=CLIENT_BASE_PRESENTER_TIMEOUT message=关闭当前登录页后，底层宿主 controller 仍未回到可展示状态。")
    throw OneClickAuthError.sdkCallback(
        stage: "展示容器",
        code: "CLIENT_BASE_PRESENTER_TIMEOUT",
        message: "关闭当前登录页后，底层宿主 controller 仍未回到可展示状态，暂时无法按最小链路拉起号码认证授权页。"
    )
}

private func sdkDismissalPresenterCandidates(from controller: UIViewController?) -> [UIViewController] {
    guard let controller else { return [] }

    let rawCandidates = [
        controller.parent?.presentingViewController?.topMostPresentedController,
        controller.presentingViewController?.topMostPresentedController,
        controller.parent?.presentingViewController,
        controller.presentingViewController,
        controller.parent,
        controller.view.window?.rootViewController,
        controller
    ].compactMap { $0 }

    var unique: [UIViewController] = []
    for candidate in rawCandidates where !unique.contains(where: { $0 === candidate }) {
        unique.append(candidate)
    }
    return unique
}

private func sdkPresenterCandidates(from controller: UIViewController) -> [UIViewController] {
    let rawCandidates = [
        controller.view.window?.rootViewController?.topMostPresentedControllerIfAvailable,
        controller.parent?.presentedViewController?.topMostPresentedControllerIfAvailable,
        controller.presentingViewController?.presentedViewController?.topMostPresentedControllerIfAvailable,
        controller.parent?.topMostPresentedControllerIfAvailable,
        controller.presentingViewController?.topMostPresentedControllerIfAvailable,
        controller.topMostPresentedControllerIfAvailable,
        controller.parent,
        controller.presentingViewController,
        controller.view.window?.rootViewController,
        controller
    ].compactMap { $0 }

    var unique: [UIViewController] = []
    for candidate in rawCandidates where !unique.contains(where: { $0 === candidate }) {
        unique.append(candidate)
    }
    return unique
}

private func sdkPresenterIsPreferred(_ controller: UIViewController) -> Bool {
    let typeName = String(describing: type(of: controller))
    return !typeName.contains("LoginPresenterResolverController")
}

#elseif canImport(UIKit)
private func sdkAwaitBasePresenterAfterDismiss(
    timeout: TimeInterval = 2.0,
    pollInterval: UInt64 = 80_000_000
) async throws -> UIViewController {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        let rootController = await MainActor.run {
            UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }

        if let rootController,
           rootController.presentedViewController == nil,
           rootController.view.window != nil {
            return await MainActor.run {
                rootController.topMostPresentedController
            }
        }

        try? await Task.sleep(nanoseconds: pollInterval)
    }

    print("[OneClickLogin] stage=展示容器 code=CLIENT_BASE_PRESENTER_TIMEOUT message=关闭当前登录页后，底层宿主 controller 仍未回到可展示状态。")
    throw OneClickAuthError.sdkCallback(
        stage: "展示容器",
        code: "CLIENT_BASE_PRESENTER_TIMEOUT",
        message: "关闭当前登录页后，底层宿主 controller 仍未回到可展示状态，暂时无法按最小链路拉起号码认证授权页。"
    )
}

private func sdkDismissalPresenterCandidates(from controller: UIViewController?) -> [UIViewController] {
    guard let controller else { return [] }

    let rawCandidates = [
        controller.parent?.presentingViewController?.topMostPresentedController,
        controller.presentingViewController?.topMostPresentedController,
        controller.parent?.presentingViewController,
        controller.presentingViewController,
        controller.parent,
        controller.view.window?.rootViewController,
        controller
    ].compactMap { $0 }

    var unique: [UIViewController] = []
    for candidate in rawCandidates where !unique.contains(where: { $0 === candidate }) {
        unique.append(candidate)
    }
    return unique
}

private func sdkPresenterCandidates(from controller: UIViewController) -> [UIViewController] {
    let rawCandidates = [
        controller.view.window?.rootViewController?.topMostPresentedControllerIfAvailable,
        controller.parent?.presentedViewController?.topMostPresentedControllerIfAvailable,
        controller.presentingViewController?.presentedViewController?.topMostPresentedControllerIfAvailable,
        controller.parent?.topMostPresentedControllerIfAvailable,
        controller.presentingViewController?.topMostPresentedControllerIfAvailable,
        controller.topMostPresentedControllerIfAvailable,
        controller.parent,
        controller.presentingViewController,
        controller.view.window?.rootViewController,
        controller
    ].compactMap { $0 }

    var unique: [UIViewController] = []
    for candidate in rawCandidates where !unique.contains(where: { $0 === candidate }) {
        unique.append(candidate)
    }
    return unique
}

private func sdkPresenterIsPreferred(_ controller: UIViewController) -> Bool {
    let typeName = String(describing: type(of: controller))
    return !typeName.contains("LoginPresenterResolverController")
}

@MainActor
private enum OneClickAuthSDKBridge {
    static func startLogin(
        presenter: UIViewController,
        onProgress: @escaping @MainActor (OneClickSDKProgress) -> Void,
        onEvent: @escaping @MainActor (OneClickSDKEvent) -> Void
    ) async throws -> OneClickAuthSDKResult {
        _ = presenter
        _ = onProgress
        _ = onEvent
        throw OneClickAuthError.sdkNotIntegrated
    }
}
#else
private enum OneClickAuthSDKBridge {
    static func startLogin(
        presenter: Any,
        onProgress: @escaping (OneClickSDKProgress) -> Void,
        onEvent: @escaping (OneClickSDKEvent) -> Void
    ) async throws -> OneClickAuthSDKResult {
        _ = presenter
        _ = onProgress
        _ = onEvent
        throw OneClickAuthError.sdkNotIntegrated
    }
}
#endif

#if canImport(UIKit)
private struct LoginPresenterResolver: UIViewControllerRepresentable {
    let onResolve: @MainActor (UIViewController) -> Void

    func makeUIViewController(context: Context) -> LoginPresenterResolverController {
        let controller = LoginPresenterResolverController()
        controller.onResolve = onResolve
        return controller
    }

    func updateUIViewController(_ uiViewController: LoginPresenterResolverController, context: Context) {
        uiViewController.onResolve = onResolve
        uiViewController.resolveIfNeeded()
    }
}

private final class LoginPresenterResolverController: UIViewController {
    var onResolve: (@MainActor (UIViewController) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.alpha = 0.001
        view.isUserInteractionEnabled = false
        definesPresentationContext = true
        providesPresentationContextTransitionStyle = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resolveIfNeeded()
    }

    func resolveIfNeeded() {
        guard let onResolve else { return }
        let controller: UIViewController
        controller = parent ?? presentingViewController ?? self
        Task { @MainActor in
            onResolve(controller)
        }
    }
}

private extension UIViewController {
    var topMostPresentedController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostPresentedController
        }
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topMostPresentedController ?? navigation
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostPresentedController ?? tab
        }
        return self
    }

    var topMostPresentedControllerIfAvailable: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostPresentedControllerIfAvailable
        }
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topMostPresentedControllerIfAvailable ?? navigation
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostPresentedControllerIfAvailable ?? tab
        }
        if let child = children.last {
            return child.topMostPresentedControllerIfAvailable
        }
        return self
    }
}

private extension CGRect {
    var debugSummary: String {
        "(\(Int(origin.x)),\(Int(origin.y)),\(Int(size.width)),\(Int(size.height)))"
    }
}
#endif
