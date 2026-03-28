import SwiftUI

struct LoginView: View {
    @EnvironmentObject var profileStore: UserProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var phone = ""
    @State private var code = ""
    @State private var countdown = 0
    @State private var showError = false
    @State private var errorMessage = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)
                    Text("AI有声书")
                        .font(.largeTitle)
                        .bold()
                    Text("登录后享受完整体验")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // 输入区
                VStack(spacing: 16) {
                    // 手机号
                    HStack {
                        Image(systemName: "phone")
                            .foregroundColor(.secondary)
                        TextField("请输入手机号", text: $phone)
                            .keyboardType(.phonePad)
                            .onChange(of: phone) { newValue in
                                // 限制11位数字
                                let filtered = String(newValue.filter { $0.isNumber }.prefix(11))
                                if filtered != newValue { phone = filtered }
                            }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // 验证码
                    HStack {
                        Image(systemName: "lock")
                            .foregroundColor(.secondary)
                        TextField("请输入验证码", text: $code)
                            .keyboardType(.numberPad)
                            .onChange(of: code) { newValue in
                                let filtered = String(newValue.filter { $0.isNumber }.prefix(4))
                                if filtered != newValue { code = filtered }
                            }
                        Button {
                            sendCode()
                        } label: {
                            Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                                .font(.subheadline)
                                .foregroundColor(countdown > 0 ? .secondary : .accentColor)
                        }
                        .disabled(countdown > 0 || phone.count != 11)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                // 登录按钮
                Button {
                    doLogin()
                } label: {
                    Text("登  录")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(loginEnabled ? Color.accentColor : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!loginEnabled)
                .padding(.horizontal)

                // 提示
                Text("开发模式：验证码固定为 1234")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("提示", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onReceive(timer) { _ in
                if countdown > 0 { countdown -= 1 }
            }
        }
    }

    private var loginEnabled: Bool {
        phone.count == 11 && code.count == 4
    }

    private func sendCode() {
        guard phone.count == 11 else { return }
        countdown = 60
    }

    private func doLogin() {
        guard phone.count == 11 else {
            errorMessage = "请输入正确的手机号"
            showError = true
            return
        }
        guard code == "1234" else {
            errorMessage = "验证码错误"
            showError = true
            return
        }
        profileStore.login(phone: phone)
        dismiss()
    }
}
