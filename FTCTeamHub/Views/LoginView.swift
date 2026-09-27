//
//  LoginView.swift
//  FTCTeamHub
//
//  Native, clean sign-in / account-creation flow. Segmented control toggles
//  between "Sign In" and "Create Account" in one screen rather than
//  separate pushed views, matching Apple's own first-party pattern (see
//  Apple Music / Fitness account screens).
//

import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AuthenticationManager.self) private var authManager

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In", signUp = "Create Account"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role: TeamRole = .builder
    @State private var avatarColor: AvatarColor = .blue
    @State private var isPasswordVisible = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    accessPanel
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(loginBackdrop)
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(FTCBrand.gradient)
                        .frame(width: 54, height: 54)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 25, weight: .black))
                        .foregroundStyle(FTCBrand.midnight)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("WILD CIRCUITS")
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .tracking(2)
                        .foregroundStyle(FTCBrand.cyan)
                    Text("FTC  ·  TEAM 24211")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                Text("2026—27")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.74))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.07), in: Capsule())
            }
            .padding(.top, 26)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.10, green: 0.16, blue: 0.34), FTCBrand.midnight.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                OrbitalRobotArtwork()
                    .frame(width: 180, height: 158)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("ONE TEAM.\nBUILT TO COMPETE.")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .tracking(-0.8)
                        .lineSpacing(-2)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your robot program, connected.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .padding(.leading, 22)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 184)
            .overlay(alignment: .bottomLeading) {
                Capsule()
                    .fill(FTCBrand.gradient)
                    .frame(width: 66, height: 4)
                    .padding(.leading, 22)
                    .offset(y: 2)
            }
            .padding(.top, 24)

            HStack(spacing: 0) {
                heroMetric("BUILD", symbol: "wrench.and.screwdriver.fill")
                metricDivider
                heroMetric("SCOUT", symbol: "scope")
                metricDivider
                heroMetric("GROW", symbol: "arrow.up.right")
            }
            .padding(.top, 18)
        }
    }

    private var accessPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(mode == .signIn ? "Welcome back" : "Join the roster")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text(mode == .signIn ? "Your next great run starts here." : "Create your local team profile.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.54))
                }
                Spacer()
            }

            modeSelector

            VStack(spacing: 12) {
                if mode == .signUp {
                    credentialField("FULL NAME", symbol: "person", text: $name, contentType: .name,
                                    capitalization: .words)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                credentialField("EMAIL ADDRESS", symbol: "envelope", text: $email,
                                contentType: .emailAddress, capitalization: .never,
                                keyboard: .emailAddress)
                passwordField
            }

            if mode == .signUp {
                profileSetup
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let error = authManager.errorMessage {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(FTCBrand.orange)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FTCBrand.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
            }

            submitButton

            if mode == .signIn {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                    Text("Your account stays on this device")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(Color(red: 0.07, green: 0.09, blue: 0.17))
                .overlay {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: mode)
    }

    private var profileSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR TEAM PROFILE")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(FTCBrand.cyan)
            Menu {
                ForEach(TeamRole.allCases) { candidate in
                    Button {
                        role = candidate
                    } label: {
                        Label(candidate.rawValue, systemImage: candidate.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: role.systemImage)
                        .foregroundStyle(FTCBrand.cyan)
                        .frame(width: 20)
                    Text(role.rawValue)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(15)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
            }
            HStack(spacing: 12) {
                ForEach(AvatarColor.allCases) { swatch in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        avatarColor = swatch
                    } label: {
                        Circle()
                            .fill(swatch.color.gradient)
                            .frame(width: 27, height: 27)
                            .padding(4)
                            .overlay {
                                Circle()
                                    .stroke(avatarColor == swatch ? .white : .clear, lineWidth: 1.5)
                            }
                            .overlay {
                                if avatarColor == swatch {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(swatch.rawValue) profile color")
                    .accessibilityAddTraits(avatarColor == swatch ? .isSelected : [])
                }
            }
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 10) {
                Text(mode == .signIn ? "Enter the team hub" : "Create team profile")
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(FTCBrand.midnight)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(FTCBrand.gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: FTCBrand.blue.opacity(0.24), radius: 14, y: 7)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isValid)
        .opacity(isValid ? 1 : 0.54)
    }

    private var isValid: Bool {
        guard email.contains("@"), password.count >= 4 else { return false }
        if mode == .signUp { return !name.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private func submit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch mode {
        case .signIn:
            authManager.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                               password: password)
        case .signUp:
            authManager.signUp(name: name, email: email, password: password, role: role, avatarColor: avatarColor)
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { option in
                Button {
                    authManager.errorMessage = nil
                    mode = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(.subheadline, design: .rounded, weight: mode == option ? .bold : .medium))
                        .foregroundStyle(mode == option ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if mode == option {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.10))
                                    .overlay(alignment: .bottom) {
                                        Capsule().fill(FTCBrand.cyan).frame(width: 32, height: 2)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 16))
    }

    private func credentialField(
        _ title: String,
        symbol: String,
        text: Binding<String>,
        contentType: UITextContentType,
        capitalization: TextInputAutocapitalization,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.48))
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FTCBrand.cyan.opacity(0.86))
                    .frame(width: 20)
                TextField(title.localizedCapitalized, text: text)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .tint(FTCBrand.cyan)
                    .accessibilityLabel(title.localizedCapitalized)
            }
            .padding(.horizontal, 15)
            .frame(height: 53)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PASSWORD")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.48))
            HStack(spacing: 12) {
                Image(systemName: "lock")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FTCBrand.cyan.opacity(0.86))
                    .frame(width: 20)
                Group {
                    if isPasswordVisible {
                        TextField("Your password", text: $password)
                    } else {
                        SecureField("Your password", text: $password)
                    }
                }
                .textContentType(mode == .signUp ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .tint(FTCBrand.cyan)
                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.white.opacity(0.46))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 15)
            .frame(height: 53)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(FTCBrand.cyan).frame(width: 6, height: 6)
                Text("BUILT FOR THE PIT. READY FOR THE FIELD.")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(1.05)
                    .foregroundStyle(.white.opacity(0.44))
            }
            Text("Team data and sign-in stay on this device unless cloud sync is enabled.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.34))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var metricDivider: some View {
        Rectangle().fill(.white.opacity(0.11)).frame(width: 1, height: 20)
    }

    private func heroMetric(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity)
    }

    private var loginBackdrop: some View {
        ZStack(alignment: .topTrailing) {
            FTCBrand.background
            Circle()
                .fill(FTCBrand.blue.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 130, y: 25)
            Circle()
                .fill(FTCBrand.violet.opacity(0.08))
                .frame(width: 230, height: 230)
                .blur(radius: 74)
                .offset(x: -180, y: 410)
        }
        .ignoresSafeArea()
    }
}

private struct OrbitalRobotArtwork: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(FTCBrand.cyan.opacity(0.24), lineWidth: 1)
                .frame(width: 146, height: 146)
            Ellipse()
                .stroke(FTCBrand.blue.opacity(0.64), lineWidth: 1.5)
                .frame(width: 164, height: 64)
                .rotationEffect(.degrees(-34))
            Ellipse()
                .stroke(FTCBrand.violet.opacity(0.72), lineWidth: 1.5)
                .frame(width: 164, height: 64)
                .rotationEffect(.degrees(39))
            Circle()
                .fill(FTCBrand.cyan)
                .frame(width: 6, height: 6)
                .offset(x: 61, y: -44)
            Circle()
                .fill(FTCBrand.orange)
                .frame(width: 7, height: 7)
                .offset(x: -68, y: 23)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.045))
                .frame(width: 75, height: 75)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(FTCBrand.cyan.opacity(0.5), lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 37, weight: .black))
                        .foregroundStyle(FTCBrand.gradient)
                        .shadow(color: FTCBrand.cyan.opacity(0.65), radius: 16)
                }
        }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    authManager.signOut() // show the logged-out state in the preview
    return LoginView()
        .modelContainer(container)
        .environment(authManager)
}
