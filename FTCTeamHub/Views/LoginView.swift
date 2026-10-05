//
//  LoginView.swift
//  FTCTeamHub
//
//  Sign in and sign up, backed by AuthenticationManager and a native
//  credential flow.
//

import SwiftUI
import SwiftData

struct LoginView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var teamSettingsList: [TeamSettings]

    private enum Mode {
        case signIn
        case signUp
    }

    private enum Field: Hashable {
        case name
        case email
        case password
    }

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role: TeamRole = .builder
    @State private var passwordVisible = false
    @State private var submitFeedbackCount = 0
    @FocusState private var focusedField: Field?

    private var isSigningUp: Bool {
        mode == .signUp
    }

    private var isValid: Bool {
        let hasCredentials = email.contains("@") && password.count >= 4
        return hasCredentials && (!isSigningUp || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    identityHeader
                    welcomeHeading
                    credentialFields
                    if isSigningUp {
                        profileFields
                            .padding(.top, 22)
                            .transition(
                                reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
                            )
                    }
                    if let error = authManager.errorMessage {
                        errorNotice(error)
                            .padding(.top, 18)
                    }
                    primaryAction
                        .padding(.top, 28)
                    modeAction
                        .padding(.top, 18)
                    privacyNote
                        .padding(.top, 30)
                }
                .frame(maxWidth: 440, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .tint(Color.accentColor)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24),
                value: isSigningUp
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: submitFeedbackCount)
            .sensoryFeedback(.error, trigger: authManager.errorMessage)
        }
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: FTCDesign.space4) {
            if let settings = teamSettingsList.first {
                Text(settings.teamName)
                    .font(.headline)
                Text("First Tech Challenge · Team \(settings.teamNumber) · \(settings.seasonName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Team account")
                    .font(.headline)
            }
        }
    }

    private var welcomeHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isSigningUp ? "Create account" : "Sign in")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(isSigningUp
                 ? "Set up your team member profile."
                 : "Use your team account to continue.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 52)
        .padding(.bottom, 34)
    }

    private var credentialFields: some View {
        VStack(alignment: .leading, spacing: FTCDesign.space20) {
            if isSigningUp {
                labeledField("Full name", symbol: "person", field: .name) {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = .email }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            labeledField("Email", symbol: "envelope", field: .email) {
                TextField("name@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
            }

            labeledField("Password", symbol: "lock", field: .password) {
                HStack(spacing: 8) {
                    Group {
                        if passwordVisible {
                            TextField("Enter your password", text: $password)
                        } else {
                            SecureField("Enter your password", text: $password)
                        }
                    }
                    .textContentType(isSigningUp ? .newPassword : .password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit(submit)

                    Button {
                        passwordVisible.toggle()
                        focusedField = .password
                    } label: {
                        Image(systemName: passwordVisible ? "eye.slash" : "eye")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(passwordVisible ? "Hide password" : "Show password")
                }
            }
        }
    }

    private func labeledField<Content: View>(
        _ title: String,
        symbol: String,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                content()
                    .font(.body)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(title)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: FTCDesign.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FTCDesign.controlRadius, style: .continuous)
                    .stroke(focusedField == field ? Color.accentColor : FTCDesign.separator,
                            lineWidth: focusedField == field ? 2 : 1)
            }
        }
    }

    private var profileFields: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Team role")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Menu {
                    ForEach(TeamRole.allCases) { option in
                        Button {
                            role = option
                        } label: {
                            Label(option.rawValue, systemImage: option.systemImage)
                        }
                    }
                } label: {
                    HStack {
                        Label(role.rawValue, systemImage: role.systemImage)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: FTCDesign.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FTCDesign.controlRadius, style: .continuous)
                            .stroke(FTCDesign.separator, lineWidth: 1)
                    }
                }
                .accessibilityLabel("Team role, \(role.rawValue)")
            }

        }
    }

    private func errorNotice(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
        .font(.footnote)
        .foregroundStyle(.primary)
        .padding(FTCDesign.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FTCDesign.secondarySurface,
                    in: RoundedRectangle(cornerRadius: FTCDesign.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var primaryAction: some View {
        Button(action: submit) {
            HStack {
                Text(isSigningUp ? "Create account" : "Sign in")
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.right")
            }.frame(minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isValid)
        .accessibilityHint(isValid ? "" : "Enter a valid email and password to continue")
    }

    private var modeAction: some View {
        HStack(spacing: 4) {
            Text(isSigningUp ? "Already have an account?" : "New to the team?")
                .foregroundStyle(.secondary)
            Button(isSigningUp ? "Sign in" : "Create an account") {
                authManager.errorMessage = nil
                focusedField = nil
                mode = isSigningUp ? .signIn : .signUp
            }
            .fontWeight(.semibold)
            .foregroundStyle(Color.accentColor)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
    }

    private var privacyNote: some View {
        VStack(spacing: 11) {
            Rectangle()
                .fill(FTCDesign.separator)
                .frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(.caption)
                Text("Local team account")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            Text("Team records stay on this device unless cloud sync is enabled.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard isValid else { return }
        focusedField = nil
        submitFeedbackCount += 1
        switch mode {
        case .signIn:
            authManager.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        case .signUp:
            authManager.signUp(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                role: role,
                avatarColor: .red
            )
        }
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    authManager.signOut()
    return LoginView()
        .modelContainer(container)
        .environment(authManager)
}
