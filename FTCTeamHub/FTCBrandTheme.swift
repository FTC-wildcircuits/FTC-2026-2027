import SwiftUI

enum FTCBrand {
    static let midnight = Color(red: 0.035, green: 0.055, blue: 0.14)
    static let navy = Color(red: 0.075, green: 0.11, blue: 0.25)
    static let blue = Color(red: 0.14, green: 0.31, blue: 0.55)
    static let cyan = Color(red: 0.16, green: 0.54, blue: 0.62)
    static let orange = Color(red: 0.91, green: 0.29, blue: 0.12)
    static let violet = Color(red: 0.39, green: 0.35, blue: 0.55)
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let ink = Color(uiColor: .label)
    static let secondaryInk = Color(uiColor: .secondaryLabel)
    static let line = Color(uiColor: .separator).opacity(0.45)
    static let background = midnight
}

struct FTCBrandMark: View {
    var size: CGFloat = 76

    var body: some View {
        Text("WC")
            .font(.system(size: size * 0.31, weight: .black, design: .rounded))
            .tracking(-size * 0.025)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(FTCBrand.orange, in: RoundedRectangle(cornerRadius: size * 0.2))
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
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    }
            }
    }
}

struct FTCLoadingView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    FTCBrandMark(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WILD CIRCUITS")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.secondary)
                        Text("Team workspace")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                    }
                }
                Rectangle().fill(FTCBrand.line).frame(height: 1)
                HStack(spacing: 11) {
                    ProgressView().tint(FTCBrand.orange)
                    Text("Opening team records…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
