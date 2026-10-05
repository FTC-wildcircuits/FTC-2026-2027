import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AuthenticationManager.self) private var authManager

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
    @State private var avatarColor: AvatarColor = .blue
    @State private var passwordVisible = false
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
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let error = authManager.errorMessage {
                        errorNotice(error)
                            .padding(.top, 18)
                    }
                    primaryAction
                        .padding(.top, 24)
                    modeAction
                        .padding(.top, 20)
                    privacyNote
                        .padding(.top, 34)
                }
                .frame(maxWidth: 440, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 26)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                FTCBrandMark(size: 46)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("WILD CIRCUITS")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.primary)
                    Text("FIRST TECH CHALLENGE  ·  24211")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("2026–27")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)

            Rectangle()
                .fill(FTCBrand.line)
                .frame(height: 1)
        }
    }

    private var welcomeHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isSigningUp ? "Join the team." : "Welcome back.")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .tracking(-1.2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(isSigningUp
                 ? "Create your member profile to get started."
                 : "Sign in to your team workspace.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 36)
        .padding(.bottom, 30)
    }

    private var credentialFields: some View {
        VStack(alignment: .leading, spacing: 19) {
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
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
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
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
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

            HStack {
                Text("Profile color")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                ForEach(AvatarColor.allCases) { swatch in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        avatarColor = swatch
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 27, height: 27)
                            .overlay {
                                if avatarColor == swatch {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(3)
                            .overlay {
                                Circle()
                                    .stroke(avatarColor == swatch ? Color.primary : .clear,
                                            lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(swatch.rawValue) profile color")
                    .accessibilityAddTraits(avatarColor == swatch ? .isSelected : [])
                }
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
                    .font(.system(.body, design: .rounded, weight: .semibold))
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
            Label("Your account is stored on this iPhone.", systemImage: "iphone")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Team data stays on this device unless cloud sync is enabled.")
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
