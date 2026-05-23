import SwiftUI

struct WelcomeView: View {
    @ObservedObject var appState: AppState
    @StateObject private var network = NetworkMonitor()

    @State private var tab: WelcomeTab = .login

    enum WelcomeTab { case login, register }

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.85, green: 0.93, blue: 1.0)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // MARK: Branding
                    Image("logo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 160, height: 160)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 4))
                        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 6)
                        .padding(.top, 56)
                        .padding(.bottom, 16)

                    VStack(spacing: 4) {
                        Text("BikeMap DC")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("DC Collaborative Bike Map")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 28)

                    // MARK: Auth card
                    VStack(spacing: 0) {
                        // Tab picker
                        Picker("", selection: $tab) {
                            Text("Sign in").tag(WelcomeTab.login)
                            Text("Create account").tag(WelcomeTab.register)
                        }
                        .pickerStyle(.segmented)
                        .padding(16)

                        Divider()

                        if tab == .login {
                            WelcomeLoginForm(appState: appState)
                        } else {
                            WelcomeRegisterForm(appState: appState)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 20)

                    // MARK: Browse without account (Apple 5.1.1(v) compliance)
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appState.guestAccess = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "map")
                            Text("Continue as a guest")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                    Text("You can sign in later to add points, report thefts, or register your bikes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, -4)

                }
                .padding(.bottom, 40)
            }

            // Offline banner
            if !network.isConnected {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.subheadline.weight(.semibold))
                        Text("No internet connection")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange, ignoresSafeAreaEdges: [])
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: network.isConnected)
            }
        }
    }
}

// MARK: - Login Form

private struct WelcomeLoginForm: View {
    @ObservedObject var appState: AppState

    @State private var email    = ""
    @State private var password = ""
    @State private var error    = ""
    @State private var loading  = false
    @State private var showPw   = false

    // Forgot password
    @State private var showForgot      = false
    @State private var forgotEmail     = ""
    @State private var forgotLoading   = false
    @State private var forgotSent      = false
    @State private var forgotError     = ""

    var body: some View {
        VStack(spacing: 14) {
            fieldGroup {
                styledField("Email", text: $email, content: .emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Divider().padding(.leading, 16)
                HStack {
                    Group {
                        if showPw {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .padding(.leading, 16)
                    .frame(height: 44)
                    Button { showPw.toggle() } label: {
                        Image(systemName: showPw ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 16)
                    }
                }
            }

            // Forgot password link
            Button {
                forgotEmail = email
                forgotSent  = false
                forgotError = ""
                showForgot  = true
            } label: {
                Text("Forgot my password")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .padding(.top, -4)

            if !error.isEmpty {
                Label(error, systemImage: "xmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if loading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign in").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(email.isEmpty || password.isEmpty || loading)
            .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)
        }
        .padding(16)
        .sheet(isPresented: $showForgot) {
            ForgotPasswordSheet(
                email: $forgotEmail,
                loading: $forgotLoading,
                sent: $forgotSent,
                errorMsg: $forgotError,
                appState: appState
            )
        }
    }

    private func submit() async {
        error = ""; loading = true
        defer { loading = false }
        do {
            try await appState.signIn(email: email.lowercased().trimmingCharacters(in: .whitespaces),
                                      password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Forgot Password Sheet

private struct ForgotPasswordSheet: View {
    @Binding var email:    String
    @Binding var loading:  Bool
    @Binding var sent:     Bool
    @Binding var errorMsg: String
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if sent {
                    // Success state
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.badge.checkmark.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                        Text("Email sent!")
                            .font(.title2.weight(.bold))
                        Text("Check your inbox at **\(email)** and follow the instructions to reset your password.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 24)
                } else {
                    // Input state
                    VStack(spacing: 8) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text("Reset password")
                            .font(.title2.weight(.bold))
                        Text("Enter your email and we'll send a link to create a new password.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                    }
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 0.5))
                    .padding(.horizontal, 24)

                    if !errorMsg.isEmpty {
                        Label(errorMsg, systemImage: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)
                    }

                    Button {
                        Task { await sendReset() }
                    } label: {
                        Group {
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Send link").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                    .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                    .opacity(email.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func sendReset() async {
        errorMsg = ""; loading = true
        defer { loading = false }
        do {
            try await appState.resetPassword(email: email.lowercased().trimmingCharacters(in: .whitespaces))
            sent = true
        } catch {
            errorMsg = String(localized: "Could not send. Check the email and try again.")
        }
    }
}

// MARK: - Register Form

private struct WelcomeRegisterForm: View {
    @ObservedObject var appState: AppState

    @State private var username    = ""
    @State private var email       = ""
    @State private var password    = ""
    @State private var confirm     = ""
    @State private var avatar      = "bobcat"
    @State private var error       = ""
    @State private var loading     = false
    @State private var showPw      = false
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 14) {
            fieldGroup {
                styledField("Username", text: $username, content: .username)
                Divider().padding(.leading, 16)
                styledField("Email", text: $email, content: .emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Divider().padding(.leading, 16)
                HStack {
                    Group {
                        if showPw {
                            TextField("Password (min. 6 characters)", text: $password)
                        } else {
                            SecureField("Password (min. 6 characters)", text: $password)
                        }
                    }
                    .textContentType(.newPassword)
                    .padding(.leading, 16)
                    .frame(height: 44)
                    Button { showPw.toggle() } label: {
                        Image(systemName: showPw ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 16)
                    }
                }
                Divider().padding(.leading, 16)
                HStack {
                    Group {
                        if showConfirm {
                            TextField("Confirm password", text: $confirm)
                        } else {
                            SecureField("Confirm password", text: $confirm)
                        }
                    }
                    .textContentType(.newPassword)
                    .padding(.leading, 16)
                    .frame(height: 44)
                    Button { showConfirm.toggle() } label: {
                        Image(systemName: showConfirm ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 16)
                    }
                }
            }

            // Avatar picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose your avatar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                    spacing: 12
                ) {
                    ForEach(avatarList, id: \.id) { av in
                        Button { avatar = av.id } label: {
                            VStack(spacing: 3) {
                                AvatarView(id: av.id, size: 48)
                                    .overlay(Circle().stroke(avatar == av.id ? Color.green : Color.clear, lineWidth: 3))
                                Text(av.name)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !error.isEmpty {
                Label(error, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if loading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Create account").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(username.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty || loading)
            .opacity(username.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty ? 0.5 : 1)
        }
        .padding(16)
    }

    private func submit() async {
        error = ""; loading = true
        defer { loading = false }
        let name = username.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3 else { error = "Nome deve ter ao menos 3 caracteres."; return }
        guard email.contains("@") && email.contains(".") else { error = String(localized: "Invalid email."); return }
        guard password.count >= 6 else { error = String(localized: "Password must be at least 6 characters."); return }
        guard password == confirm else { error = String(localized: "Passwords don't match."); return }
        do {
            try await appState.register(email: email.lowercased().trimmingCharacters(in: .whitespaces),
                                         password: password, username: name, avatar: avatar)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Helpers

private func fieldGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
        content()
    }
    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 0.5))
}

private func styledField(_ placeholder: String, text: Binding<String>, content: UITextContentType) -> some View {
    TextField(placeholder, text: text)
        .textContentType(content)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .padding(.horizontal, 16)
        .frame(height: 44)
}
