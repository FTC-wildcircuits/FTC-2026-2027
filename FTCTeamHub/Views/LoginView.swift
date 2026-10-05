//
//  LoginView.swift
//  FTCTeamHub
//
//  Sign in and sign up, backed by AuthenticationManager and a native
//  credential flow.
//

import SwiftUI
import UIKit
import SwiftData

struct LoginView: View {
    @Environment(AuthenticationManager.self) private var authManager
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
    @State private var avatarColor: AvatarColor = .red
    @State private var passwordVisible = false
    @FocusState private var focusedField: Field?

    private var isSigningUp: Bool {
        mode == .signUp
    }

    private var teamName: String {
        let name = teamSettingsList.first?.teamName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Wild Circuits" : name
    }

    private var teamNumber: Int {
        teamSettingsList.first?.teamNumber ?? 24211
    }

    private var seasonName: String {
        teamSettingsList.first?.seasonName ?? "2026–27"
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
                            .transition(.move(edge: .top).combined(with: .opacity))
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
            .tint(FTCBrand.orange)
            .animation(.easeInOut(duration: 0.2), value: isSigningUp)
        }
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(FTCBrand.orange)
                    .frame(width: 3, height: 27)
                VStack(alignment: .leading, spacing: 3) {
                    Text(teamName.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(1.1)
                    Text("FIRST TECH CHALLENGE  /  TEAM \(teamNumber)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.15)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(seasonName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var welcomeHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isSigningUp ? "Create account" : "Sign in")
                .font(.system(size: 34, weight: .bold))
                .tracking(-1.1)
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
        VStack(alignment: .leading, spacing: 20) {
            if isSigningUp {
                labeledField("Full name", symbol: "person", field: .name) {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = .email }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
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
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(focusedField == field ? FTCBrand.accentText.opacity(0.7) : FTCBrand.line,
                            lineWidth: focusedField == field ? 1.5 : 1)
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
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(FTCBrand.line, lineWidth: 1)
                    }
                }
                .accessibilityLabel("Team role, \(role.rawValue)")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Member color")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Shown next to your name across team lists and activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FTCColorPicker(selection: $avatarColor)
            }
        }
    }

    private func errorNotice(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(FTCBrand.accentText)
        }
        .font(.footnote)
        .foregroundStyle(.primary)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(FTCBrand.accentText.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryAction: some View {
        Button(action: submit) {
            HStack {
                Text(isSigningUp ? "Create account" : "Sign in")
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(FTCBrand.orange, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isValid)
        .opacity(isValid ? 1 : 0.52)
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
            .foregroundStyle(FTCBrand.accentText)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
    }

    private var privacyNote: some View {
        VStack(spacing: 11) {
            Rectangle()
                .fill(FTCBrand.line)
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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                avatarColor: avatarColor
            )
        }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
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
