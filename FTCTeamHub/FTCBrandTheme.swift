import SwiftUI

enum FTCBrand {
    static let midnight = Color(red: 0.035, green: 0.055, blue: 0.14)
    static let navy = Color(red: 0.075, green: 0.11, blue: 0.25)
    static let blue = Color(red: 0.20, green: 0.47, blue: 1.0)
    static let cyan = Color(red: 0.20, green: 0.88, blue: 0.95)
    static let orange = Color(red: 1.0, green: 0.48, blue: 0.20)
    static let violet = Color(red: 0.55, green: 0.38, blue: 1.0)

    static let gradient = LinearGradient(
        colors: [blue, violet, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let background = LinearGradient(
        colors: [midnight, Color(red: 0.055, green: 0.08, blue: 0.19), midnight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct FTCBrandMark: View {
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Circle()
                .fill(FTCBrand.gradient.opacity(0.2))
                .frame(width: size, height: size)
                .overlay {
                    Circle().stroke(FTCBrand.cyan.opacity(0.55), lineWidth: 1)
                }
            Circle()
                .stroke(FTCBrand.blue.opacity(0.7), lineWidth: 1)
                .frame(width: size * 0.72, height: size * 0.72)
                .rotation3DEffect(.degrees(62), axis: (x: 1, y: 0, z: 0))
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.34, weight: .black))
                .foregroundStyle(FTCBrand.gradient)
                .shadow(color: FTCBrand.cyan.opacity(0.6), radius: size * 0.12)
        }
        .accessibilityLabel("FTC Team Hub")
    }
}

struct FTCBrandCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(FTCBrand.cyan.opacity(0.18), lineWidth: 1)
                    }
            }
    }
}

struct FTCLoadingView: View {
    var body: some View {
        ZStack {
            FTCBrand.background.ignoresSafeArea()
            VStack(spacing: 22) {
                FTCBrandMark(size: 104)
                    .symbolEffect(.pulse, options: .repeating)
                VStack(spacing: 6) {
                    Text("WILD CIRCUITS")
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .tracking(3)
                        .foregroundStyle(FTCBrand.cyan)
                    Text("Team Hub")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }
                ProgressView()
                    .tint(FTCBrand.cyan)
                    .padding(.top, 8)
                Text("Preparing your team workspace")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(36)
        }
        .preferredColorScheme(.dark)
    }
}
