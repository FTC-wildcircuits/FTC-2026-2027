import SwiftUI

enum FTCDesign {
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24

    static let controlRadius: CGFloat = 10
    static let cardRadius: CGFloat = 16
    static let minimumHitTarget: CGFloat = 44

    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let secondarySurface = Color(uiColor: .secondarySystemBackground)
    static let label = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
    static let separator = Color(uiColor: .separator)
}

struct FTCBrandCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(FTCDesign.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FTCDesign.secondarySurface,
                in: RoundedRectangle(cornerRadius: FTCDesign.cardRadius, style: .continuous)
            )
    }
}

struct FTCStateChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(tint)
            .padding(.horizontal, FTCDesign.space12)
            .frame(minHeight: FTCDesign.minimumHitTarget)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct FTCLoadingView: View {
    var body: some View {
        VStack(spacing: FTCDesign.space12) {
            ProgressView()
            Text("Loading team records")
                .font(.body)
                .foregroundStyle(FTCDesign.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FTCDesign.groupedBackground.ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Team design system · Light") {
    VStack(alignment: .leading, spacing: FTCDesign.space16) {
        FTCBrandCard {
            VStack(alignment: .leading, spacing: FTCDesign.space12) {
                Text("Inventory status")
                    .font(.headline)
                FTCStateChip(title: "Needs maintenance", systemImage: "wrench.and.screwdriver", tint: .orange)
            }
        }
        FTCLoadingView()
            .frame(height: 100)
    }
    .padding()
    .modelContainer(makePreviewContainer())
    .preferredColorScheme(.light)
}

#Preview("Team design system · Dark") {
    VStack(alignment: .leading, spacing: FTCDesign.space16) {
        FTCBrandCard {
            VStack(alignment: .leading, spacing: FTCDesign.space12) {
                Text("Inventory status")
                    .font(.headline)
                FTCStateChip(title: "Needs maintenance", systemImage: "wrench.and.screwdriver", tint: .orange)
            }
        }
        FTCLoadingView()
            .frame(height: 100)
    }
    .padding()
    .modelContainer(makePreviewContainer())
    .preferredColorScheme(.dark)
}

#Preview("Team design system · Accessibility") {
    VStack(alignment: .leading, spacing: FTCDesign.space16) {
        FTCBrandCard {
            VStack(alignment: .leading, spacing: FTCDesign.space12) {
                Text("Inventory status")
                    .font(.headline)
                FTCStateChip(title: "Needs maintenance", systemImage: "wrench.and.screwdriver", tint: .orange)
            }
        }
        FTCLoadingView()
            .frame(height: 100)
    }
    .padding()
    .modelContainer(makePreviewContainer())
    .dynamicTypeSize(.accessibility5)
}
