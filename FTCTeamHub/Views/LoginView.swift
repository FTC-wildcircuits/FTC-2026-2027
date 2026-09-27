import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AuthenticationManager.self) private var authManager

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Create Account"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role: TeamRole = .builder
    @State private var avatarColor: AvatarColor = .blue
    @State private var passwordVisible = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    identityHeader
                    signInPanel
                    footer
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("WC")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(-1)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(FTCBrand.orange, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text("WILD CIRCUITS")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                    Text("FIRST TECH CHALLENGE     /     24211")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("2026—27")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 18)

            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
                .padding(.top, 18)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TEAM\nWORKSPACE")
                        .font(.system(size: 37, weight: .black, design: .rounded))
                        .tracking(-1.8)
                        .lineSpacing(-5)
                        .foregroundStyle(FTCBrand.midnight)
                    Text("Robot · Strategy · People")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("24211")
                    .font(.system(size: 31, weight: .black, design: .rounded).monospacedDigit())
                    .tracking(-2)
                    .foregroundStyle(FTCBrand.orange)
                    .padding(.bottom, 3)
                    .accessibilityLabel("Team 24211")
            }
            .padding(.vertical, 23)
        }
    }

    private var signInPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .signIn ? "Sign in" : "Create your account")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text(mode == .signIn
                     ? "Use your team account to continue."
                     : "Set up your Wild Circuits member profile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            modePicker

            VStack(spacing: 13) {
                if mode == .signUp {
                    inputField("Full name", symbol: "person", text: $name, type: .name,
                               capitalization: .words)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                inputField("Email address", symbol: "envelope", text: $email,
                           type: .emailAddress, capitalization: .never, keyboard: .emailAddress)
                passwordField
            }

            if mode == .signUp {
                profileFields
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let error = authManager.errorMessage {
                Label {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(FTCBrand.orange)
                }
                .font(.footnote)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }

            Button(action: submit) {
                HStack {
                    Spacer()
                    Text(mode == .signIn ? "Continue" : "Create account")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 17)
                .frame(height: 52)
                .background(FTCBrand.midnight, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(FTCBrand.orange)
                        .frame(width: 4, height: 24)
                        .padding(.leading, 1)
                }
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.5)

            if mode == .signIn {
                Label("Account stored on this iPhone", systemImage: "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { option in
                Button {
                    authManager.errorMessage = nil
                    mode = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(.subheadline, design: .rounded,
                                      weight: mode == option ? .semibold : .regular))
                        .foregroundStyle(mode == option ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if mode == option {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func inputField(
        _ title: String,
        symbol: String,
        text: Binding<String>,
        type: UITextContentType,
        capitalization: TextInputAutocapitalization,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(FTCBrand.midnight.opacity(0.68))
                .frame(width: 19)
            TextField(title, text: text)
                .textContentType(type)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 14)
        .frame(height: 51)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private var passwordField: some View {
        HStack(spacing: 11) {
            Image(systemName: "lock")
                .font(.subheadline)
                .foregroundStyle(FTCBrand.midnight.opacity(0.68))
                .frame(width: 19)
            Group {
                if passwordVisible {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .textContentType(mode == .signUp ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                passwordVisible.toggle()
            } label: {
                Image(systemName: passwordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(passwordVisible ? "Hide password" : "Show password")
        }
        .padding(.horizontal, 14)
        .frame(height: 51)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private var profileFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEAM PROFILE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.secondary)

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
                .padding(13)
                .background(Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 12) {
                Text("PROFILE COLOR")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(AvatarColor.allCases) { swatch in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        avatarColor = swatch
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if avatarColor == swatch {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                Circle().stroke(avatarColor == swatch ? Color.primary : .clear, lineWidth: 1.5)
                                    .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(swatch.rawValue) profile color")
                    .accessibilityAddTraits(avatarColor == swatch ? .isSelected : [])
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 9) {
            Rectangle()
                .fill(Color.primary.opacity(0.09))
                .frame(height: 1)
            HStack {
                Text("WILD CIRCUITS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                Spacer()
                Text("NEW JERSEY  ·  EST. 2026")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.3)
            }
            .foregroundStyle(.tertiary)
            Text("Team data stays on this device unless cloud sync is enabled.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 19)
    }

    private var isValid: Bool {
        guard email.contains("@"), password.count >= 4 else { return false }
        return mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch mode {
        case .signIn:
            authManager.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                               password: password)
        case .signUp:
            authManager.signUp(name: name, email: email, password: password,
                               role: role, avatarColor: avatarColor)
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
